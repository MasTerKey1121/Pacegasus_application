import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:pacegasus/providers/run_provider.dart';
import 'package:pacegasus/providers/run_setup_provider.dart';
import 'package:pacegasus/services/api_client.dart';
import 'package:pacegasus/services/quest_api.dart';
import 'package:pacegasus/services/running_session_api.dart';

class TestQuests extends QuestApi {
  TestQuests() : super(ApiClient(baseUrl: 'http://localhost'));
  List<String> started = [];
  final List<String> finished = [];
  Completer<Map<String, dynamic>>? pending;

  @override
  Future<Map<String, dynamic>> getTodaySideQuests({
    required String environment,
    required String trainingType,
  }) async =>
      pending != null
          ? await pending!.future
          : {
              'data': {
                'quests': List.generate(
                    3,
                    (i) => {
                          'instanceId': '${i + 1}',
                          'title': 'Quest ${i + 1}',
                          'description': 'Optional task',
                          'coinRewardBase': (i + 1) * 10,
                        }),
              },
            };

  @override
  Future<Map<String, dynamic>> startSideQuests({
    required String sessionId,
    required List<String> instanceIds,
  }) async {
    started = instanceIds;
    // Responses may return the same instances in a different order.
    return {
      'data': instanceIds.reversed.map((id) => {'id': id}).toList()
    };
  }

  @override
  Future<Map<String, dynamic>> finishSideQuest({
    required String sideQuestId,
    String? photoUrl,
    String? note,
  }) async {
    finished.add(sideQuestId);
    return {
      'data': {'id': sideQuestId, 'status': 'completed'}
    };
  }
}

class TestSessions extends RunningSessionApi {
  TestSessions() : super(ApiClient(baseUrl: 'http://localhost'));
  int starts = 0;
  int completions = 0;

  @override
  Future<Map<String, dynamic>> start({
    required String environment,
    required String sessionType,
    required double startLat,
    required double startLng,
    List<Map<String, double>> routePoints = const [],
    List<String> sideQuestInstanceIds = const [],
  }) async {
    starts++;
    expect(sideQuestInstanceIds, isEmpty);
    return {
      'data': {'id': 'run-1'}
    };
  }

  @override
  Future<Map<String, dynamic>> complete({
    required String sessionId,
    required double distanceKm,
    required int durationSeconds,
    required double endLat,
    required double endLng,
    List<Map<String, double>> routePoints = const [],
  }) async {
    completions++;
    return {
      'data': {'id': sessionId}
    };
  }
}

void main() {
  test(
      'all quests are available; only an explicitly completed quest earns reward',
      () async {
    final quests = TestQuests();
    final sessions = TestSessions();
    final setup = RunSetupNotifier(quests, sessions);
    final run = RunSessionNotifier(sessions);
    addTearDown(setup.dispose);
    addTearDown(run.dispose);

    await setup.selectEnvironment(env: 'park', mainQuestSessionType: 'easy');
    expect(await setup.startRun(mainQuestSessionType: 'easy'), isTrue);
    expect(quests.started, ['1', '2', '3']);
    expect(setup.activeSideQuests.map((q) => q.title),
        ['Quest 3', 'Quest 2', 'Quest 1']);
    expect(setup.activeSideQuests.map((q) => q.coinReward), [30, 20, 10]);

    await setup.completeSideQuest('2');
    await setup.completeSideQuest('2');
    expect(quests.finished, ['2']);
    run.elapsedSeconds = 600;
    run.setDistance(1);
    expect(
        await run.stop(
            sessionId: setup.sessionId!, sideQuests: setup.activeSideQuests),
        isNotNull);
    expect(sessions.completions, 1);
    expect(quests.finished, ['2']);
    expect(
        setup.activeSideQuests.where((q) => q.done).map((q) => q.sideQuestId),
        ['2']);
  });

  test('cannot start while today quests are loading', () async {
    final quests = TestQuests()..pending = Completer<Map<String, dynamic>>();
    final sessions = TestSessions();
    final setup = RunSetupNotifier(quests, sessions);
    addTearDown(setup.dispose);
    final loading =
        setup.selectEnvironment(env: 'park', mainQuestSessionType: 'easy');
    expect(await setup.startRun(mainQuestSessionType: 'easy'), isFalse);
    expect(sessions.starts, 0);
    quests.pending!.complete({
      'data': {'quests': []}
    });
    await loading;
    expect(await setup.startRun(mainQuestSessionType: 'easy'), isTrue);
    expect(setup.activeSideQuests, isEmpty);
  });
}
