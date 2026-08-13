import 'api_client.dart';

class ProgramApi {
  final ApiClient client;
  ProgramApi(this.client);

  /// API 5.0: retrieve the available training-program templates.
  Future<Map<String, dynamic>> getTemplates() =>
      client.get('/api/programs/templates', auth: true);

  /// API 5.1: create a plan whose daily schedule will be arranged by the user.
  Future<Map<String, dynamic>> start({required String level}) => client.post(
        '/api/programs/start',
        body: {'level': level, 'scheduleMode': 'manual'},
        auth: true,
      );

  /// API 5.2: retrieve all main quests in the active program's current week.
  Future<Map<String, dynamic>> getCurrentWeek() =>
      client.get('/api/programs/current/week', auth: true);

  Future<Map<String, dynamic>> addQuestsBatch(
    List<Map<String, String>> quests,
  ) => client.post(
        '/api/programs/quests/batch',
        body: {'quests': quests},
        auth: true,
      );
}
