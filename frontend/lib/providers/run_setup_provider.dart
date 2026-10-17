import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/side_quest.dart';
import '../models/training_date.dart';
import '../services/quest_api.dart';
import '../services/api_client.dart';
import '../services/running_session_api.dart';
import '../services/daily_side_quest_store.dart';
import '../services/run_draft_store.dart';
import 'auth_provider.dart';
import 'progress_provider.dart';
import 'training_day_provider.dart';
import 'run_provider.dart';

final questApiProvider =
    Provider<QuestApi>((ref) => QuestApi(ref.read(apiClientProvider)));
final runningSessionApiProvider = Provider<RunningSessionApi>(
    (ref) => RunningSessionApi(ref.read(apiClientProvider)));
String mapToSideQuestTrainingType(String? type) => switch (type) {
      'vo2max' => 'interval',
      'tempo' => 'tempo',
      'long_run' => 'long_run',
      _ => 'easy',
    };

class RunSetupNotifier extends ChangeNotifier {
  RunSetupNotifier(this._questApi, this._sessionApi,
      {this.owner,
      this.store,
      this.onReward,
      this.isRunning,
      String Function()? day})
      : _today = day ?? (() => trainingDateKey(trainingToday())!) {
    _day = _today();
  }
  final QuestApi _questApi;
  final RunningSessionApi _sessionApi;
  final String? owner;
  final DailySideQuestStore? store;
  final VoidCallback? onReward;
  final bool Function()? isRunning;
  final String Function() _today;
  late String _day;
  bool _alive = true;
  String? environment, sessionId, sessionType;
  List<Map<String, double>> restoredRoute = [];
  List<SideQuest> sideQuests = [];
  List<ActiveSideQuest> activeSideQuests = [];
  List<String> sideQuestIds = [];
  List<Map<String, dynamic>> _daily = [];
  String? _boundSession;
  bool _generationUnknown = false;
  bool canRetryQuests = false;
  bool _retryUnsentGeneration = false;
  bool get sideQuestLoadUncertain => _generationUnknown && _daily.isEmpty;
  int? _lastQuestErrorStatus;
  bool isLoadingQuests = false, isStarting = false;
  String? errorMessage;
  final Set<String> _completingIds = {};
  Future<void> _writes = Future.value();
  Set<String> get selectedInstanceIds => _daily
      .where((q) => q['done'] != true && q['bound'] == null)
      .map((q) => q['instanceId'].toString())
      .toSet();
  bool get dailyComplete =>
      _daily.isNotEmpty && _daily.every((q) => q['done'] == true);
  bool isDone(String id) =>
      _daily.any((q) => q['instanceId'] == id && q['done'] == true);
  bool isCompletingQuest(String id) => _completingIds.contains(id);
  bool canFinish(String id) =>
      _today() == _day &&
      sessionId != null &&
      (isRunning?.call() ?? true) &&
      _daily.any((q) =>
          q['instanceId'] == id &&
          q['bound'] == sessionId &&
          q['activated'] == true &&
          q['done'] != true);

  Future<void> restoreDaily() async {
    if (isLoadingQuests || isStarting || !_alive) return;
    final day = _day;
    try {
      if (owner == null) return;
      final cached = await store?.load(owner!, day);
      if (!_alive ||
          day != _day ||
          cached == null ||
          isLoadingQuests ||
          isStarting) {
        return;
      }
      _daily = (cached['quests'] as List)
          .map((q) => Map<String, dynamic>.from(q as Map))
          .toList();
      _boundSession = cached['boundSession']?.toString();
      _generationUnknown = cached['generationUnknown'] == true;
      _lastQuestErrorStatus = (cached['lastQuestErrorStatus'] as num?)?.toInt();
      _showDaily();
      notifyListeners();
    } catch (e) {
      if (_alive) {
        errorMessage = 'อ่าน Side Quest ที่เก็บไว้ไม่สำเร็จ: $e';
        notifyListeners();
      }
    }
  }

  void checkDay() {
    if (_day == _today()) return;
    _day = _today();
    _daily = [];
    sideQuests = [];
    activeSideQuests = [];
    _boundSession = null;
    _generationUnknown = false;
    canRetryQuests = false;
    _lastQuestErrorStatus = null;
    _retryUnsentGeneration = false;
    errorMessage =
        'วันใหม่แล้ว กรุณาเลือกประเภทการวิ่งเพื่อโหลด Side Quest ของวันนี้';
    notifyListeners();
  }

