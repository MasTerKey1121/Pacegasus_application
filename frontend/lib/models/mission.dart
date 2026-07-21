class Mission {
  final String id;
  final String icon;
  final String title;
  final String subtitle;
  final int coinReward;
  bool done;

  Mission({
    required this.id,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.coinReward,
    this.done = false,
  });
}
