/// Rewards confirmed by the existing post-run feedback API.
class RunReward {
  final int coins;
  final int exp;
  const RunReward({required this.coins, required this.exp});

  static RunReward? fromFeedback(Map<String, dynamic> response) {
    final data = response['data'];
    if (data is! Map) return null;
    final total = data['reward'];
    if (total is Map && total['awarded'] == false) {
      return const RunReward(coins: 0, exp: 0);
    }
    if (total is Map &&
        total['awarded'] == true &&
        total['coins'] is num &&
        total['exp'] is num) {
      return RunReward(
          coins: (total['coins'] as num).toInt(),
          exp: (total['exp'] as num).toInt());
    }
    return null;
  }
}
