import 'api_client.dart';

/// API for the post-run feedback recorded on the run summary screen.
class RpeApi {
  final ApiClient client;

  RpeApi(this.client);

  Future<Map<String, dynamic>> logRunFeedback({
    required String runningSessionId,
    required int durationMinutes,
    required int rpeScore,
    required int stressLevel,
    required String mood,
    required bool hasPain,
  }) =>
      client.post(
        '/api/rpe',
        body: {
          'runningSessionId': runningSessionId,
          'durationMinutes': durationMinutes,
          'rpeScore': rpeScore,
          'stressLevel': stressLevel,
          'mood': mood,
          'hasPain': hasPain,
          'painNote': null,
        },
        auth: true,
      );
}