  Future<void> _persist() {
    if (owner == null || store == null) return Future.value();
    final day = _day;
    final snapshot = <String, dynamic>{
      'quests': _daily.map((q) => Map<String, dynamic>.from(q)).toList(),
      'boundSession': _boundSession,
      'retryable': canRetryQuests,
      'lastQuestErrorStatus': _lastQuestErrorStatus,
      'generationUnknown': _generationUnknown
    };
    final next = _writes.then((_) => store!.save(owner!, day, snapshot));
    _writes = next.then((_) {}, onError: (Object _, StackTrace __) {});
    return next;
  }

  void _showDaily() {
    for (final quest in _daily) {
      if (quest['status'] == 'completed') quest['done'] = true;
    }
    sideQuests = _daily.map(SideQuest.fromJson).toList();
    activeSideQuests = _daily
        .where((q) => q['bound'] != null)
        .map((q) => ActiveSideQuest(
            sideQuestId: q['instanceId'].toString(),
            title: '${q['title']}',
            description: '${q['description'] ?? ''}',
            coinReward: (q['coinRewardBase'] as num?)?.toInt() ?? 0,
            done: q['done'] == true))
        .toList();
    sideQuestIds = activeSideQuests.map((q) => q.sideQuestId).toList();
  }

  Future<void> retrySideQuests() async {
    if (!canRetryQuests || environment == null) return;
    await selectEnvironment(
        env: environment!, mainQuestSessionType: sessionType);
  }

  Future<void> selectEnvironment(
      {required String env, required String? mainQuestSessionType}) async {
    if (isLoadingQuests || isStarting) return;
    checkDay();
    final day = _day;
    environment = env;
    sessionType = mainQuestSessionType;
    isLoadingQuests = true;
    canRetryQuests = false;
    errorMessage = null;
    var cacheLoaded = false;
    var sent = false;
    var received = false;
    notifyListeners();
    try {
      final cached = owner == null ? null : await store?.load(owner!, day);
      if (!_alive || day != _day) return;
      cacheLoaded = true;
      if (cached != null && _daily.isEmpty) {
        _daily = (cached['quests'] as List)
            .map((q) => Map<String, dynamic>.from(q as Map))
            .toList();
        _boundSession = cached['boundSession']?.toString();
        _generationUnknown = cached['generationUnknown'] == true;
        _lastQuestErrorStatus =
            (cached['lastQuestErrorStatus'] as num?)?.toInt();
      }
      // A stored request marker is NOT evidence of quest completion. Reuse a
      // known set; only retry generation when an explicit pre-write rejection
      // or a locally unsent request proves no replacement is being created.
      final rejected =
          [400, 401, 403, 404, 422].contains(_lastQuestErrorStatus);
      if (_generationUnknown &&
          (_daily.isNotEmpty || rejected || _retryUnsentGeneration)) {
        _generationUnknown = false;
      }
      if (_generationUnknown) {
        _showDaily();
        errorMessage =
            'ยังตรวจสอบผลการโหลด Side Quest ครั้งก่อนไม่ได้ ไม่ได้หมายความว่าทำภารกิจแล้ว จึงไม่สร้างชุดซ้ำในวันนี้ · ยังวิ่งอิสระได้';
        return;
      }
      if (_daily.isEmpty &&
          (cached == null ||
              rejected ||
              _retryUnsentGeneration ||
              cached['retryable'] == true)) {
        _generationUnknown = true;
        _lastQuestErrorStatus = null;
        await _persist();
        _retryUnsentGeneration = false;
        sent = true;
        final response = await _questApi.getTodaySideQuests(
            environment: env,
            trainingType: mapToSideQuestTrainingType(mainQuestSessionType));
        if (!_alive || day != _day) return;
        final items = ((response['data'] as Map)['quests'] as List)
            .map((q) => Map<String, dynamic>.from(q as Map))
            .toList();
        if (items.any((q) =>
            q['instanceId'] == null || q['instanceId'].toString().isEmpty)) {
          throw const FormatException('Missing instance ID');
        }
        _daily = items
            .map((q) => {...q, 'done': q['status'] == 'completed'})
            .toList();
        received = true;
        _generationUnknown = false;
      }
      _showDaily();
      await _persist();
      if (_boundSession != null &&
          _boundSession != sessionId &&
          !dailyComplete) {
        errorMessage =
            'Side Quest ที่ค้างอยู่กับการวิ่งรอบเดิม ยังทำต่อในรอบใหม่ไม่ได้ · วิ่งอิสระต่อได้';
      }
    } catch (e) {
      if (_alive && day == _day) {
        final rejected = e is ApiException &&
            [400, 401, 403, 404, 422].contains(e.statusCode);
        if (cacheLoaded) {
          _lastQuestErrorStatus = e is ApiException ? e.statusCode : null;
          _generationUnknown = sent && !received && !rejected;
          _retryUnsentGeneration = !sent && _daily.isEmpty;
        }
        canRetryQuests = !cacheLoaded || !_generationUnknown;
        _showDaily();
        final reason = e is ApiException
            ? e.message
            : 'กรุณาตรวจสอบการเชื่อมต่อหรือพื้นที่เก็บข้อมูล';
        errorMessage = _generationUnknown
            ? 'ยังไม่ได้รับผลยืนยันการโหลด Side Quest: $reason · ไม่ได้หมายความว่าทำภารกิจแล้ว'
            : 'โหลด Side Quest ไม่สำเร็จ: $reason';
        if (cacheLoaded) {
          try {
            await _persist();
          } catch (_) {/* Preserve the known set in memory. */}
        }
      }
    } finally {
      if (_alive) {
        isLoadingQuests = false;
        notifyListeners();
      }
    }
  }

