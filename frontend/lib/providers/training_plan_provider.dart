import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/training_models.dart';
import 'auth_provider.dart';

class _Boundaries {
  final int base, build, peak, block;
  _Boundaries(this.base, this.build, this.peak, this.block);
}

/// Owns the whole "จัดตารางซ้อม" builder: which plan length is picked,
/// which phase each week falls into, the per-week quota, and the actual
/// day-by-day placement the person has made so far.
class TrainingPlanNotifier extends ChangeNotifier {
  int planWeeks = 10;
  int currentWeek = 0;
  SessionType? selectedType;
  late List<List<SessionType?>> weekSchedules;
  List<int> availablePlanLengths = const [8, 9, 10];
  final Set<int> _savedWeekIndexes = <int>{};
  bool _hasPhases = true;

  TrainingPlanNotifier() {
    rebuildWeeks();
  }

  /// Align the local schedule builder with the duration range of the plan
  /// selected during registration.
  void configurePlanDuration({
    required int minWeeks,
    required int maxWeeks,
    required bool hasPhases,
  }) {
    final options = List<int>.generate(
      maxWeeks - minWeeks + 1,
      (index) => minWeeks + index,
    );
    if (_sameList(availablePlanLengths, options) && _hasPhases == hasPhases) {
      return;
    }
    availablePlanLengths = options;
    _hasPhases = hasPhases;
    planWeeks = options.last;
    rebuildWeeks();
  }

  _Boundaries _computeBoundaries() {
    final block = planWeeks - 2;
    final base = (block / 3).ceil();
    final remaining = block - base;
    final build = (remaining / 2).ceil();
    final peak = remaining - build;
    return _Boundaries(base, build, peak, block);
  }

  PlanPhase getPhase(int weekIndex) {
    final b = _computeBoundaries();
    if (weekIndex < b.base) return PlanPhase.base;
    if (weekIndex < b.base + b.build) return PlanPhase.build;
    if (weekIndex < b.block) return PlanPhase.peak;
    if (weekIndex == b.block) return PlanPhase.taper;
    return PlanPhase.race;
  }

  Map<PlanPhase, int> get phaseStartWeeks {
    final b = _computeBoundaries();
    return {
      PlanPhase.base: 0,
      PlanPhase.build: b.base,
      PlanPhase.peak: b.base + b.build,
      PlanPhase.taper: b.block,
      PlanPhase.race: b.block + 1,
    };
  }

  WeekCaps getCaps(int weekIndex) {
    // The 5K beginner template is a single-phase plan. Its database specs
    // contain Easy Run and Long Run only; never offer VO2Max/Tempo here.
    if (!_hasPhases) return const WeekCaps(easy: 3, long: 1);
    final phase = getPhase(weekIndex);
    if (phase == PlanPhase.race) return const WeekCaps(easy: 4);
    if (phase == PlanPhase.taper) return const WeekCaps(easy: 2, long: 1, tempo: 1);
    final quality = weekIndex % 2 == 0 ? SessionType.vo2max : SessionType.tempo;
    return WeekCaps(
      easy: 2,
      long: 1,
      tempo: quality == SessionType.tempo ? 1 : 0,
      vo2max: quality == SessionType.vo2max ? 1 : 0,
    );
  }

  List<SessionType?> _initWeek(int weekIndex) {
    final arr = List<SessionType?>.filled(7, null);
    if (_hasPhases && getPhase(weekIndex) == PlanPhase.race) {
      arr[5] = SessionType.restForced;
      arr[6] = SessionType.race;
    }
    return arr;
  }

  void rebuildWeeks() {
    weekSchedules = List.generate(planWeeks, (i) => _initWeek(i));
    _savedWeekIndexes.clear();
    currentWeek = 0;
    selectedType = null;
    notifyListeners();
  }

  /// The schedule grid is purely in-memory. Clear it when the signed-in
  /// account changes so a newly-created account can never see the previous
  /// user's unfinished placements.
  void reset() {
    planWeeks = 10;
    availablePlanLengths = const [8, 9, 10];
    _hasPhases = true;
    rebuildWeeks();
  }

  void setPlanWeeks(int w) {
    planWeeks = w;
    rebuildWeeks();
  }

  void goToWeek(int idx) {
    currentWeek = idx.clamp(0, planWeeks - 1);
    selectedType = null;
    notifyListeners();
  }

  void nextWeek() {
    if (currentWeek < planWeeks - 1) {
      currentWeek++;
      selectedType = null;
      notifyListeners();
    }
  }

  void prevWeek() {
    if (currentWeek > 0) {
      currentWeek--;
      selectedType = null;
      notifyListeners();
    }
  }

  void selectType(SessionType type) {
    selectedType = selectedType == type ? null : type;
    notifyListeners();
  }

  List<SessionType?> get currentWeekData => weekSchedules[currentWeek];

  int remainingFor(SessionType type, {int? weekIndex}) {
    final index = weekIndex ?? currentWeek;
    final placed = weekSchedules[index].where((item) => item == type).length;
    return (getCaps(index).capFor(type) - placed).clamp(0, 99);
  }

