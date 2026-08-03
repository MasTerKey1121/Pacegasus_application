import 'api_client.dart';

class QuestApi {
  final ApiClient client;
  QuestApi(this.client);

  /// API 6.1
  Future<Map<String, dynamic>> getTodaySideQuests({
    required String environment,
    required String trainingType,
  }) =>
      client.get(
        '/api/quests/side?environment=$environment&trainingType=$trainingType',
        auth: true,
      );

  /// API 6.2
  Future<Map<String, dynamic>> startSideQuests({
    required String sessionId,
    required List<String> instanceIds,
  }) =>
    client.post(
      '/api/quests/running-sessions/$sessionId/side-quests',
      body: {'instances': instanceIds.map((id) => {'instanceId': id}).toList()},
      auth: true,
    );

  /// API 6.3
  Future<Map<String, dynamic>> updateSideQuestProgress({
    required String sideQuestId,
    required int progressCount,
    String? photoUrl,
  }) =>
      client.patch(
        '/api/side-quests/$sideQuestId/progress',
        body: {
          'progressCount': progressCount,
          if (photoUrl != null) 'photoUrl': photoUrl,
        },
        auth: true,
      );

  /// API 6.4
  Future<Map<String, dynamic>> finishSideQuest({
    required String sideQuestId,
    String? photoUrl,
    String? note,
  }) =>
      client.patch(
        '/api/side-quests/$sideQuestId/finish',
        body: {
          if (photoUrl != null) 'photoUrl': photoUrl,
          if (note != null) 'note': note,
        },
        auth: true,
      );
}