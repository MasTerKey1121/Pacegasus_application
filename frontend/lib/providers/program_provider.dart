import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/program_api.dart';
import '../services/onboarding_api.dart';
import '../services/api_client.dart';
import '../models/training_models.dart';
import 'auth_provider.dart';

final programApiProvider = Provider<ProgramApi>(
  (ref) => ProgramApi(ref.read(apiClientProvider)),
);

class ProgramNotifier extends ChangeNotifier {
  ProgramNotifier(this._api, this._onboardingApi);

  final ProgramApi _api;
  final OnboardingApi _onboardingApi;
  List<Map<String, dynamic>> quests = const [];
  List<Map<String, dynamic>> templates = const [];
  bool isLoading = false;
  bool isLoadingTemplates = false;
  bool isRegistering = false;
  bool isSavingSchedule = false;
  String? errorMessage;
  String? _onboardingLevel;
  String? selectedTemplateLevel;
  bool _isRegistered = false;
  bool _isScheduleSaved = false;
  DateTime? _programStartDate;
  bool _hasRestored = false;

  /// API 5.1 must only be called after the user explicitly registers a plan.
  bool get isRegistered => _isRegistered;
  bool get isScheduleSaved => _isScheduleSaved;

  /// The day the active program began. Used by the schedule builder to work
  /// out which real calendar week a given "week index" in the UI maps to.
  DateTime? get programStartDate => _programStartDate;

  /// Running experience calculated during onboarding.
  String? get onboardingLevel => _onboardingLevel;

  /// The API 5.0 template that matches the level determined in onboarding.
  Map<String, dynamic>? get registrationTemplate {
    for (final template in templates) {
      if (template['level'] == _onboardingLevel) return template;
    }
    return templates.isEmpty ? null : templates.first;
  }

  void setOnboardingLevel(String level) {
    _onboardingLevel = level;
  }

  void selectTemplate(String level) {
    selectedTemplateLevel = level;
    notifyListeners();
  }

  /// Clears all account-specific state before a different user signs in.
  void reset() {
    quests = const [];
    templates = const [];
    isLoading = false;
    isLoadingTemplates = false;
    isRegistering = false;
    isSavingSchedule = false;
    errorMessage = null;
    _onboardingLevel = null;
    selectedTemplateLevel = null;
    _isRegistered = false;
    _isScheduleSaved = false;
    _programStartDate = null;
    _hasRestored = false;
    notifyListeners();
  }

  /// Restores state that would otherwise be lost when the app is restarted.
  /// An active program is the source of truth for whether registration is done.
  Future<void> restore() async {
    if (_hasRestored || isLoading) return;

    _hasRestored = true;
    isLoading = true;
    errorMessage = null;
    notifyListeners();

    try {
      final response = await _api.getCurrentWeek();
      _setQuests(response);
      _isRegistered = true;
    } on ApiException catch (error) {
      // A 404 means this user has not registered a program yet; it is not an
      // error state for the Home screen.
      if (error.statusCode != 404) errorMessage = error.message;
    } catch (error) {
      errorMessage = error.toString();
    }

    // The level is needed only when a completed-onboarding user registers a
    // program. Fetch it again because the in-memory provider is recreated on
    // every app launch.
    await _restoreOnboardingLevel();
    isLoading = false;
    notifyListeners();
  }

  Future<void> _restoreOnboardingLevel() async {
    try {
      final response = await _onboardingApi.status();
      final data = response['data'] as Map<String, dynamic>? ?? const {};
      final level = data['runningExperienceLevel'] as String?;
      if (level != null && level.isNotEmpty) _onboardingLevel = level;
    } catch (_) {
      // Keep the program state usable if this optional restore request fails.
    }
  }

  /// API 5.0: load data used by the training-registration screen.
  Future<void> loadTemplates() async {
    if (isLoadingTemplates || templates.isNotEmpty) return;

    isLoadingTemplates = true;
    errorMessage = null;
    notifyListeners();
    try {
      final response = await _api.getTemplates();
      final data = response['data'] as List<dynamic>? ?? const [];
      templates = data
          .whereType<Map>()
          .map((template) => Map<String, dynamic>.from(template))
          .toList(growable: false);
    } catch (error) {
      errorMessage = error.toString();
    } finally {
      isLoadingTemplates = false;
      notifyListeners();
    }
  }

