import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/side_quest.dart';
import '../services/quest_api.dart';
import '../services/running_session_api.dart';
import 'auth_provider.dart';

final questApiProvider =
    Provider<QuestApi>((ref) => QuestApi(ref.read(apiClientProvider)));

final runningSessionApiProvider = Provider<RunningSessionApi>(
    (ref) => RunningSessionApi(ref.read(apiClientProvider)));

/// map session_type ของ main quest (easy/tempo/vo2max/long_run)
/// ไปเป็น trainingType ของ side quest (easy/tempo/interval/long_run)
String mapToSideQuestTrainingType(String? sessionType) {
  switch (sessionType) {
    case 'vo2max':
      return 'interval';
    case 'tempo':
      return 'tempo';
    case 'long_run':
      return 'long_run';
    case 'easy':
    default:
      return 'easy';
  }
}

class RunSetupNotifier extends ChangeNotifier {
  RunSetupNotifier(this._questApi, this._sessionApi);

  final QuestApi _questApi;
  final RunningSessionApi _sessionApi;

  String? environment;

  List<SideQuest> sideQuests = [];

  /// เปลี่ยนจากเลือกได้ตัวเดียว -> เลือกได้หลายตัว
  Set<String> selectedInstanceIds = {};

  List<String> sideQuestIds = [];

  /// ภารกิจที่ "เริ่ม" ไปแล้วจริงๆ สำหรับ session นี้ (มี id ใช้ยิง finish ได้)
  /// ใช้โชว์ในหน้าต่างเล็กๆ ของหน้า running session
  List<ActiveSideQuest> activeSideQuests = [];

  final Set<String> _completingIds = {};
  bool isCompletingQuest(String sideQuestId) =>
      _completingIds.contains(sideQuestId);

  bool isLoadingQuests = false;
  bool isStarting = false;
  String? errorMessage;

  String? sessionId;

  Future<void> selectEnvironment({
    required String env,
    required String? mainQuestSessionType,
  }) async {
    environment = env;
    selectedInstanceIds = {};
    sideQuestIds = [];
    isLoadingQuests = true;
    errorMessage = null;
    notifyListeners();

    try {
      final trainingType = mapToSideQuestTrainingType(mainQuestSessionType);

      final response = await _questApi.getTodaySideQuests(
        environment: env,
        trainingType: trainingType,
      );

      final data = response['data'] as Map<String, dynamic>? ?? const {};

      final raw = (data['sideQuests'] ?? data['quests'] ?? []) as List<dynamic>;

      sideQuests = raw
          .whereType<Map>()
          .map((q) => SideQuest.fromJson(Map<String, dynamic>.from(q)))
          .toList(growable: false);

      // User explicitly chooses which optional side quests to start.
      selectedInstanceIds = {};
    } catch (e) {
      errorMessage = e.toString();
      sideQuests = [];
    } finally {
      isLoadingQuests = false;
      notifyListeners();
    }
  }