  Future<bool> startRun({required String? mainQuestSessionType}) async {
    if (environment == null || isLoadingQuests || isStarting) return false;
    checkDay();
    final startingDay = _day;
    isStarting = true;
    errorMessage = null;
    sessionType = mainQuestSessionType ?? 'easy';
    notifyListeners();
    try {
      if (owner != null) {
        final draft =
            await verifiedRunDraft(runDraftStore, _sessionApi, owner!);
        if (!_alive) return false;
        if (draft != null) {
          throw StateError(
              'มี Session ที่ยังไม่จบ กรุณากลับหน้าหลักและเปิดการวิ่งเดิมก่อน');
        }
      }
      final res = await _sessionApi.start(
          environment: environment!,
          sessionType: sessionType!,
          startLat: 13.7563,
          startLng: 100.5018);
      if (!_alive) return false;
      final data = res['data'] as Map;
      sessionId = data['id']?.toString();
      if (sessionId == null ||
          (owner != null && data['user_id']?.toString() != owner)) {
        throw StateError('ไม่สามารถยืนยัน Session ใหม่');
      }
      if (owner != null) {
        await runDraftStore.save({
          'ownerUserId': owner,
          'sessionId': sessionId,
          'environment': environment,
          'sessionType': sessionType,
          'elapsedSeconds': 0,
          'distanceKm': 0,
          'isPaused': false,
          'sideQuests': [],
          'routePoints': []
        });
      }
      final ids = startingDay == _day && startingDay == _today()
          ? selectedInstanceIds.toList()
          : <String>[];
      if (ids.isNotEmpty) {
        _boundSession = sessionId;
        for (final q in _daily) {
          if (ids.contains(q['instanceId'])) q['bound'] = sessionId;
        }
        await _persist(); // A lost activation response cannot cause reassignment.
        try {
          final response = await _questApi.startSideQuests(
              sessionId: sessionId!, instanceIds: ids);
          if (!_alive) return false;
          for (final item in (response['data'] as List).whereType<Map>()) {
            final match = _daily.where((q) => q['instanceId'] == item['id']);
            if (match.isNotEmpty) {
              match.first['templateId'] = item['sideQuestTemplateId'];
              match.first['activated'] = item['status'] == 'in_progress';
            }
          }
          await _persist();
        } catch (e) {
          errorMessage =
              'เริ่มวิ่งแล้ว แต่ยืนยันการเริ่ม Side Quest ไม่สำเร็จ: $e';
        }
      }
      _showDaily();
      if (_boundSession != null &&
          _boundSession != sessionId &&
          !dailyComplete) {
        errorMessage =
            'Side Quest ที่ค้างอยู่กับการวิ่งรอบเดิม ยังทำต่อในรอบใหม่ไม่ได้ · วิ่งอิสระต่อได้';
      }
      return true;
    } catch (e) {
      if (_alive) errorMessage = e.toString();
      return false;
    } finally {
      if (_alive) {
        isStarting = false;
        notifyListeners();
      }
    }
  }

