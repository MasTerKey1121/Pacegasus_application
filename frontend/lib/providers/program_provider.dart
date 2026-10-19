import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/program_api.dart';
import '../services/onboarding_api.dart';
import '../services/api_client.dart';
import '../models/training_models.dart';
import '../models/training_date.dart';
import 'auth_provider.dart';

final programApiProvider = Provider<ProgramApi>(
  (ref) => ProgramApi(ref.read(apiClientProvider)),
);

enum ProgramAccess { checking, unregistered, unscheduled, ready, failed }

class ProgramNotifier extends ChangeNotifier {
  ProgramNotifier(this._api, this._onboardingApi,
      {String? Function()? owner,
      FlutterSecureStorage storage = const FlutterSecureStorage()})
      : _owner = owner,
        _selectionStorage = storage;
  final String? Function()? _owner;
  final FlutterSecureStorage _selectionStorage;
  int? selectedPlanWeeks;
  String? get userProgramId => _userProgramId;
  String? get _selectionKey {
    final owner = _owner?.call();
    return owner == null || _userProgramId == null
        ? null
        : 'program_selection_v1_${owner}_$_userProgramId';
  }

  Future<void> rememberPlanWeeks(int weeks) async {
    selectedPlanWeeks = weeks;
    final key = _selectionKey;
    if (key == null) return;
    await _selectionStorage.write(
        key: key,
        value: jsonEncode({
          'weeks': weeks,
          'startDate': _programStartDate?.toIso8601String(),
          'level': selectedTemplateLevel,
        }));
  }

  Future<void> restorePlanSelection() async {
    final key = _selectionKey;
    final version = _accountVersion;
    if (key == null) return;
    final raw = await _selectionStorage.read(key: key);
    if (version != _accountVersion || key != _selectionKey || raw == null) {
      return;
    }
    final data = jsonDecode(raw) as Map;
    final cachedStart = trainingDate(data['startDate']);
    if (cachedStart != null &&
        _programStartDate != null &&
        cachedStart != _programStartDate) {
      return;
    }
    final weeks = int.tryParse('${data['weeks']}');
    if (weeks != null && weeks >= 1 && weeks <= 520) {
      selectedPlanWeeks ??= weeks;
    }
    _programStartDate ??= cachedStart;
    selectedTemplateLevel ??= data['level']?.toString();
  }

  final ProgramApi _api;
  final OnboardingApi _onboardingApi;
  List<Map<String, dynamic>> quests = const [];
  List<Map<String, dynamic>> templates = const [];
  bool isLoading = false;
  bool isLoadingTemplates = false;
  bool isRegistering = false;
  bool isSavingSchedule = false;
  String? errorMessage;
  String? currentWeekErrorMessage;
  String? _onboardingLevel;
  String? selectedTemplateLevel;
  bool _isRegistered = false;
  bool _isScheduleSaved = false;
  DateTime? _programStartDate;
  bool _hasRestored = false;
  int _accountVersion = 0;
  String? _userProgramId;

  /// API 5.1 must only be called after the user explicitly registers a plan.
  bool get isRegistered => _isRegistered;
  bool get isScheduleSaved => _isScheduleSaved;
  bool _programConfirmed = false;
  bool _cancelling = false;
  int _readVersion = 0;
  Future<bool>? _currentRead;
  ProgramAccess get access {
    if (isLoading || isRegistering || isSavingSchedule || _cancelling) {
      return ProgramAccess.checking;
    }
    if (currentWeekErrorMessage != null) return ProgramAccess.failed;
    if (!_programConfirmed) return ProgramAccess.checking;
    if (!isRegistered) return ProgramAccess.unregistered;
    return isScheduleSaved ? ProgramAccess.ready : ProgramAccess.unscheduled;
  }

