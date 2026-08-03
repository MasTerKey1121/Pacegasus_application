import 'api_client.dart';

class RunningSessionApi {
  final ApiClient client;
  RunningSessionApi(this.client);

  /// API 7.1
  Future<Map<String, dynamic>> start({
    required String environment,
    required String sessionType,
    required double startLat,
    required double startLng,
    List<Map<String, double>> routePoints = const [],
    List<String> sideQuestInstanceIds = const [],
  }) =>
      client.post(
        '/api/running-sessions',
        body: {
          'environment': environment,
          'sessionType': sessionType,
          'startLat': startLat,
          'startLng': startLng,
          'routePoints': routePoints,
          'sideQuestInstanceIds': sideQuestInstanceIds,
        },
        auth: true,
      );

  /// API 7.2
  Future<Map<String, dynamic>> getDetail({required String sessionId}) =>
      client.get('/api/running-sessions/$sessionId', auth: true);

  /// API 7.3
  Future<Map<String, dynamic>> complete({
    required String sessionId,
    required double distanceKm,
    required int durationSeconds,
    required double endLat,
    required double endLng,
    List<Map<String, double>> routePoints = const [],
  }) =>
      client.patch(
        '/api/running-sessions/$sessionId/complete',
        body: {
          'distanceKm': distanceKm,
          'durationSeconds': durationSeconds,
          'endLat': endLat,
          'endLng': endLng,
          'routePoints': routePoints,
        },
        auth: true,
      );

  /// API 7.4
  Future<Map<String, dynamic>> abandon({
    required String sessionId,
    required double distanceKm,
    required int durationSeconds,
  }) =>
      client.patch(
        '/api/running-sessions/$sessionId/abandon',
        body: {'distanceKm': distanceKm, 'durationSeconds': durationSeconds},
        auth: true,
      );
}
