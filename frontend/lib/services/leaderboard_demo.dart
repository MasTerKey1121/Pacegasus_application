import '../config/leaderboard_demo_config.dart';
import 'leaderboard_api.dart';

/// The displayed position is separate from the entry's original server rank.
class LeaderboardDisplayEntry {
  const LeaderboardDisplayEntry(this.entry, this.rank);
  final RankingEntry entry;
  final int? rank;
}

class LeaderboardDisplay {
  const LeaderboardDisplay(this.entries, {required this.hasDemo});
  final List<LeaderboardDisplayEntry> entries;
  final bool hasDemo;
}

// A fixed integer hash, independent of Random's implementation, device, locale,
// login or runtime hashCode. Every intermediate also fits JS's exact integers.
int _hash(String value) {
  var hash = 17;
  for (final code in value.codeUnits) {
    hash = (hash * 31 + code) & 0x7fffffff;
  }
  return hash;
}

List<RankingEntry> generateLeaderboardDemos(
    RankingData data, LeaderboardDemoConfig config) {
  if (!config.enabled ||
      config.count == 0 ||
      data.scope != 'individual' ||
      data.metric != 'weekly_distance' ||
      data.timezone != 'Asia/Bangkok' ||
      data.endsAt.toUtc().difference(data.startsAt.toUtc()) !=
          const Duration(days: 7)) {
    return const [];
  }
  // Use the period returned by the server, never a device-local week or clock.
  final week = '${data.startsAt.toUtc().toIso8601String()}/'
      '${data.endsAt.toUtc().toIso8601String()}';
  final min = (config.minDistanceKm * 100).round();
  final max = (config.maxDistanceKm * 100).round();
  if (min < 1 || max < min) {
    throw ArgumentError('Demo distances must be positive hundredths of a km');
  }
  const names = [
    'Mali',
    'Beam',
    'Mint',
    'Sky',
    'June',
    'Nook',
    'Tan',
    'Ploy',
    'Mook',
    'Jay'
  ];
  const suffixes = [
    'Run',
    'Jog',
    'Go',
    'Pace',
    'Step',
    'Move',
    'Dash',
    'Trail'
  ];
  final reserved = {
    for (final entry in data.entries) entry.id,
    if (data.mine != null) data.mine!.id
  };
  final result = <RankingEntry>[];
  for (var index = 1; result.length < config.count; index++) {
    final id = 'demo_leaderboard_${index.toString().padLeft(4, '0')}';
    if (reserved.contains(id)) continue;
    final name = '${names[_hash('$id/name') % names.length]}'
        '${suffixes[_hash('$id/suffix') % suffixes.length]}'
        '${10 + _hash('$id/number') % 90}';
    final hundredths = min + _hash('$id/$week/distance') % (max - min + 1);
    result.add(RankingEntry(
        id: id,
        name: name,
        rank: null,
        distance: hundredths / 100,
        isDemo: true));
  }
  return List.unmodifiable(result);
}

LeaderboardDisplay buildLeaderboardDisplay(
    RankingData data, LeaderboardDemoConfig config) {
  final demos = generateLeaderboardDemos(data, config);
  if (demos.isEmpty) {
    return LeaderboardDisplay(
        List.unmodifiable([
          for (final entry in data.entries)
            LeaderboardDisplayEntry(entry, entry.rank)
        ]),
        hasDemo: false);
  }
  final combined = [...data.entries, ...demos];
  // Matches the existing SQL: distance DESC, then canonical user ID ASC.
  combined.sort((a, b) {
    final distance = b.distance.compareTo(a.distance);
    return distance != 0 ? distance : a.id.compareTo(b.id);
  });
  final visible = combined.take(50).toList(growable: false);
  return LeaderboardDisplay(
      List.unmodifiable([
        for (var index = 0; index < visible.length; index++)
          LeaderboardDisplayEntry(visible[index], index + 1)
      ]),
      hasDemo: true);
}