  Future<void> completeSideQuest(String id) async {
    if (!canFinish(id) || _completingIds.contains(id)) return;
    final day = _day;
    final session = sessionId!;
    final completingSet = _daily;
    _completingIds.add(id);
    errorMessage = null;
    notifyListeners();
    try {
      final response = await _sessionApi.getDetail(sessionId: session);
      if (!_alive || day != _day || !canFinish(id)) return;
      final detail = response['data'] as Map;
      if (detail['status'] != 'in_progress' ||
          detail['id'] != session ||
          (owner != null && detail['user_id']?.toString() != owner)) {
        throw StateError('กดจบภารกิจได้เฉพาะ Session ที่กำลังวิ่ง');
      }
      final result =
          (await _questApi.finishSideQuest(sideQuestId: id))['data'] as Map;
      if (!_alive) return;
      if (result['id'] != id ||
          result['status'] != 'completed' ||
          result['runningSessionId'] != session ||
          (owner != null && result['userId']?.toString() != owner)) {
        throw StateError('ยังไม่ได้รับการยืนยันจาก server');
      }
      completingSet.firstWhere((q) => q['instanceId'] == id)['done'] = true;
      onReward?.call();
      if (day != _day) {
        if (store != null && owner != null) {
          await store!.save(owner!, day, {
            'quests': completingSet,
            'boundSession': session,
            'generationUnknown': false
          });
        }
        return;
      }
      _showDaily();
      final quest = activeSideQuests.firstWhere((q) => q.sideQuestId == id);
      quest.confirmedCoins = (result['coinAwarded'] as num?)?.toInt();
      try {
        await _persist();
      } catch (e) {
        errorMessage = 'server ยืนยันแล้ว แต่เก็บสถานะในอุปกรณ์ไม่สำเร็จ: $e';
      }
    } catch (e) {
      if (_alive && day == _day) {
        errorMessage = 'จบภารกิจไม่สำเร็จ ลองใหม่ได้: $e';
      }
    } finally {
      if (_alive) {
        _completingIds.remove(id);
        notifyListeners();
      }
    }
  }

  void restoreDraft(Map<String, dynamic> draft) {
    environment = draft['environment']?.toString();
    sessionId = draft['sessionId']?.toString();
    sessionType = draft['sessionType']?.toString();
    restoredRoute = ((draft['routePoints'] as List?) ?? [])
        .whereType<Map>()
        .map((p) => {
              'lat': (p['lat'] as num).toDouble(),
              'lng': (p['lng'] as num).toDouble()
            })
        .toList();
    notifyListeners();
    if (environment != null) {
      selectEnvironment(env: environment!, mainQuestSessionType: sessionType);
    }
  }

  void reset() {
    environment = null;
    sessionId = null;
    sessionType = null;
    restoredRoute = [];
    activeSideQuests = [];
    sideQuestIds = [];
    // Daily set/completed state survives new runs and feedback on the same day.
    notifyListeners();
  }

  @override
  void dispose() {
    _alive = false;
    super.dispose();
  }
}

final runSetupProvider = ChangeNotifierProvider<RunSetupNotifier>((ref) {
  final owner =
      ref.watch(authProvider.select((s) => s.user?['id']))?.toString();
  final notifier = RunSetupNotifier(
      ref.read(questApiProvider), ref.read(runningSessionApiProvider),
      owner: owner,
      store: const DailySideQuestStore(),
      onReward: () => ref.invalidate(progressProvider),
      isRunning: () =>
          ref.read(runProvider).isRunning && !ref.read(runProvider).isStopping);
  scheduleMicrotask(notifier.restoreDaily);
  ref.listen<String>(trainingDayProvider, (_, __) => notifier.checkDay());
  return notifier;
});