  Future<bool> authorizeNewSession() async {
    if (access != ProgramAccess.ready) return false;
    final version = _accountVersion;
    final programId = _userProgramId;
    await loadCurrentWeek();
    return version == _accountVersion &&
        programId == _userProgramId &&
        access == ProgramAccess.ready;
  }

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
    _accountVersion++;
    _readVersion++;
    _currentRead = null;
    _programConfirmed = false;
    _cancelling = false;
    quests = const [];
    templates = const [];
    isLoading = false;
    isLoadingTemplates = false;
    isRegistering = false;
    isSavingSchedule = false;
    errorMessage = null;
    currentWeekErrorMessage = null;
    _onboardingLevel = null;
    selectedTemplateLevel = null;
    _isRegistered = false;
    _isScheduleSaved = false;
    _programStartDate = null;
    selectedPlanWeeks = null;
    _hasRestored = false;
    _userProgramId = null;
    notifyListeners();
  }

  /// Restores state that would otherwise be lost when the app is restarted.
  /// An active program is the source of truth for whether registration is done.
  Future<void> restore({bool force = false}) async {
    if (_hasRestored && !force) return;
    final version = _accountVersion;
    await loadCurrentWeek();
    if (version == _accountVersion) await _restoreOnboardingLevel();
  }

  Future<void> _restoreOnboardingLevel() async {
    final version = _accountVersion;
    try {
      final response = await _onboardingApi.status();
      if (version != _accountVersion) return;
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
    if (isRegistering || isLoading) return false;
    final version = _accountVersion;
    isRegistering = true;
    errorMessage = null;
    notifyListeners();
    try {
      await loadCurrentWeek();
      if (version != _accountVersion) return false;
      if (_isRegistered && currentWeekErrorMessage == null) return true;
      if (currentWeekErrorMessage != null || !_programConfirmed) return false;
      if (level == null &&
          (_onboardingLevel == null || _onboardingLevel!.isEmpty)) {
        await _restoreOnboardingLevel();
      }
      if (version != _accountVersion) return false;
      final selectedLevel = level ?? _onboardingLevel;
      if (selectedLevel == null || selectedLevel.isEmpty) {
        errorMessage = 'ไม่พบระดับการวิ่งจาก Onboarding';
        return false;
      }
      try {
        final response = await _api.start(level: selectedLevel);
        if (version != _accountVersion) return false;
        final data = response['data'] as Map;
        _userProgramId = data['userProgramId']?.toString();
        _programStartDate = trainingDate(data['startDate']);
        selectedTemplateLevel = selectedLevel;
        selectedPlanWeeks = null;
        _isRegistered = true;
        _isScheduleSaved = false;
        await loadCurrentWeek();
        return version == _accountVersion;
      } on ApiException catch (e) {
        if (version != _accountVersion) return false;
        if (e.statusCode == 409 ||
            (e.statusCode == 400 &&
                e.message.contains('คุณมีโปรแกรมที่กำลังดำเนินการอยู่แล้ว'))) {
          await loadCurrentWeek();
          return version == _accountVersion &&
              _isRegistered &&
              currentWeekErrorMessage == null;
        }
        rethrow;
      }
    } catch (e) {
      if (version == _accountVersion) errorMessage = e.toString();
      return false;
    } finally {
      if (version == _accountVersion) {
        isRegistering = false;
        notifyListeners();
      }
    }
  }

  Future<bool> cancelCurrentProgram() async {
    if (!_isRegistered || isLoading) return false;

    _accountVersion++;
    _readVersion++;
    _currentRead = null;
    final version = _accountVersion;
    _cancelling = true;
    isLoading = true;
    errorMessage = null;
    notifyListeners();
    try {
      await _api.cancelCurrentProgram();
      if (version != _accountVersion) return false;
      _programConfirmed = true;
      quests = const [];
      selectedTemplateLevel = null;
      _isRegistered = false;
      _isScheduleSaved = false;
      _userProgramId = null;
      _programStartDate = null;
      currentWeekErrorMessage = null;
      isLoading = false;
      notifyListeners();
      return true;
    } catch (error) {
      if (version != _accountVersion) return false;
      errorMessage = error is ApiException ? error.message : error.toString();
      isLoading = false;
      notifyListeners();
      return false;
    } finally {
      if (version == _accountVersion) {
        _cancelling = false;
        notifyListeners();
      }
    }
  }

  Map<String, dynamic>? get todayQuest {
    final today = trainingToday();
    final todayKey =
        '${today.year.toString().padLeft(4, '0')}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}';

    for (final quest in quests) {
      final scheduledDate = trainingDateKey(quest['scheduled_date']);
      if (scheduledDate == todayKey) return quest;
    }
    return null;
  }

  Future<bool> loadCurrentWeek() {
    if (_cancelling) return Future.value(false);
    if (_currentRead != null) return _currentRead!;
    final future = _loadCurrentWeek();
    _currentRead = future;
    future.whenComplete(() {
      if (identical(_currentRead, future)) _currentRead = null;
    });
    return future;
  }

  Future<bool> _loadCurrentWeek() async {
    _hasRestored = true;
    _readVersion++;
    final readVersion = _readVersion;
    final version = _accountVersion;
    isLoading = true;
    errorMessage = null;
    currentWeekErrorMessage = null;
    notifyListeners();

    var foundProgram = false;
    try {
      final response = await _api.getCurrentWeek();
      if (version != _accountVersion || readVersion != _readVersion) {
        return false;
      }
      foundProgram = true;
      await _setQuests(response, readVersion);
      if (version != _accountVersion || readVersion != _readVersion) {
        return false;
      }
      _isRegistered = true;
      isLoading = false;
      notifyListeners();
      return true;
    } catch (error) {
      if (version != _accountVersion || readVersion != _readVersion) {
        return false;
      }
      if (!foundProgram &&
          error is ApiException &&
          error.statusCode == 404 &&
          (error.message.contains('ไม่พบโปรแกรมที่กำลังดำเนินการอยู่') ||
              error.message.toLowerCase().contains('no active plan') ||
              error.message.toLowerCase().contains('no plan'))) {
        _programConfirmed = true;
        _isRegistered = false;
        _isScheduleSaved = false;
        _programStartDate = null;
        _userProgramId = null;
        selectedPlanWeeks = null;
        quests = [];
        errorMessage = null;
        currentWeekErrorMessage = null;
      } else {
        debugPrint('[ProgramRestore] failed: '
            '${error is FormatException ? error.message : error.runtimeType}'
            '${error is ApiException ? ' (HTTP ${error.statusCode})' : ''}');
        errorMessage = error.toString();
        currentWeekErrorMessage = errorMessage;
      }
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
    final version = _accountVersion;
    final programId = _userProgramId;
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
      if (version != _accountVersion || programId != _userProgramId) {
        return false;
      }
      _isScheduleSaved = true;
      _readVersion++;
      _currentRead = null;
      await loadCurrentWeek();
      if (version != _accountVersion || programId != _userProgramId) {
        return false;
      }
      isSavingSchedule = false;
      notifyListeners();
      return true;
    } catch (error) {
      if (version != _accountVersion) return false;
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
    final version = _accountVersion;
    final programId = _userProgramId;
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
      if (version != _accountVersion || programId != _userProgramId) {
        return false;
      }
      _isScheduleSaved = true;
      _readVersion++;
      _currentRead = null;
      await loadCurrentWeek();
      if (version != _accountVersion || programId != _userProgramId) {
        return false;
      }
      isSavingSchedule = false;
      notifyListeners();
      return true;
    } catch (error) {
      if (version != _accountVersion) return false;
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
    final version = _accountVersion;
    try {
      final response = await _api.getQuestsInRange(
        from: _dateOnly(from),
        to: _dateOnly(to),
      );
      if (version != _accountVersion) throw StateError('บัญชีเปลี่ยนแล้ว');
      final data = response['data'] as Map<String, dynamic>? ?? const {};
      final rawQuests = data['quests'] as List<dynamic>? ?? const [];
      return rawQuests
          .whereType<Map>()
          .map((quest) => Map<String, dynamic>.from(quest))
          .toList(growable: false);
    } catch (_) {
      rethrow;
    }
  }

  Future<void> _setQuests(
      Map<String, dynamic> response, int readVersion) async {
    final version = _accountVersion;
    final data = response['data'] as Map<String, dynamic>? ?? const {};
    final programId = data['userProgramId']?.toString();
    if (programId == null || programId.isEmpty) {
      throw const FormatException('ไม่สามารถยืนยันโปรแกรมปัจจุบันได้');
    }
    if (programId != _userProgramId) {
      _programStartDate = null;
      selectedPlanWeeks = null;
      selectedTemplateLevel = null;
    }
    _userProgramId = programId;
    final templateLevel = data['templateLevel']?.toString();
    if (templateLevel != null && templateLevel.isNotEmpty) {
      selectedTemplateLevel = templateLevel;
    }
    final weekStart = trainingDate(data['weekStart']);
    final weekNumber = int.tryParse('${data['weekNumber']}');
    final startDate = trainingDate(data['startDate']) ??
        (weekStart != null && weekNumber != null && weekNumber >= 1
            ? weekStart.subtract(Duration(days: (weekNumber - 1) * 7))
            : null);
    if (startDate != null) _programStartDate = startDate;
    selectedPlanWeeks ??= int.tryParse('${data['durationWeeks']}');
    // Restore only metadata scoped to this account and this program. It is
    // never used as proof that the server saved a schedule.
    try {
      await restorePlanSelection();
    } catch (_) {
      debugPrint(
          '[ProgramRestore] local selection unavailable; checking server');
    }
    if (version != _accountVersion || readVersion != _readVersion) return;
    final rawQuests = data['quests'] as List<dynamic>? ?? const [];
    quests = rawQuests
        .whereType<Map>()
        .map((quest) => Map<String, dynamic>.from(quest))
        .toList(growable: false);
    _isScheduleSaved = false;
    final explicit = data['scheduleSaved'];
    bool saved;
    if (explicit is bool) {
      saved = explicit;
    } else {
      final start = _programStartDate;
      if (start == null) {
        throw const FormatException('ไม่พบวันเริ่มโปรแกรมสำหรับตรวจตารางซ้อม');
      }
      // Existing quest rows from the authenticated current-program endpoint
      // already prove a schedule exists, even when older responses omit its
      // template metadata. Do not require a template match just to run again.
      if (_containsSavedQuest(quests, start)) {
        saved = true;
      } else {
        var weeks =
            int.tryParse('${data['durationWeeks']}') ?? selectedPlanWeeks;
        if (weeks == null || weeks < 1) {
          if (templates.isEmpty) {
            final response = await _api.getTemplates();
            if (version != _accountVersion || readVersion != _readVersion) {
              return;
            }
            final rows = response['data'];
            if (rows is! List) {
              throw const FormatException('ตรวจช่วงโปรแกรมไม่ได้');
            }
            templates = rows
                .whereType<Map>()
                .map((r) => Map<String, dynamic>.from(r))
                .toList();
          }
          final matches = templates.where((t) =>
              data['programTemplateId'] != null
                  ? t['id'] == data['programTemplateId']
                  : selectedTemplateLevel != null &&
                      t['level'] == selectedTemplateLevel);
          if (matches.isEmpty) {
            // A new week may be empty although an earlier week was saved. Read
            // that program's existing history without guessing its plan level.
            final through = trainingDate(data['weekEnd']) ??
                weekStart?.add(const Duration(days: 6)) ??
                trainingToday();
            saved = await _readSavedSchedule(
                programId,
                start,
                through.isBefore(start) ? start : through,
                version,
                readVersion);
            if (version != _accountVersion || readVersion != _readVersion) {
              return;
            }
            if (!saved) {
              throw const FormatException(
                  'ข้อมูลแผนจากเซิร์ฟเวอร์ยังไม่พอสำหรับตรวจตารางซ้อม กรุณาลองใหม่');
            }
            _isScheduleSaved = true;
            _programConfirmed = true;
            return;
          }
          selectedTemplateLevel = matches.first['level']?.toString();
          weeks = int.tryParse('${matches.first['duration_weeks_max']}');
        }
        if (weeks == null || weeks < 1 || weeks > 520) {
          throw const FormatException('ไม่สามารถยืนยันช่วงโปรแกรมซ้อมได้');
        }
        final end = start.add(Duration(days: weeks * 7 - 1));
        saved = await _readSavedSchedule(
            programId, start, end, version, readVersion);
      }
    }
    if (version != _accountVersion || readVersion != _readVersion) return;
    _isScheduleSaved = saved;
    _programConfirmed = true;
  }

  bool _containsSavedQuest(Iterable<Map> rows, DateTime start,
          [DateTime? end]) =>
      rows.any((q) {
        final date = trainingDate(q['scheduled_date']);
        return date != null &&
            !date.isBefore(start) &&
            (end == null || !date.isAfter(end)) &&
            q['id'] != null &&
            q['session_type'] != null;
      });

  Future<bool> _readSavedSchedule(String programId, DateTime start,
      DateTime end, int version, int readVersion) async {
    final response =
        await _api.getQuestsInRange(from: _dateOnly(start), to: _dateOnly(end));
    if (version != _accountVersion || readVersion != _readVersion) return false;
    final range = response['data'];
    if (range is! Map ||
        range['userProgramId']?.toString() != programId ||
        range['quests'] is! List) {
      throw const FormatException('ไม่สามารถยืนยันตารางของโปรแกรมปัจจุบันได้');
    }
    return _containsSavedQuest(
        (range['quests'] as List).whereType<Map>(), start, end);
  }

  String _sessionTypeValue(SessionType type) => switch (type) {
        SessionType.easy => 'easy',
        SessionType.long => 'long_run',
        SessionType.tempo => 'tempo',
        SessionType.vo2max => 'vo2max',
        _ => throw ArgumentError('Unsupported scheduled session: $type'),
      };

  @override
  void dispose() {
    _accountVersion++;
    super.dispose();
  }

  String _dateOnly(DateTime value) =>
      '${value.year.toString().padLeft(4, '0')}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';
}

final programProvider = ChangeNotifierProvider<ProgramNotifier>((ref) {
  final notifier = ProgramNotifier(
    ref.read(programApiProvider),
    ref.read(onboardingApiProvider),
    owner: () => ref.read(authProvider).user?['id']?.toString(),
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
