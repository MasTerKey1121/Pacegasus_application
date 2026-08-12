import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/program_api.dart';
import '../services/onboarding_api.dart';
import '../services/api_client.dart';
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
  String? errorMessage;
  String? _onboardingLevel;
  String? selectedTemplateLevel;
  bool _isRegistered = false;
  bool _hasRestored = false;

  /// API 5.1 must only be called after the user explicitly registers a plan.
  bool get isRegistered => _isRegistered;

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
    errorMessage = null;
    _onboardingLevel = null;
    selectedTemplateLevel = null;
    _isRegistered = false;
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
    if (level == null && (_onboardingLevel == null || _onboardingLevel!.isEmpty)) {
      await _restoreOnboardingLevel();
    }
    final selectedLevel = level ?? _onboardingLevel;
    if (selectedLevel == null || selectedLevel.isEmpty) {
      errorMessage = 'ไม่พบระดับการวิ่งจาก Onboarding';
      notifyListeners();
      return false;
    }

    isRegistering = true;
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

  void _setQuests(Map<String, dynamic> response) {
    final data = response['data'] as Map<String, dynamic>? ?? const {};
    final rawQuests = data['quests'] as List<dynamic>? ?? const [];
    quests = rawQuests
        .whereType<Map>()
        .map((quest) => Map<String, dynamic>.from(quest))
        .toList(growable: false);
  }
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
