import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'api_client.dart';
import '../providers/auth_provider.dart';

class OnboardingApi {
  final ApiClient client;
  OnboardingApi(this.client);

  Future<Map<String, dynamic>> status() =>
      client.get('/api/onboarding/status', auth: true);

  Future<Map<String, dynamic>> step1(Map<String, dynamic> body) =>
      client.put('/api/onboarding/step1', body: body, auth: true);

  Future<Map<String, dynamic>> step2(Map<String, dynamic> body) =>
      client.put('/api/onboarding/step2', body: body, auth: true);

  Future<Map<String, dynamic>> step3(Map<String, dynamic> body) =>
      client.put('/api/onboarding/step3', body: body, auth: true);

  Future<Map<String, dynamic>> step4(Map<String, dynamic> body) =>
      client.put('/api/onboarding/step4', body: body, auth: true);
}

final onboardingApiProvider = Provider<OnboardingApi>((ref) {
  return OnboardingApi(ref.read(apiClientProvider));
});