  Future<bool> registerPlan({String? level}) async {
    if (level == null &&
        (_onboardingLevel == null || _onboardingLevel!.isEmpty)) {
      await _restoreOnboardingLevel();
    }
    final selectedLevel = level ?? _onboardingLevel;
    if (selectedLevel == null || selectedLevel.isEmpty) {
      errorMessage = 'ไม่พบระดับการวิ่งจาก Onboarding';
      notifyListeners();
      return false;
    }

    isRegistering = true;
    // Keep the registered plan available to the schedule builder immediately
    // after API 5.1 succeeds (and while the app remains open).
    selectedTemplateLevel = selectedLevel;
    errorMessage = null;
    notifyListeners();
    try {
      await _api.start(level: selectedLevel);
      // A training program is available to the UI only after its schedule
      // (API 5.2) has been retrieved successfully.
      final loaded = await loadCurrentWeek();
      isRegistering = false;
      notifyListeners();
      return loaded;
    } catch (error) {
      errorMessage = error.toString();
      isRegistering = false;
      notifyListeners();
      return false;
    }
  }

  Future<bool> cancelCurrentProgram() async {
    if (!_isRegistered || isLoading) return false;

    isLoading = true;
    errorMessage = null;
    notifyListeners();
    try {
      await _api.cancelCurrentProgram();
      quests = const [];
      selectedTemplateLevel = null;
      _isRegistered = false;
      _isScheduleSaved = false;
      _programStartDate = null;
      isLoading = false;
      notifyListeners();
      return true;
    } catch (error) {
      errorMessage = error is ApiException ? error.message : error.toString();
      isLoading = false;
      notifyListeners();
      return false;
    }
  }

  Map<String, dynamic>? get todayQuest {
    final today = DateTime.now();
    final todayKey =
        '${today.year.toString().padLeft(4, '0')}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}';

    for (final quest in quests) {
      final scheduledDate = quest['scheduled_date']?.toString() ?? '';
      if (scheduledDate.startsWith(todayKey)) return quest;
    }
    return null;
  }

  Future<bool> loadCurrentWeek() async {
    isLoading = true;
    errorMessage = null;
    notifyListeners();

    try {
      final response = await _api.getCurrentWeek();
      _setQuests(response);
      _isRegistered = true;
      isLoading = false;
      notifyListeners();
      return true;
    } catch (error) {
      errorMessage = error.toString();
      isLoading = false;
      notifyListeners();
      return false;
    }
  }

  /// Persists one completed week so the user may continue planning later.
  Future<bool> saveManualScheduleWeek({
    required int weekIndex,
    required List<SessionType?> week,
  }) async {
    if (isSavingSchedule) return false;
    if (_programStartDate == null) {
      errorMessage = 'ไม่พบวันเริ่มต้นของแผน กรุณาลองเปิดหน้าตารางใหม่';
      notifyListeners();
      return false;
    }
    isSavingSchedule = true;
    errorMessage = null;
    notifyListeners();
    try {
      final quests = _questsForWeek(weekIndex: weekIndex, week: week);
      if (quests.isEmpty) throw StateError('ไม่พบรายการซ้อมสำหรับบันทึก');
      // The backend inserts this single batch in one transaction. A failed
      // rule check therefore cannot leave a partially saved plan behind.
      await _api.addQuestsBatch(quests);
      _isScheduleSaved = true;
      isSavingSchedule = false;
      notifyListeners();
      return true;
    } catch (error) {
      errorMessage = error.toString();
      isSavingSchedule = false;
      notifyListeners();
      return false;
    }
  }

