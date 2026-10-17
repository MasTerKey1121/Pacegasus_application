import 'dart:async';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pacegasus/providers/run_setup_provider.dart';
import 'package:pacegasus/services/daily_side_quest_store.dart';
import 'package:pacegasus/services/quest_api.dart';
import 'package:pacegasus/services/running_session_api.dart';
import 'run_quest_regression_test.dart' show ContractClient, day;

// The contract allows separate inventories per environment. Unlike the
// current production inventory, this fixture provides both Park and City.
class EnvironmentClient extends ContractClient {
  @override
  Future<Map<String, dynamic>> get(String path, {bool auth = false}) async {
    final result = await super.get(path, auth: auth);
    if (path.startsWith('/api/quests/side?')) {
      final env = Uri.parse(path).queryParameters['environment'];
      final data = result['data'] as Map;
      data['environment'] = env;
      for (final row in data['quests'] as List) {
        row['instanceId'] = '$env-${row['instanceId']}';
      }
    }
    return result;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  test(
      'one of three completes only that user/day/place and survives restart; new Thai day resets choices',
      () async {
    final client = EnvironmentClient();
    final originalProgress = Map<String, dynamic>.from(client.progress);
    var today = day;
    RunSetupNotifier create({String owner = 'a'}) =>
        RunSetupNotifier(QuestApi(client), RunningSessionApi(client),
            owner: owner, store: const DailySideQuestStore(), day: () => today);
    final state = create();
    await state.restoreDaily();
    await state.selectEnvironment(env: 'park', mainQuestSessionType: 'easy');
    expect(state.visibleSideQuests.length, 3);
    await state.startRun(mainQuestSessionType: 'easy');
    await state.completeSideQuest('park-i2');
    expect(state.dailyComplete, true);
    expect(state.visibleSideQuests.map((q) => q.instanceId), ['park-i2']);
    expect(state.isDone('park-i1'), false); // No fake server completion.
    expect(state.selectedInstanceIds, isEmpty);
    await state.completeSideQuest('park-i1');
    expect(client.sidePatches, 1);
    client.rows.last['status'] = 'completed';
    state.dispose();

    final restored = create();
    await restored.restoreDaily();
    expect(restored.dailyComplete, true);
    expect(restored.visibleSideQuests.single.instanceId, 'park-i2');
    expect(restored.rewardsForSession('run1'), isEmpty);
    await restored.selectEnvironment(env: 'city', mainQuestSessionType: 'easy');
    expect(restored.dailyComplete, false);
    expect(restored.visibleSideQuests.length, 3);
    await restored.startRun(mainQuestSessionType: 'easy');
    await restored.completeSideQuest('city-i3');
    expect(restored.dailyComplete, true);
    expect(restored.visibleSideQuests.single.instanceId, 'city-i3');
    await restored.selectEnvironment(
        env: 'park', mainQuestSessionType: 'tempo');
    expect(restored.visibleSideQuests.single.instanceId, 'park-i2');
    expect(client.generated, 2);
    expect(client.sidePatches, 2);

    final other = create(owner: 'b');
    await other.restoreDaily();
    expect(other.dailyComplete, false);
    expect(other.visibleSideQuests, isEmpty);
    other.dispose();
    today = '2026-10-18';
    restored.checkDay();
    expect(restored.dailyComplete, false);
    expect(restored.visibleSideQuests, isEmpty);
    await restored.selectEnvironment(env: 'park', mainQuestSessionType: 'easy');
    expect(restored.visibleSideQuests.length, 3);
    expect(restored.dailyComplete, false);
    expect(client.generated, 3);
    expect(client.progress, originalProgress);
    restored.dispose();
  });

  test(
      'different choice buttons cannot finish in parallel; failure leaves the daily group open',
      () async {
    final client = EnvironmentClient();
    final state = RunSetupNotifier(QuestApi(client), RunningSessionApi(client));
    await state.selectEnvironment(env: 'park', mainQuestSessionType: 'easy');
    await state.startRun(mainQuestSessionType: 'easy');
    client.failSide = true;
    await state.completeSideQuest('park-i1');
    expect(state.dailyComplete, false);
    expect(state.visibleSideQuests.length, 3);
    client.failSide = false;
    client.pendingSide = Completer<Map<String, dynamic>>();
    final finishing = state.completeSideQuest('park-i2');
    await Future<void>.delayed(Duration.zero);
    await state.completeSideQuest('park-i3');
    expect(client.sidePatches, 2); // One failure and one in-flight request.
    client.pendingSide!.complete(client.sideResult('park-i2'));
    await finishing;
    expect(state.dailyComplete, true);
    await state.completeSideQuest('park-i3');
    expect(client.sidePatches, 2);
    expect(state.visibleSideQuests.single.instanceId, 'park-i2');
    state.dispose();
  });
}
