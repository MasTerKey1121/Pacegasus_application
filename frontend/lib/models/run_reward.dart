/// Rewards confirmed by the existing post-run feedback API.
class RunReward {
  final int coins;
  final int exp;
  const RunReward({required this.coins, required this.exp});

  static RunReward? fromFeedback(Map<String, dynamic> response) {
    final data = response['data'];
    if (data is! Map) return null;
    final reward = data['reward'];
    if (reward is! Map) return null;
    if (reward['awarded'] == false) {
      return const RunReward(coins: 0, exp: 0);
    }
    if (reward['awarded'] == true &&
        reward['coins'] is num &&
        reward['exp'] is num) {
      return RunReward(
          coins: (reward['coins'] as num).toInt(),
          exp: (reward['exp'] as num).toInt());
    }
    return null;
  }
}
