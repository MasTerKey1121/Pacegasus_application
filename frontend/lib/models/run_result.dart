/// Snapshot produced right after a run session ends, before the person
/// fills in the post-run feedback (RPE / mood / injury).
class RunResult {
  final double distanceKm;
  final Duration duration;
  final String avgPace; // e.g. "6:30"
  final int calories;
  final List<RunRoutePoint> routePoints;

  int? rpe; // 1-10
  int? stressLevel; // 1-10
  int? moodIndex; // 0-4 (😩🙁🙂😃🤩)
  bool? hasInjury;

  RunResult({
    required this.distanceKm,
    required this.duration,
    required this.avgPace,
    required this.calories,
    this.routePoints = const [],
    this.rpe,
    this.stressLevel,
    this.moodIndex,
    this.hasInjury,
  });
}

class RunRoutePoint {
  final double latitude, longitude;
  const RunRoutePoint(this.latitude, this.longitude);

  static List<RunRoutePoint> parse(Object? value) {
    if (value is! List) return const [];
    final points = <RunRoutePoint>[];
    for (final point in value.whereType<Map>()) {
      final lat = double.tryParse('${point['lat'] ?? point['latitude']}');
      final lng = double.tryParse('${point['lng'] ?? point['longitude']}');
      if (lat != null &&
          lng != null &&
          lat.isFinite &&
          lng.isFinite &&
          lat.abs() <= 90 &&
          lng.abs() <= 180) {
        points.add(RunRoutePoint(lat, lng));
      }
    }
    return List.unmodifiable(points);
  }
}
