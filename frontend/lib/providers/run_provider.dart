import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/run_result.dart';
import '../models/side_quest.dart';
import '../services/running_session_api.dart';
import '../services/api_client.dart';
import '../services/run_finish_operation.dart';
import 'auth_provider.dart';
import 'run_setup_provider.dart';

/// Drives the running screen using elapsed time plus GPS distance updates.
class RunSessionNotifier extends ChangeNotifier {
  RunSessionNotifier(this._sessionApi,
      {this.ownerUserId,
      Duration Function()? elapsedClock,
      this.finishLimit = const Duration(seconds: 120),
      this.localStepLimit = const Duration(seconds: 10),
      this.gpsStopLimit = const Duration(seconds: 5),
      this.recoveryDelay = const Duration(seconds: 2)})
      : _elapsedClock = elapsedClock;
  final String? ownerUserId;
  final Duration finishLimit, localStepLimit, gpsStopLimit, recoveryDelay;
  bool _preparingFinish = false;
  bool get finishBusy => _preparingFinish || isStopping;
  bool checkpointSaved = false;
  String? finishStage;
  String? finishReference;
  String? finishWarning;
  String get finishMessage => switch (finishStage) {
        'confirmed' => 'บันทึกผลวิ่งแล้ว',
        'gps_stop' => 'กำลังหยุดการติดตาม GPS',
        'checkpoint' => 'กำลังเก็บข้อมูลการวิ่ง',
        'connecting' => 'กำลังเชื่อมต่อเซิร์ฟเวอร์ ผลวิ่งยังเก็บไว้',
        'auth_refresh' => 'กำลังต่ออายุการเชื่อมต่อ',
        'session_detail' => 'กำลังตรวจสอบสถานะการวิ่ง',
        'complete' => 'กำลังบันทึกผลการวิ่ง',
        _ => 'กำลังเตรียมบันทึกผลการวิ่ง',
      };
  String? finishError;
  int _generation = 0;
  bool _disposed = false;
  final RunningSessionApi _sessionApi;
  final Duration Function()? _elapsedClock;
  final Stopwatch _monotonicClock = Stopwatch()..start();
  Duration _recordedTime = Duration.zero;
  Duration? _activeSince;

  Duration get _now => _elapsedClock?.call() ?? _monotonicClock.elapsed;
  Duration get _elapsedTime {
    final since = _activeSince;
    if (since == null) return _recordedTime;
    final active = _now - since;
    return _recordedTime + (active.isNegative ? Duration.zero : active);
  }

  // Timer callbacks may be delayed while Android is drawing another app or
  // the screen is locked. Elapsed time must not depend on callback counts.
  int get elapsedSeconds => _elapsedTime.inSeconds;
  set elapsedSeconds(int seconds) {
    _recordedTime = Duration(seconds: seconds < 0 ? 0 : seconds);
    if (_activeSince != null) _activeSince = _now;
  }

  void _freezeClock() {
    _recordedTime = _elapsedTime;
    _activeSince = null;
  }

  void refreshElapsedTime() {
    if (!_disposed && isRunning) notifyListeners();
  }

  Timer? _timer;
  bool isRunning = false;
  bool isPaused = false;
  bool isStopping = false;
  double distanceKm = 0;
  double speedKmh = 0;

  RunResult? lastResult;

