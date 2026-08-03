class SideQuest {
  final String instanceId;
  final String title;
  final String description;
  final int coinReward;
  final String? icon;

  SideQuest({
    required this.instanceId,
    required this.title,
    required this.description,
    required this.coinReward,
    this.icon,
  });

  factory SideQuest.fromJson(Map<String, dynamic> json) => SideQuest(
        instanceId: (json['instanceId'] ?? json['id'] ?? '').toString(),
        title: (json['title'] ?? json['name'] ?? '').toString(),
        description: (json['description'] ?? '').toString(),
        coinReward: (json['coinReward'] ?? json['reward'] ?? 0) as int,
        icon: json['icon']?.toString(),
      );
}

class ActiveSideQuest {
  final String sideQuestId;
  final String title;
  final String description;
  final String? icon;
  final int coinReward;
  bool done;

  ActiveSideQuest({
    required this.sideQuestId,
    required this.title,
    required this.description,
    required this.coinReward,
    this.icon,
    this.done = false,
  });
}
