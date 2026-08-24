/// Snapshot produced right after a run session ends, before the person
/// fills in the post-run feedback (RPE / mood / injury).
class RunResult {
  final double distanceKm;
  final Duration duration;
  final String avgPace; // e.g. "6:30"
  final int calories;

  int? rpe; // 1-10
  int? stressLevel; // 1-10
  int? moodIndex; // 0-4 (😩🙁🙂😃🤩)
  bool? hasInjury;

  RunResult({
    required this.distanceKm,
    required this.duration,
    required this.avgPace,
    required this.calories,
    this.rpe,
    this.stressLevel,
    this.moodIndex,
    this.hasInjury,
  });
}
