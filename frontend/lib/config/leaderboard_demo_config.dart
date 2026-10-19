import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Display-only weekly leaderboard examples. No accounts or runs are created.
/// Change these defaults to disable examples or adjust their count/range.
class LeaderboardDemoConfig {
  const LeaderboardDemoConfig({
    this.enabled = true,
    this.count = 50,
    this.minDistanceKm = 0.01,
    this.maxDistanceKm = 2.30,
  })  : assert(count >= 0),
        assert(minDistanceKm > 0),
        assert(maxDistanceKm >= minDistanceKm);

  final bool enabled;
  final int count;
  final double minDistanceKm, maxDistanceKm;
}

final leaderboardDemoConfigProvider =
    Provider((ref) => const LeaderboardDemoConfig());