  Future<bool> replaceManualScheduleWeek({
    required int weekIndex,
    required List<SessionType?> week,
  }) async {
    if (isSavingSchedule) return false;
    if (_programStartDate == null) {
      errorMessage = 'ไม่พบวันเริ่มต้นของแผน กรุณาลองเปิดหน้าตารางใหม่';
      notifyListeners();
      return false;
    }
    final quests = _questsForWeek(weekIndex: weekIndex, week: week);
    if (quests.isEmpty) {
      errorMessage = 'ไม่พบรายการซ้อมสำหรับบันทึก';
      notifyListeners();
      return false;
    }
    isSavingSchedule = true;
    errorMessage = null;
    notifyListeners();
    try {
      final weekStart = _programStartDate!.add(Duration(days: weekIndex * 7));
      await _api.replaceScheduleWeek(
        weekStart: _dateOnly(weekStart),
        quests: quests,
      );
      _isScheduleSaved = true;
      isSavingSchedule = false;
      notifyListeners();
      return true;
    } catch (error) {
      errorMessage = error.toString();
      isSavingSchedule = false;
      notifyListeners();
      return false;
    }
  }

  List<Map<String, String>> _questsForWeek({
    required int weekIndex,
    required List<SessionType?> week,
  }) {
    final quests = <Map<String, String>>[];
    for (var dayIndex = 0; dayIndex < week.length; dayIndex++) {
      final type = week[dayIndex];
      if (type == null ||
          type == SessionType.race ||
          type == SessionType.restForced) {
        continue;
      }
      final date =
          _programStartDate!.add(Duration(days: weekIndex * 7 + dayIndex));
      quests.add({
        'scheduledDate': _dateOnly(date),
        'sessionType': _sessionTypeValue(type),
      });
    }
    return quests;
  }

  /// Fetches every quest already saved between [from] and [to] so the
  /// schedule builder can figure out which weeks it has already saved,
  /// instead of relying on its own in-memory (and easily stale) state.
  Future<List<Map<String, dynamic>>> loadQuestsRange({
    required DateTime from,
    required DateTime to,
  }) async {
    try {
      final response = await _api.getQuestsInRange(
        from: _dateOnly(from),
        to: _dateOnly(to),
      );
      final data = response['data'] as Map<String, dynamic>? ?? const {};
      final rawQuests = data['quests'] as List<dynamic>? ?? const [];
      return rawQuests
          .whereType<Map>()
          .map((quest) => Map<String, dynamic>.from(quest))
          .toList(growable: false);
    } catch (_) {
      return const [];
    }
  }

  void _setQuests(Map<String, dynamic> response) {
    final data = response['data'] as Map<String, dynamic>? ?? const {};
    _isScheduleSaved = data['scheduleSaved'] == true;
    final templateLevel = data['templateLevel']?.toString();
    if (templateLevel != null && templateLevel.isNotEmpty) {
      selectedTemplateLevel = templateLevel;
    }
    final startDate = DateTime.tryParse(data['startDate']?.toString() ?? '');
    if (startDate != null) _programStartDate = startDate;
    final rawQuests = data['quests'] as List<dynamic>? ?? const [];
    quests = rawQuests
        .whereType<Map>()
        .map((quest) => Map<String, dynamic>.from(quest))
        .toList(growable: false);
  }

  String _sessionTypeValue(SessionType type) => switch (type) {
        SessionType.easy => 'easy',
        SessionType.long => 'long_run',
        SessionType.tempo => 'tempo',
        SessionType.vo2max => 'vo2max',
        _ => throw ArgumentError('Unsupported scheduled session: $type'),
      };

  String _dateOnly(DateTime value) =>
      '${value.year.toString().padLeft(4, '0')}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';
}

final programProvider = ChangeNotifierProvider<ProgramNotifier>((ref) {
  final notifier = ProgramNotifier(
    ref.read(programApiProvider),
    ref.read(onboardingApiProvider),
  );

  // Riverpod keeps this provider alive while the app remains open. Reset it
  // when the authenticated user changes, so a new account never inherits the
  // previous account's registered-program state.
  ref.listen<AuthState>(authProvider, (previous, next) {
    final previousUserId = previous?.user?['id'];
    final nextUserId = next.user?['id'];
    if (previousUserId != nextUserId) notifier.reset();
  });

  return notifier;
});
