import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/side_quest.dart';
import '../services/quest_api.dart';
import '../services/running_session_api.dart';
import 'auth_provider.dart';
import 'program_provider.dart';

final questApiProvider = Provider<QuestApi>((ref) => QuestApi(ref.read(apiClientProvider)));
final runningSessionApiProvider =
    Provider<RunningSessionApi>((ref) => RunningSessionApi(ref.read(apiClientProvider)));

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
  String? selectedInstanceId;
  bool isLoadingQuests = false;
  bool isStarting = false;
  String? errorMessage;

  String? sessionId;

  Future<void> selectEnvironment(String env, {required String? mainQuestSessionType}) async {
    environment = env;
    selectedInstanceId = null;
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
    } catch (e) {
      errorMessage = e.toString();
      sideQuests = [];
    } finally {
      isLoadingQuests = false;
      notifyListeners();
    }
  }

  void selectSideQuest(String instanceId) {
    selectedInstanceId = selectedInstanceId == instanceId ? null : instanceId;
    notifyListeners();
  }

  /// เรียก 7.1 (สร้าง session) แล้ว 6.2 (เริ่ม side quest ที่เลือก)
  /// คืน true ถ้าสำเร็จ
  Future<bool> startRun({required String? mainQuestSessionType}) async {
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
          {'lat': 13.7563, 'lng': 100.5018},
        ],
        sideQuestInstanceIds: selectedInstanceId != null ? [selectedInstanceId!] : const [],
      );
      final data = res['data'] as Map<String, dynamic>? ?? const {};
      sessionId = (data['id'] ?? data['sessionId'])?.toString();

      if (selectedInstanceId != null && sessionId != null) {
        await _questApi.startSideQuest(
          sessionId: sessionId!,
          instanceId: selectedInstanceId!,
        );
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

  void reset() {
    environment = null;
    sideQuests = [];
    selectedInstanceId = null;
    sessionId = null;
    errorMessage = null;
  }
}

final runSetupProvider = ChangeNotifierProvider<RunSetupNotifier>(
  (ref) => RunSetupNotifier(ref.read(questApiProvider), ref.read(runningSessionApiProvider)),
);