  Future<bool> startRun({
    required String? mainQuestSessionType,
  }) async {
    if (environment == null) return false;

    isStarting = true;
    errorMessage = null;
    notifyListeners();

    try {
      final res = await _sessionApi.start(
        environment: environment!,
        sessionType: mainQuestSessionType ?? 'easy',
        startLat: 13.7563,
        startLng: 100.5018,
        routePoints: const [
          {
            'lat': 13.7563,
            'lng': 100.5018,
          }
        ],
        // Start side quests through QuestApi below.  Supplying the IDs here
        // would activate them once in the running-session API and then try to
        // activate the same instances again, which makes multiple selections
        // exceed the backend's active-quest limit.
      );

      final data = res['data'] as Map<String, dynamic>? ?? const {};

      sessionId = (data['id'] ?? data['sessionId'])?.toString();

      if (selectedInstanceIds.isNotEmpty && sessionId != null) {
        final res = await _questApi.startSideQuests(
          sessionId: sessionId!,
          instanceIds: selectedInstanceIds.toList(),
        );

        final list = (res['data'] as List).cast<Map<String, dynamic>>();

        sideQuestIds = list.map((e) => e['id'].toString()).toList();

        // จับคู่ id ที่ backend คืนมา กับ title/description ของ quest ที่เลือกไว้
        // (สมมติว่าลำดับที่คืนมาตรงกับลำดับที่ส่งไป — ดูหมายเหตุเรื่อง order ด้านบน)
        final selected = selectedInstanceIds.toList();
        activeSideQuests = List.generate(sideQuestIds.length, (i) {
          final match = i < selected.length
              ? sideQuests.firstWhere(
                  (q) => q.instanceId == selected[i],
                  orElse: () => SideQuest(
                      instanceId: selected[i],
                      title: 'ภารกิจ',
                      description: '',
                      coinReward: 0),
                )
              : null;
          return ActiveSideQuest(
            sideQuestId: sideQuestIds[i],
            title: match?.title ?? 'ภารกิจ',
            description: match?.description ?? '',
            icon: match?.icon,
            coinReward: match?.coinReward ?? 0,
          );
        });
      }

      isStarting = false;
      notifyListeners();

      return sessionId != null;
    } catch (e) {
      errorMessage = e.toString();
      isStarting = false;
      notifyListeners();
      return false;
    }
  }

  /// กดจบภารกิจทีละอันระหว่างวิ่ง (เรียก API 6.4 ทันที)
  Future<void> completeSideQuest(String sideQuestId) async {
    final idx =
        activeSideQuests.indexWhere((q) => q.sideQuestId == sideQuestId);
    if (idx == -1) return;
    final quest = activeSideQuests[idx];
    if (quest.done || _completingIds.contains(sideQuestId)) return;

    _completingIds.add(sideQuestId);
    notifyListeners();
    try {
      await _questApi.finishSideQuest(sideQuestId: sideQuestId);
      quest.done = true;
    } catch (e) {
      errorMessage = e.toString();
    } finally {
      _completingIds.remove(sideQuestId);
      notifyListeners();
    }
  }

  void reset() {
    environment = null;
    sideQuests = [];
    selectedInstanceIds = {};
    sideQuestIds = [];
    activeSideQuests = [];
    _completingIds.clear();
    sessionId = null;
    errorMessage = null;
    notifyListeners();
  }

  void toggleSideQuest(String instanceId) {
    if (selectedInstanceIds.contains(instanceId)) {
      selectedInstanceIds.remove(instanceId);
    } else {
      selectedInstanceIds.add(instanceId);
    }
    notifyListeners();
  }

  void restoreDraft(Map<String, dynamic> draft) {
    environment = draft['environment']?.toString();
    sessionId = draft['sessionId']?.toString();
    final rawQuests = draft['sideQuests'] as List<dynamic>? ?? const [];
    activeSideQuests = rawQuests.whereType<Map>().map((raw) {
      final item = Map<String, dynamic>.from(raw);
      return ActiveSideQuest(
        sideQuestId: item['id']?.toString() ?? '',
        title: item['title']?.toString() ?? 'ภารกิจ',
        description: item['description']?.toString() ?? '',
        icon: item['icon']?.toString(),
        coinReward: (item['coinReward'] as num?)?.toInt() ?? 0,
        done: item['done'] == true,
      );
    }).toList(growable: false);
    sideQuestIds =
        activeSideQuests.map((q) => q.sideQuestId).toList(growable: false);
    notifyListeners();
  }
}

final runSetupProvider = ChangeNotifierProvider<RunSetupNotifier>((ref) {
  final notifier = RunSetupNotifier(
    ref.read(questApiProvider),
    ref.read(runningSessionApiProvider),
  );
  ref.listen<AuthState>(authProvider, (previous, next) {
    if (previous?.user?['id'] != next.user?['id']) notifier.reset();
  });
  return notifier;
});