  void start() {
    _generation++;
    _preparingFinish = false;
    isStopping = false;
    checkpointSaved = false;
    finishStage = null;
    finishWarning = null;
    finishError = null;
    lastResult = null;
    isRunning = true;
    isPaused = false;
    elapsedSeconds = 0;
    distanceKm = 0;
    speedKmh = 0;
    _activeSince = _now;
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (isPaused) return;
      notifyListeners();
    });
    notifyListeners();
  }

  void togglePause() {
    if (!isRunning || isStopping) return;
    if (isPaused) {
      _activeSince = _now;
    } else {
      _freezeClock();
      speedKmh = 0;
    }
    isPaused = !isPaused;
    notifyListeners();
  }

  void recordGpsDistance({required double meters, required double seconds}) {
    if (!isRunning || isPaused || meters <= 0 || seconds <= 0) return;
    distanceKm += meters / 1000;
    speedKmh = (meters / seconds) * 3.6;
    notifyListeners();
  }

  /// Treadmill sessions use the distance shown by the treadmill instead of GPS.
  void setDistance(double kilometers) {
    distanceKm = kilometers < 0 ? 0 : kilometers;
    speedKmh = elapsedSeconds > 0 ? (distanceKm / elapsedSeconds) * 3600 : 0;
    notifyListeners();
  }

  void restore({
    required int elapsed,
    required double distance,
    required bool paused,
    bool pendingCompletion = false,
  }) {
    _generation++;
    _preparingFinish = false;
    isStopping = false;
    lastResult = null;
    _timer?.cancel();
    elapsedSeconds = elapsed;
    distanceKm = distance;
    isRunning = !pendingCompletion;
    finishError = pendingCompletion
        ? 'ยังไม่ทราบผลการบันทึก กรุณาลองบันทึกใหม่เพื่อตรวจสถานะ'
        : null;
    isPaused = paused;
    speedKmh = 0;
    _activeSince = isRunning && !isPaused ? _now : null;
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      notifyListeners();
    });
    notifyListeners();
  }

  void prepareFinish() {
    _timer?.cancel();
    _freezeClock();
    isRunning = false;
    speedKmh = 0;
    notifyListeners();
  }

  /// The entire finish attempt has one deadline, including work before HTTP.
  /// The frozen checkpoint is persisted before waiting for GPS cancellation.
  Future<RunResult?> finish({
    required String sessionId,
    required List<ActiveSideQuest> sideQuests,
    required Future<void> Function() persistCheckpoint,
    required Future<void> Function() stopGps,
    required double endLat,
    required double endLng,
    List<Map<String, double>> routePoints = const [],
  }) async {
    if (finishBusy || _disposed) return null;
    final generation = _generation;
    _preparingFinish = true;
    finishError = null;
    finishWarning = null;
    prepareFinish();
    final operation = RunFinishOperation(
        limit: finishLimit,
        isCurrent: () => !_disposed && generation == _generation,
        onStage: (stage) {
          if (_disposed || generation != _generation) return;
          finishStage = stage;
          notifyListeners();
        });
    finishReference = operation.reference;
    try {
      operation.stage('confirm_finish');
      operation.log('gps_stop_requested');
      final gpsStopping = Future<void>.sync(stopGps);
      // Observe an immediate native error while the checkpoint is being saved.
      // The original future is still awaited below and remains retryable.
      unawaited(
          gpsStopping.then((_) {}, onError: (Object _, StackTrace __) {}));
      operation.stage('checkpoint');
      await operation.wait(persistCheckpoint, cap: localStepLimit);
      checkpointSaved = true;
      operation.log('checkpoint_saved');
      operation.stage('gps_stop');
      try {
        await operation.wait(() => gpsStopping, cap: gpsStopLimit);
        operation.log('gps_stopped');
      } catch (_) {
        operation.check();
        // Time/distance/route are frozen and durable. A stuck native cleanup
        // must not force restarting the app just to submit those same values.
        operation.log('gps_stop_pending');
        finishWarning =
            'บันทึกผลวิ่งแล้ว แต่ระบบ GPS ยังไม่ยืนยันว่าหยุด กรุณาตรวจการแจ้งเตือนการวิ่ง';
        notifyListeners();
      }
      return await operation.run(() => stop(
          sessionId: sessionId,
          sideQuests: sideQuests,
          endLat: endLat,
          endLng: endLng,
          routePoints: routePoints));
    } catch (_) {
      if (!_disposed && generation == _generation) {
        operation.log('preparation_failed');
        finishError = checkpointSaved
            ? 'ยังบันทึกไม่สำเร็จ ผลวิ่งเก็บไว้ในเครื่องแล้ว กรุณาลองบันทึกใหม่'
            : 'เก็บผลวิ่งลงเครื่องยังไม่สำเร็จ ข้อมูลยังอยู่ในหน้านี้ กรุณาลองใหม่ก่อนปิดแอป';
      }
      return null;
    } finally {
      operation.close();
      if (!_disposed && generation == _generation) {
        _preparingFinish = false;
        notifyListeners();
      }
    }
  }

  bool _transient(Object error) =>
      error is TimeoutException ||
      (error is ApiException &&
          [0, 408, 429, 500, 502, 503, 504].contains(error.statusCode));

  Future<Map<String, dynamic>> _readForFinish(
      String sessionId, RunFinishOperation? operation) async {
    Future<Map<String, dynamic>> read() async {
      operation?.stage('session_detail');
      return operation == null
          ? _sessionApi.getDetail(sessionId: sessionId)
          : operation.wait(() => _sessionApi.getDetail(sessionId: sessionId));
    }

    try {
      return await read();
    } catch (error) {
      if (operation == null || !_transient(error)) rethrow;
      operation.log('detail_unavailable',
          status: error is ApiException ? error.statusCode : 0);
    }
    // This is active recovery only while finishing, never an app keepalive.
    for (var attempt = 1; attempt <= 3; attempt++) {
      operation.stage('connecting');
      await operation.wait(() => Future<void>.delayed(recoveryDelay * attempt));
      try {
        final health = await operation.wait(_sessionApi.health);
        if (health['success'] != true) {
          throw ApiException(503, 'เซิร์ฟเวอร์ยังไม่พร้อม');
        }
        operation.log('health_ready');
        return await read(); // Health never stands in for session ownership/status.
      } catch (error) {
        if (!_transient(error) || attempt == 3) rethrow;
        operation.log('recovery_wait',
            status: error is ApiException ? error.statusCode : 0);
      }
    }
    throw StateError('ยังตรวจสถานะการวิ่งไม่ได้');
  }

  Future<RunResult?> stop({
    required String sessionId,
    required List<ActiveSideQuest> sideQuests,
    double? endLat,
    double? endLng,
    List<Map<String, double>> routePoints = const [],
  }) async {
    final operation = RunFinishOperation.current;
    if (isStopping || lastResult != null) {
      return lastResult;
    } // กันกดปุ่ม "จบการวิ่ง" ซ้ำ
    final generation = _generation;
    _timer?.cancel();
    _freezeClock();
    isRunning = false;
    isStopping = true;
    finishError = null;
    notifyListeners();

    try {
      Map? confirmed;
      // Reconcile before completing, including a timeout whose write may
      // have committed. A failed detail read must never cause another PATCH.
      {
        final response = await _readForFinish(sessionId, operation);
        if (_disposed || generation != _generation) return null;
        confirmed = response['data'] as Map;
        if (confirmed['id'] != sessionId ||
            (ownerUserId != null &&
                confirmed['user_id']?.toString() != ownerUserId)) {
          throw StateError('ไม่สามารถยืนยันเจ้าของ Session');
        }
        if (confirmed['status'] != 'completed' &&
            confirmed['status'] != 'in_progress') {
          throw StateError('Session นี้ไม่สามารถบันทึกซ้ำได้');
        }
      }
      if (confirmed['status'] != 'completed') {
        operation?.stage('complete');
        Future<Map<String, dynamic>> send() => _sessionApi.complete(
              sessionId: sessionId,
              distanceKm: distanceKm,
              durationSeconds: elapsedSeconds,
              endLat: endLat ?? 13.7563,
              endLng: endLng ?? 100.5018,
              routePoints: routePoints,
            );

        Map<String, dynamic> response;
        try {
          response =
              operation == null ? await send() : await operation.wait(send);
        } catch (error) {
          if (operation == null || !_transient(error)) rethrow;
          operation.log('complete_uncertain',
              status: error is ApiException ? error.statusCode : 0);
          // A write may have committed. Only read here; retrying the button
          // starts another attempt with detail before any new PATCH.
          response = await _readForFinish(sessionId, operation);
        }

        if (_disposed || generation != _generation) return null;
        confirmed = response['data'] as Map?;
      }
      if (confirmed?['status'] != 'completed' ||
          confirmed?['id'] != sessionId ||
          (ownerUserId != null &&
              confirmed?['user_id']?.toString() != ownerUserId)) {
        throw StateError('ยังไม่ได้รับการยืนยันการบันทึก Session');
      }
      operation?.stage('confirmed');
      distanceKm = double.parse('${confirmed!['distance_km']}');
      elapsedSeconds = int.parse('${confirmed['duration_seconds']}');
      // การจบวิ่งไม่ถือว่าทำ Side Quest สำเร็จ รางวัลให้เฉพาะภารกิจ
      // ที่ผู้ใช้กดทำสำเร็จผ่าน RunSetupNotifier.completeSideQuest เท่านั้น

      final duration = Duration(seconds: elapsedSeconds);

      final paceMinPerKm =
          distanceKm > 0 ? (elapsedSeconds / 60) / distanceKm : 0;

      final mm = paceMinPerKm.floor();

      final ss = ((paceMinPerKm - mm) * 60).round().toString().padLeft(2, '0');

      lastResult = RunResult(
        distanceKm: double.parse(distanceKm.toStringAsFixed(2)),
        duration: duration,
        avgPace: distanceKm > 0 ? '$mm:$ss' : '--:--',
        calories: (distanceKm * 62).round(),
        routePoints: RunRoutePoint.parse(confirmed['route_points']).isNotEmpty
            ? RunRoutePoint.parse(confirmed['route_points'])
            : RunRoutePoint.parse(routePoints),
      );

      return lastResult;
    } catch (e) {
      if (!_disposed && generation == _generation) {
        operation?.log('finish_pending',
            status: e is ApiException ? e.statusCode : null);
        finishError = operation == null
            ? 'บันทึกการวิ่งไม่สำเร็จ: $e'
            : 'ยังยืนยันผลบันทึกไม่ได้ ผลวิ่งเก็บไว้ในเครื่องแล้ว กรุณาลองบันทึกใหม่ ระบบจะตรวจสถานะก่อนส่งซ้ำ';
      }
      return null;
    } finally {
      if (!_disposed && generation == _generation) {
        isStopping = false;
        notifyListeners();
      }
    }
  }

  String get elapsedLabel {
    final m = (elapsedSeconds ~/ 60).toString().padLeft(2, '0');
    final s = (elapsedSeconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  void reset() {
    _generation++;
    _preparingFinish = false;
    checkpointSaved = false;
    finishStage = null;
    finishWarning = null;
    finishError = null;
    _timer?.cancel();
    _timer = null;
    _activeSince = null;
    isRunning = false;
    isPaused = false;
    isStopping = false;
    elapsedSeconds = 0;
    distanceKm = 0;
    speedKmh = 0;
    lastResult = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _generation++;
    _timer?.cancel();
    _monotonicClock.stop();
    super.dispose();
  }
}

final runProvider = ChangeNotifierProvider<RunSessionNotifier>((ref) {
  final owner = ref.watch(authProvider.select((s) => s.user?['id']));
  final notifier = RunSessionNotifier(
    ref.read(runningSessionApiProvider),
    ownerUserId: owner?.toString(),
  );
  return notifier;
});
