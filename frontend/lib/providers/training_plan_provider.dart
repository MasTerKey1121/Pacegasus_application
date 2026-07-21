import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/training_models.dart';

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

  TrainingPlanNotifier() {
    rebuildWeeks();
  }

  static const availablePlanLengths = [8, 9, 10];

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
    if (getPhase(weekIndex) == PlanPhase.race) {
      arr[5] = SessionType.restForced;
      arr[6] = SessionType.race;
    }
    return arr;
  }

  void rebuildWeeks() {
    weekSchedules = List.generate(planWeeks, (i) => _initWeek(i));
    currentWeek = 0;
    selectedType = null;
    notifyListeners();
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
    if (placedCount + 1 >= cap) selectedType = null;
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

  int get overallDoneCount =>
      List.generate(planWeeks, (i) => i).where((i) => isWeekComplete(i)).length;

  bool get allWeeksComplete => overallDoneCount == planWeeks;
}

final trainingPlanProvider = ChangeNotifierProvider<TrainingPlanNotifier>((ref) => TrainingPlanNotifier());
