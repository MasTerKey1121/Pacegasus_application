import 'api_client.dart';

class ProgramApi {
  final ApiClient client;
  ProgramApi(this.client);

  /// API 5.1: create the user's automatically generated training program.
  Future<Map<String, dynamic>> start({required String level}) => client.post(
        '/api/programs/start',
        body: {'level': level, 'scheduleMode': 'auto'},
        auth: true,
      );

  /// API 5.2: retrieve all main quests in the active program's current week.
  Future<Map<String, dynamic>> getCurrentWeek() =>
      client.get('/api/programs/current/week', auth: true);
}