  /// A hard workout cannot be placed immediately before or after another.
  /// Used by the UI to show unavailable days before the user taps them.
  bool isBlockedForSelectedType(int dayIndex) {
    if (selectedType == null || !hardSessionTypes.contains(selectedType)) {
      return false;
    }
    final week = currentWeekData;
    if (week[dayIndex] != null) return false;
    final previous = dayIndex > 0 ? week[dayIndex - 1] : null;
    final next = dayIndex < week.length - 1 ? week[dayIndex + 1] : null;
    return (previous != null && hardSessionTypes.contains(previous)) ||
        (next != null && hardSessionTypes.contains(next));
  }

  /// Attempts to place the currently-selected chip on [dayIndex], or clears
  /// that day if it's already filled. Returns a human-readable error
  /// message on failure, or null on success (including no-op taps).
  String? handleDayTap(int dayIndex) {
    final w = weekSchedules[currentWeek];
    final val = w[dayIndex];

    if (val == SessionType.race || val == SessionType.restForced) {
      return 'วันนี้ถูกล็อกไว้อัตโนมัติแล้ว';
    }
    if (val != null) {
      w[dayIndex] = null;
      notifyListeners();
      return null;
    }
    if (selectedType == null) return null;

    if (isBlockedForSelectedType(dayIndex)) {
      return 'วันติดกับการซ้อมหนัก ใช้ลง Interval, Tempo หรือ Long Run ไม่ได้';
    }

    final caps = getCaps(currentWeek);
    final cap = caps.capFor(selectedType!);
    final placedCount = w.where((d) => d == selectedType).length;
    if (placedCount >= cap) {
      return 'ลงประเภทนี้ครบจำนวนแล้ว';
    }
    if (hardSessionTypes.contains(selectedType)) {
      final prev = dayIndex > 0 ? w[dayIndex - 1] : null;
      final next = dayIndex < 6 ? w[dayIndex + 1] : null;
      final prevHard = prev != null && hardSessionTypes.contains(prev);
      final nextHard = next != null && hardSessionTypes.contains(next);
      if (prevHard || nextHard) {
        return 'VO2Max, Tempo และ Long Run ห้ามอยู่ติดกัน ต้องพักหรือ Easy คั่นก่อน';
      }
    }
    w[dayIndex] = selectedType;
    // Keep a completed hard-session selection briefly so adjacent days remain
    // visibly locked. It resets when the user selects another workout or
    // changes week.
    if (placedCount + 1 >= cap && !hardSessionTypes.contains(selectedType)) {
      selectedType = null;
    }
    notifyListeners();
    return null;
  }

  bool isWeekComplete(int idx) {
    final caps = getCaps(idx);
    final w = weekSchedules[idx];
    for (final entry in caps.asMap.entries) {
      if (entry.value <= 0) continue;
      final count = w.where((d) => d == entry.key).length;
      if (count != entry.value) return false;
    }
    return true;
  }

  bool isWeekSaved(int weekIndex) => _savedWeekIndexes.contains(weekIndex);

  void markWeekSaved(int weekIndex) {
    _savedWeekIndexes.add(weekIndex);
    notifyListeners();
  }

  /// Rebuilds local placements/saved-week state from what the backend
  /// actually has on record for this program, and resumes at the first week
  /// that isn't fully saved yet. Without this, re-opening the builder (after
  /// leaving the screen, or an app restart) forgets which weeks were already
  /// saved and can reuse the same real-world dates for what the user thinks
  /// is a new week — which the backend then correctly rejects as exceeding
  /// that week's cap.
  void syncFromServer({
    required DateTime startDate,
    required List<Map<String, dynamic>> quests,
  }) {
    final start = DateTime(startDate.year, startDate.month, startDate.day);
    for (final quest in quests) {
      final date = DateTime.tryParse(quest['scheduled_date']?.toString() ?? '');
      final type = _sessionTypeFromApiValue(quest['session_type']?.toString());
      if (date == null || type == null) continue;

      final offsetDays = DateTime(date.year, date.month, date.day).difference(start).inDays;
      if (offsetDays < 0) continue;
      final weekIndex = offsetDays ~/ 7;
      final dayIndex = offsetDays % 7;
      if (weekIndex >= weekSchedules.length) continue;

      weekSchedules[weekIndex][dayIndex] = type;
      _savedWeekIndexes.add(weekIndex);
    }

    var resumeWeek = 0;
    while (resumeWeek < planWeeks - 1 && _savedWeekIndexes.contains(resumeWeek)) {
      resumeWeek++;
    }
    currentWeek = resumeWeek;
    selectedType = null;
    notifyListeners();
  }

  SessionType? _sessionTypeFromApiValue(String? value) => switch (value) {
        'easy' => SessionType.easy,
        'long_run' => SessionType.long,
        'tempo' => SessionType.tempo,
        'vo2max' => SessionType.vo2max,
        _ => null,
      };

  int get overallDoneCount =>
      List.generate(planWeeks, (i) => i).where((i) => isWeekComplete(i)).length;

  bool get allWeeksComplete => overallDoneCount == planWeeks;

  bool _sameList(List<int> first, List<int> second) {
    if (first.length != second.length) return false;
    for (var index = 0; index < first.length; index++) {
      if (first[index] != second[index]) return false;
    }
    return true;
  }
}

final trainingPlanProvider = ChangeNotifierProvider<TrainingPlanNotifier>((ref) {
  final notifier = TrainingPlanNotifier();
  ref.listen<AuthState>(authProvider, (previous, next) {
    if (previous?.user?['id'] != next.user?['id']) notifier.reset();
  });
  return notifier;
});
