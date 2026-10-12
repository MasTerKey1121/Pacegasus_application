import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/auth_provider.dart';
import 'api_client.dart';

final leaderboardApiProvider =
    Provider((ref) => LeaderboardApi(ref.watch(apiClientProvider)));

class RankingEntry {
  final String id, name;
  final String? imageUrl;
  final int? rank;
  final double distance;
  const RankingEntry(
      {required this.id,
      required this.name,
      required this.rank,
      required this.distance,
      this.imageUrl});
  factory RankingEntry.fromJson(Map<String, dynamic> json) => RankingEntry(
      id: json['id'] as String,
      name: json['name'] as String,
      rank: (json['rank'] as num?)?.toInt(),
      distance: (json['distanceKm'] as num).toDouble(),
      imageUrl: json['imageUrl'] as String?);
}

class RankingData {
  final List<RankingEntry> entries;
  final RankingEntry? mine;
  final DateTime startsAt, endsAt;
  const RankingData(
      {required this.entries,
      required this.mine,
      required this.startsAt,
      required this.endsAt});
}

class LeaderboardApi {
  final ApiClient client;
  LeaderboardApi(this.client);
  Future<RankingData> load(String scope) async {
    final response =
        await client.get('/api/leaderboard?scope=$scope', auth: true);
    final data = response['data'] as Map<String, dynamic>;
    return RankingData(
        entries: (data['entries'] as List)
            .map((e) => RankingEntry.fromJson(e as Map<String, dynamic>))
            .toList(),
        mine: data['myEntry'] == null
            ? null
            : RankingEntry.fromJson(data['myEntry'] as Map<String, dynamic>),
        startsAt: DateTime.parse(data['period']['startsAt'] as String),
        endsAt: DateTime.parse(data['period']['endsAt'] as String));
  }
}
