// Observational audit probes, excluded from the normal test/ suite.
// Passing here confirms the current defect, not the desired product behavior.
import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pacegasus/providers/auth_provider.dart';
import 'package:pacegasus/providers/onboarding_provider.dart';
import 'package:pacegasus/providers/mission_provider.dart';
import 'package:pacegasus/providers/run_provider.dart';
import 'package:pacegasus/providers/run_setup_provider.dart';
import 'package:pacegasus/services/api_client.dart';
import 'package:pacegasus/services/auth_api.dart';
import 'package:pacegasus/services/quest_api.dart';
import 'package:pacegasus/services/running_session_api.dart';

class OfflineSessions extends RunningSessionApi {
  OfflineSessions() : super(ApiClient(baseUrl: 'http://localhost'));
  @override
  Future<Map<String, dynamic>> complete({required String sessionId,
    required double distanceKm, required int durationSeconds,
    required double endLat, required double endLng,
    List<Map<String, double>> routePoints = const []}) async {
    throw ApiException(0, 'audit simulated offline');
  }
}

class DelayedQuests extends QuestApi {
  DelayedQuests() : super(ApiClient(baseUrl: 'http://localhost'));
  final requests = <String, Completer<Map<String, dynamic>>>{};
  @override
  Future<Map<String, dynamic>> getTodaySideQuests({required String environment,
    required String trainingType}) =>
      (requests[environment] = Completer<Map<String, dynamic>>()).future;
}

class OfflineAuth extends AuthApi {
  OfflineAuth(ApiClient client) : super(client);
  @override
  Future<Map<String, dynamic>> refresh({required String refreshToken}) async =>
      throw ApiException(0, 'audit simulated offline');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('audit: temporary offline refresh deletes the saved login', () async {
    FlutterSecureStorage.setMockInitialValues({'refresh_token': 'valid-session'});
    final client = ApiClient(baseUrl: 'http://localhost');
    final auth = AuthNotifier(OfflineAuth(client), client);
    addTearDown(auth.dispose);
    await auth.init();
    expect(auth.state.status, AuthStatus.unauthenticated);
    expect(await const FlutterSecureStorage().read(key: 'refresh_token'), isNull);
  });

  test('audit: failed completion stops the run and leaves no active retry state', () async {
    final run = RunSessionNotifier(OfflineSessions());
    addTearDown(run.dispose);
    run.start();
    final result = await run.stop(sessionId: 'session', sideQuests: const []);
    expect(result, isNull);
    expect(run.isRunning, isFalse);
    expect(run.isStopping, isFalse);
  });

  test('audit: switching account retains onboarding answers and daily mission status', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final auth = container.read(authProvider.notifier);
    auth.updateUser({'id': 'account-a'});
    final onboarding = container.read(onboardingProvider);
    onboarding.update((data) => data.weightKg = '77');
    final missions = container.read(missionProvider);
    missions.setDone('run', true);
    auth.updateUser({'id': 'account-b'});
    expect(container.read(onboardingProvider).data.weightKg, '77');
    expect(container.read(missionProvider).missions.firstWhere((m) => m.id == 'run').done, isTrue);
  });

  test('audit: older environment request overwrites newer side quests', () async {
    final api = DelayedQuests();
    final setup = RunSetupNotifier(api, OfflineSessions());
    addTearDown(setup.dispose);
    final road = setup.selectEnvironment(env: 'road', mainQuestSessionType: 'easy');
    final park = setup.selectEnvironment(env: 'park', mainQuestSessionType: 'easy');
    Map<String, dynamic> response(String id) => {'data': {'quests': [
      {'instanceId': id, 'title': id, 'description': '', 'coinRewardBase': 5}
    ]}};
    api.requests['park']!.complete(response('park-quest'));
    await park;
    api.requests['road']!.complete(response('road-quest'));
    await road;
    expect(setup.environment, 'park');
    expect(setup.sideQuests.single.instanceId, 'road-quest');
  });
}
