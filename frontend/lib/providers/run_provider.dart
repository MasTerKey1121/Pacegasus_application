import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/run_result.dart';
import '../models/side_quest.dart';
import '../services/running_session_api.dart';
import 'auth_provider.dart';
import 'run_setup_provider.dart';

/// Drives the running screen using elapsed time plus GPS distance updates.
class RunSessionNotifier extends ChangeNotifier {
  RunSessionNotifier(this._sessionApi);
  final RunningSessionApi _sessionApi;

  Timer? _timer;
  bool isRunning = false;
  bool isPaused = false;
  bool isStopping = false;
  int elapsedSeconds = 0;
  double distanceKm = 0;
  double speedKmh = 0;

  final double goalDistanceKm = 5.0;
  final String goalPace = '7 min/km';

  RunResult? lastResult;

  void start() {
    isRunning = true;
    isPaused = false;
    elapsedSeconds = 0;
    distanceKm = 0;
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (isPaused) return;
      elapsedSeconds += 1;
      notifyListeners();
    });
    notifyListeners();
  }

  void togglePause() {
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
  }) {
    _timer?.cancel();
    elapsedSeconds = elapsed;
    distanceKm = distance;
    isRunning = true;
    isPaused = paused;
    speedKmh = 0;
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!isPaused) elapsedSeconds += 1;
      notifyListeners();
    });
    notifyListeners();
  }

  Future<RunResult?> stop({
    required String sessionId,
    required List<ActiveSideQuest> sideQuests,
    double? endLat,
    double? endLng,
    List<Map<String, double>> routePoints = const [],
  }) async {
    if (isStopping) return null; // กันกดปุ่ม "จบการวิ่ง" ซ้ำ
    _timer?.cancel();
    isRunning = false;
    isStopping = true;
    notifyListeners();

    try {
      await _sessionApi.complete(
        sessionId: sessionId,
        distanceKm: distanceKm,
        durationSeconds: elapsedSeconds,
        endLat: endLat ?? 13.7563,
        endLng: endLng ?? 100.5018,
        routePoints: routePoints,
      );

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
        routePoints: RunRoutePoint.parse(routePoints),
      );

      return lastResult;
    } catch (e) {
      debugPrint(e.toString());
      return null;
    } finally {
      isStopping = false;
      notifyListeners();
    }
  }

  String get elapsedLabel {
    final m = (elapsedSeconds ~/ 60).toString().padLeft(2, '0');
    final s = (elapsedSeconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  void reset() {
    _timer?.cancel();
    _timer = null;
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
    _timer?.cancel();
    super.dispose();
  }
}

final runProvider = ChangeNotifierProvider<RunSessionNotifier>((ref) {
  final notifier = RunSessionNotifier(
    ref.read(runningSessionApiProvider),
  );
  ref.listen<AuthState>(authProvider, (previous, next) {
    if (previous?.user?['id'] != next.user?['id']) notifier.reset();
  });
  return notifier;
});
