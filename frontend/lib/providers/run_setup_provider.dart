import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/side_quest.dart';
import '../models/run_reward.dart';
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
  final Map<String, Map<String, dynamic>> _places = {};
  String _viewEnvironment = 'park';
  bool _hasLoadedPlaces = false;
  Future<void>? _placeLoad;
  Map<String, dynamic>? _unscopedLegacy;
  String? noSideQuestsMessage;
  String get _placeLabel => switch (_viewEnvironment) {
        'park' => 'Park',
        'road' => 'Road',
        'city' => 'City',
        'treadmill' => 'Treadmill',
        'trail' => 'Trail',
        _ => _viewEnvironment,
      };
  String? _boundSession;
  bool _generationUnknown = false;
  bool canRetryQuests = false;
  bool _retryUnsentGeneration = false;
  bool get sideQuestLoadUncertain => _generationUnknown && _daily.isEmpty;
  int? _lastQuestErrorStatus;
  bool isLoadingQuests = false, isStarting = false;
  String? errorMessage;
  final Set<String> _completingIds = {};
  final Map<String, SideQuestRewardReceipt> _confirmedRewards = {};
  List<SideQuestRewardReceipt> rewardsForSession(String session) =>
      List.unmodifiable(
          _confirmedRewards.values.where((r) => r.sessionId == session));
  String? questSessionNotice(String id) {
    final rows = _daily.where((q) => q['instanceId'] == id);
    if (rows.isEmpty || rows.first['done'] == true) return null;
    final bound = rows.first['bound'];
    return bound != null && bound != sessionId
        ? 'ภารกิจนี้ผูกกับการวิ่งรอบก่อน'
        : null;
  }

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

  Map<String, dynamic> _currentPlace() => {
        'environment': _viewEnvironment,
        'quests': _daily.map((q) => Map<String, dynamic>.from(q)).toList(),
        'boundSession': _boundSession,
        'retryable': canRetryQuests,
        'lastQuestErrorStatus': _lastQuestErrorStatus,
        'generationUnknown': _generationUnknown,
        'noQuests': noSideQuestsMessage != null,
        'errorMessage': errorMessage,
      };
  void _rememberPlace() {
    // Home can restore an empty store before any place has been requested.
    // That default view is not a server result and must not suppress its GET.
    if (_hasLoadedPlaces &&
        (_daily.isNotEmpty ||
            _generationUnknown ||
            _boundSession != null ||
            noSideQuestsMessage != null ||
            _lastQuestErrorStatus != null ||
            canRetryQuests)) {
      _places[_viewEnvironment] = _currentPlace();
    }
  }

  Map<String, dynamic> _snapshot() => {
        'version': 2,
        'lastEnvironment': _viewEnvironment,
        'places': _places.map(
            (key, value) => MapEntry(key, Map<String, dynamic>.from(value))),
        if (_unscopedLegacy != null) 'legacyUncertain': _unscopedLegacy,
      };
  void _displayPlace(String env) {
    _viewEnvironment = env;
    final place = _places[env] ?? const <String, dynamic>{};
    _daily = (place['quests'] as List? ?? [])
        .map((q) => Map<String, dynamic>.from(q as Map))
        .toList();
    _boundSession = place['boundSession']?.toString();
    _generationUnknown = place['generationUnknown'] == true;
    _lastQuestErrorStatus = (place['lastQuestErrorStatus'] as num?)?.toInt();
    canRetryQuests = place['retryable'] == true;
    _retryUnsentGeneration = false;
    errorMessage = place['errorMessage']?.toString();
    noSideQuestsMessage =
        place['noQuests'] == true ? 'ขณะนี้ยังไม่มีเควสที่ $_placeLabel' : null;
    _showDaily();
  }

  Future<void> _loadPlaces(String day) async {
    if (_hasLoadedPlaces) return;
    try {
      await (_placeLoad ??= _readPlaces(day));
    } catch (_) {
      if (day == _day) _placeLoad = null;
      rethrow;
    }
  }

  Future<void> _readPlaces(String day) async {
    if (_hasLoadedPlaces) return;
    final cached = owner == null ? null : await store?.load(owner!, day);
    if (!_alive || day != _day) return;
    if (cached?['places'] is Map) {
      for (final entry in (cached!['places'] as Map).entries) {
        _places[entry.key.toString()] =
            Map<String, dynamic>.from(entry.value as Map);
      }
      _unscopedLegacy = cached['legacyUncertain'] is Map
          ? Map<String, dynamic>.from(cached['legacyUncertain'] as Map)
          : null;
    } else if (cached != null) {
      final legacy = Map<String, dynamic>.from(cached);
      final rows = legacy['quests'] as List? ?? [];
      // The legacy release only had Park templates. Preserve successful IDs
      // and completion flags, rather than generating a replacement set.
      final knownEnvironment = legacy['environment']?.toString() ??
          (rows.isNotEmpty ? 'park' : null);
      if (knownEnvironment != null) {
        _places[knownEnvironment] = legacy;
      } else if (legacy['generationUnknown'] == true) {
        _unscopedLegacy = legacy;
      }
    }
    _hasLoadedPlaces = true;
  }

  Future<void> restoreDaily() async {
    if (isLoadingQuests || isStarting || !_alive) return;
    checkDay();
    final day = _day;
    try {
      await _loadPlaces(day);
      if (!_alive || day != _day || isLoadingQuests || isStarting) return;
      _displayPlace(environment ??
          (_places.containsKey('park') ? 'park' : _viewEnvironment));
      notifyListeners();
    } catch (_) {
      if (_alive && day == _day) {
        canRetryQuests = true;
        errorMessage = 'อ่าน Side Quest ที่เก็บไว้ไม่สำเร็จ กรุณาลองใหม่';
        notifyListeners();
      }
    }
  }

  void checkDay() {
    if (_day == _today()) return;
    _day = _today();
    _places.clear();
    _hasLoadedPlaces = false;
    _placeLoad = null;
    _unscopedLegacy = null;
    _daily = [];
    sideQuests = [];
    activeSideQuests = [];
    _boundSession = null;
    _generationUnknown = false;
    canRetryQuests = false;
    _lastQuestErrorStatus = null;
    _retryUnsentGeneration = false;
    noSideQuestsMessage = null;
    errorMessage =
        'วันใหม่แล้ว กรุณาเลือกประเภทการวิ่งเพื่อโหลด Side Quest ของวันนี้';
    notifyListeners();
  }

  Future<void> _persist() {
    _rememberPlace();
    if (owner == null || store == null) return Future.value();
    final day = _day;
    final snapshot = _snapshot();
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
    if (!_alive || isLoadingQuests || isStarting || _completingIds.isNotEmpty) {
      return;
    }
    checkDay();
    _rememberPlace();
    final day = _day;
    environment = env;
    sessionType = mainQuestSessionType;
    isLoadingQuests = true;
    canRetryQuests = false;
    errorMessage = null;
    noSideQuestsMessage = null;
    _displayPlace(env);
    errorMessage = null;
    canRetryQuests = false;
    var cacheLoaded = false;
    var sent = false;
    var received = false;
    notifyListeners();
    try {
      await _loadPlaces(day);
      if (!_alive || day != _day) return;
      cacheLoaded = true;
      _displayPlace(env);
      errorMessage = null;
      final cached = _places[env];
      // Old unattributed failures must not block places whose requests can
      // safely return 404. Park is the only legacy place with created sets.
      if (cached == null && env == 'park' && _unscopedLegacy != null) {
        _generationUnknown = true;
        _lastQuestErrorStatus =
            (_unscopedLegacy!['lastQuestErrorStatus'] as num?)?.toInt();
      }
      if (noSideQuestsMessage != null) return;
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
      if (_daily.isEmpty && _boundSession != null) {
        errorMessage =
            'อ่านชุด Side Quest ของการวิ่งเดิมไม่ได้ · ยังวิ่งอิสระได้';
        return;
      }
      // An old empty placeholder has neither a response nor an outstanding
      // request. Fetch it too; confirmed emptiness/uncertainty returned above.
      if (_daily.isEmpty) {
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
        noSideQuestsMessage =
            _daily.isEmpty ? 'ขณะนี้ยังไม่มีเควสที่ $_placeLabel' : null;
      }
      _showDaily();
      await _persist();
    } catch (e) {
      if (_alive && day == _day) {
        final noTemplates = sent &&
            e is ApiException &&
            e.statusCode == 404 &&
            e.message.startsWith('ไม่พบ side quest สำหรับ $env x ');
        if (noTemplates) {
          _generationUnknown = false;
          _lastQuestErrorStatus = 404;
          _daily = [];
          _boundSession = null;
          canRetryQuests = false;
          noSideQuestsMessage = 'ขณะนี้ยังไม่มีเควสที่ $_placeLabel';
          errorMessage = null;
          _showDaily();
          try {
            await _persist();
          } catch (_) {
            errorMessage =
                'เก็บสถานะ Side Quest ในอุปกรณ์ไม่สำเร็จ กรุณาลองใหม่';
            canRetryQuests = true;
          }
          return;
        }
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
    final completingEnvironment = _viewEnvironment;
    _rememberPlace();
    final completingSnapshot = _snapshot();
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
      final completedQuest =
          completingSet.firstWhere((q) => q['instanceId'] == id);
      completedQuest['done'] = true;
      final coins = result['coinAwarded'];
      if (coins is num && coins.isFinite && coins >= 0) {
        _confirmedRewards[id] = SideQuestRewardReceipt(
            questId: id,
            sessionId: session,
            title: '${completedQuest['title']}',
            coins: coins.toInt());
      }
      onReward?.call();
      if (day != _day) {
        if (store != null && owner != null) {
          final places =
              Map<String, dynamic>.from(completingSnapshot['places'] as Map);
          places[completingEnvironment] = {
            'environment': completingEnvironment,
            'quests': completingSet,
            'boundSession': session,
            'generationUnknown': false
          };
          await store!
              .save(owner!, day, {...completingSnapshot, 'places': places});
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
    _confirmedRewards.clear();
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
