import 'api_client.dart';

class WellnessApi {
  final ApiClient client;
  WellnessApi(this.client);

  Future<Map<String, dynamic>> getToday() =>
      client.get('/api/wellness-checkin/today', auth: true);

  Future<Map<String, dynamic>> create(Map<String, dynamic> body) =>
      client.post('/api/wellness-checkin', body: body, auth: true);

  Future<Map<String, dynamic>> update(Map<String, dynamic> body) =>
      client.put('/api/wellness-checkin', body: body, auth: true);
}