import 'dart:async';
import 'package:flutter/widgets.dart';
import 'package:pacegasus/providers/training_day_provider.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pacegasus/providers/auth_provider.dart';
import 'package:pacegasus/providers/progress_provider.dart';
import 'package:pacegasus/providers/daily_quest_provider.dart';
import 'package:pacegasus/providers/run_provider.dart';
import 'package:pacegasus/providers/run_setup_provider.dart';
import 'package:pacegasus/services/api_client.dart';
import 'package:pacegasus/services/auth_api.dart';
import 'package:pacegasus/services/program_api.dart';
import 'package:pacegasus/services/quest_api.dart';
import 'package:pacegasus/services/running_session_api.dart';
import 'package:pacegasus/services/run_draft_store.dart';
import 'package:pacegasus/services/daily_side_quest_store.dart';
import 'package:pacegasus/models/training_date.dart';

const day = '2026-10-17';
Map<String, dynamic> runRow(String id, double km,
        {String environment = 'park',
        String status = 'completed',
        String ended = '2026-10-17T10:00:00Z',
        int seconds = 600}) =>
    {
      'id': id,
      'user_id': 'a',
      'environment': environment,
      'session_type': 'easy',
      'status': status,
      'started_at': '2026-10-17T09:00:00Z',
      'ended_at': ended,
      'distance_km': km.toStringAsFixed(3),
      'duration_seconds': seconds,
      'route_points': [],
    };
Map<String, dynamic> questRow({String unit = 'km', num target = 3}) => {
      'id': 'q',
      'scheduled_date': day,
      'session_type': 'easy',
      'unit': unit,
      'planned_value': '$target',
      'status': 'pending',
      'running_session_id': null,
    };

/// Responses mirror the inspected controllers/services (snake_case session
/// rows, data.sessions history, camelCase progress/side-quest instances).
class ContractClient extends ApiClient {
  ContractClient() : super(baseUrl: 'http://localhost');
  String owner = 'a';
  Map<String, dynamic> quest = questRow();
  List<Map<String, dynamic>> rows = [];
  Map<String, dynamic> progress = {
    'coinBalance': 87,
    'level': 5,
    'exp': 30,
    'expToNext': 240
  };
  Map<String, dynamic>? detailOverride;
  Completer<Map<String, dynamic>>? pendingProgress,
      pendingComplete,
      pendingSide;
  bool offline = false,
      failQuest = false,
      lostQuest = false,
      failRun = false,
      lostRun = false,
      failSide = false;
  int runPatches = 0,
      questPatches = 0,
      sidePatches = 0,
      generated = 0,
      starts = 0,
      activations = 0;
  final calls = <String>[];
  @override
  Future<Map<String, dynamic>> get(String path, {bool auth = false}) async {
    expect(auth, true);
    calls.add('GET $path');
    if (offline) throw ApiException(0, 'offline');
    if (path == '/api/users/me/progress') {
      if (pendingProgress != null) return pendingProgress!.future;
      return {'success': true, 'data': Map<String, dynamic>.from(progress)};
    }
    if (path == '/api/programs/current/week' ||
        path.startsWith('/api/programs/quests?')) {
      return {
        'success': true,
        'data': {
          'quests': [Map<String, dynamic>.from(quest)]
        }
      };
    }
    if (path == '/api/running-sessions/history?sortBy=date&order=desc') {
      return {
        'success': true,
        'data': {
          'sortBy': 'date',
          'order': 'desc',
          'sessions': rows.where((r) => r['status'] == 'completed').map((r) {
            final history = Map<String, dynamic>.from(r)
              ..remove('user_id')
              ..remove('route_points');
            history['session_date'] = r['ended_at'];
            history.putIfAbsent('rpe_logs', () => []);
            return history;
          }).toList()
        }
      };
    }
    if (path.startsWith('/api/running-sessions/')) {
      final id = path.split('/').last;
      return {
        'success': true,
        'data': detailOverride ?? rows.firstWhere((r) => r['id'] == id)
      };
    }
    if (path.startsWith('/api/quests/side?')) {
      generated++;
      return {
        'success': true,
        'data': {
          'environment': 'park',
          'trainingType': 'easy',
          'plannedDistanceKm': 3,
          'quests': [
            for (var i = 1; i <= 3; i++)
              {
                'instanceId': 'i$i',
                'title': 'Quest $i',
                'description': 'Task',
                'targetCount': 1,
                'foundCount': 0,
                'status': 'in_progress',
                'coinRewardBase': 10
              },
          ]
        }
      };
    }
    throw StateError('Unexpected GET $path');
  }

  @override
  Future<Map<String, dynamic>> post(String path,
      {Map<String, dynamic>? body, bool auth = false}) async {
    expect(auth, true);
    if (path == '/api/running-sessions') {
      starts++;
      final row = runRow('run$starts', 0, status: 'in_progress')
        ..['user_id'] = owner;
      rows.add(row);
      return {'success': true, 'data': row};
    }
    if (path.endsWith('/side-quests')) {
      activations++;
      return {
        'success': true,
        'data': [
          for (final item in body!['instances'] as List)
            {
              'id': item['instanceId'],
              'userId': owner,
              'runningSessionId': path.split('/')[4],
              'sideQuestTemplateId': 'template-${item['instanceId']}',
              'status': 'in_progress',
              'coinAwarded': 0
            }
        ]
      };
    }
    throw StateError('Unexpected POST $path');
  }

  @override
  Future<Map<String, dynamic>> patch(String path,
      {Map<String, dynamic>? body, bool auth = false}) async {
    expect(auth, true);
    calls.add('PATCH $path');
    if (path == '/api/programs/quests/q/complete') {
      questPatches++;
      if (failQuest) throw ApiException(503, 'try later');
      quest['status'] = 'completed';
      if (lostQuest) throw ApiException(0, 'response lost');
      return {
        'success': true,
        'data': {
          'quest': Map<String, dynamic>.from(quest),
          'reward': {
            'awarded': true,
            'coins': 8,
            'exp': 20,
            'progress': progress
          }
        }
      };
    }
    if (path.startsWith('/api/running-sessions/')) {
      runPatches++;
      if (pendingComplete != null) return pendingComplete!.future;
      if (failRun) throw ApiException(503, 'try later');
      final id = path.split('/')[3];
      final row = rows.firstWhere((r) => r['id'] == id);
      row.addAll({
        'status': 'completed',
        'distance_km': body!['distanceKm'],
        'duration_seconds': body['durationSeconds'],
        'route_points': body['routePoints']
      });
      if (lostRun) throw ApiException(0, 'response lost');
      return {'success': true, 'data': Map<String, dynamic>.from(row)};
    }
    if (path.startsWith('/api/side-quests/')) {
      sidePatches++;
      if (pendingSide != null) return pendingSide!.future;
      if (failSide) throw ApiException(503, 'try later');
      return sideResult(path.split('/')[3]);
    }
    throw StateError('Unexpected PATCH $path');
  }

  Map<String, dynamic> sideResult(String id) => {
        'success': true,
        'data': {
          'id': id,
          'userId': owner,
          'runningSessionId': 'run$starts',
          'status': 'completed',
          'coinAwarded': 10,
          'targetCount': 1,
          'foundCount': 1,
          'sideQuestTemplateId': 'template-$id'
        }
      };
}

class TestAuth extends AuthNotifier {
  TestAuth(ApiClient client) : super(AuthApi(client), client);
  void signIn(String id) =>
      state = AuthState(status: AuthStatus.authenticated, user: {'id': id});
  void signOut() => state = const AuthState(status: AuthStatus.unauthenticated);
}

class DelayedStorage extends FlutterSecureStorage {
  final gate = Completer<void>();
  String? value;
  @override
  Future<void> write(
      {required String key,
      required String? value,
      dynamic iOptions,
      dynamic aOptions,
      dynamic lOptions,
      dynamic webOptions,
      dynamic mOptions,
      dynamic wOptions}) async {
    await gate.future;
    this.value = value;
  }

  @override
  Future<String?> read(
          {required String key,
          dynamic iOptions,
          dynamic aOptions,
          dynamic lOptions,
          dynamic webOptions,
          dynamic mOptions,
          dynamic wOptions}) async =>
      value;
  @override
  Future<void> delete(
      {required String key,
      dynamic iOptions,
      dynamic aOptions,
      dynamic lOptions,
      dynamic webOptions,
      dynamic mOptions,
      dynamic wOptions}) async {
    value = null;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));
  test(
      'timer write in flight drains before clear; later ticks cannot resurrect draft',
      () async {
    final storage = DelayedStorage();
    final store = RunDraftStore(storage: storage);
    final writing = store.save({'ownerUserId': 'a', 'sessionId': 's'});
    final drain = store.seal('a', 's');
    final clear = store.clear(userId: 'a');
    await store.save({'ownerUserId': 'a', 'sessionId': 's'});
    storage.gate.complete();
    await Future.wait([writing, drain, clear]);
    expect(await store.loadForUser('a'), isNull);
  });
  for (final status in ['completed', 'abandoned']) {
    test('restart and same-account login never resume $status session',
        () async {
      final client = ContractClient()..rows = [runRow('s', 1, status: status)];
      await RunDraftStore().save({'ownerUserId': 'a', 'sessionId': 's'});
      final restarted = RunDraftStore();
      expect(await verifiedRunDraft(restarted, RunningSessionApi(client), 'a'),
          isNull);
      expect(await restarted.loadForUser('a'), isNull);
    });
  }
  test(
      'in-progress checkpoint restores time/distance/pause/route; offline keeps it for retry',
      () async {
    final client = ContractClient()..offline = true;
    final store = RunDraftStore();
    final route = [
      {'lat': 13.7, 'lng': 100.5},
      {'lat': 13.8, 'lng': 100.6}
    ];
    await store.save({
      'ownerUserId': 'a',
      'sessionId': 's',
      'elapsedSeconds': 123,
      'distanceKm': 1.2,
      'isPaused': true,
      'environment': 'park',
      'sessionType': 'easy',
      'routePoints': route
    });
    await expectLater(verifiedRunDraft(store, RunningSessionApi(client), 'a'),
        throwsA(isA<ApiException>()));
    expect(await store.loadForUser('a'), isNotNull);
    client
      ..offline = false
      ..rows = [runRow('s', 0, status: 'in_progress')];
    final draft =
        (await verifiedRunDraft(store, RunningSessionApi(client), 'a'))!;
    final setup = RunSetupNotifier(QuestApi(client), RunningSessionApi(client))
      ..restoreDraft(draft);
    final run = RunSessionNotifier(RunningSessionApi(client))
      ..restore(
          elapsed: draft['elapsedSeconds'],
          distance: draft['distanceKm'],
          paused: draft['isPaused']);
    expect(run.elapsedSeconds, 123);
    expect(run.distanceKm, 1.2);
    expect(run.isPaused, true);
    expect(setup.restoredRoute, route);
    await Future<void>.delayed(Duration.zero);
    setup.dispose();
    run.dispose();
  });
  test(
      'draft account isolation preserves previous owner and rejects foreign server detail',
      () async {
    final store = RunDraftStore();
    await store.save({'ownerUserId': 'a', 'sessionId': 's'});
    expect(await store.loadForUser('b'), isNull);
    expect(await store.loadForUser('a'), isNotNull);
    final client = ContractClient()..rows = [runRow('s', 1)..['user_id'] = 'b'];
    await expectLater(verifiedRunDraft(store, RunningSessionApi(client), 'a'),
        throwsStateError);
    expect(await store.loadForUser('a'), isNotNull);
  });
  for (final lost in [false, true]) {
    test('failed complete retries via detail first (response lost=$lost)',
        () async {
      final client = ContractClient()
        ..rows = [runRow('s', 0, status: 'in_progress')]
        ..failRun = !lost
        ..lostRun = lost;
      final state =
          RunSessionNotifier(RunningSessionApi(client), ownerUserId: 'a')
            ..elapsedSeconds = 123
            ..setDistance(2);
      addTearDown(state.dispose);
      expect(await state.stop(sessionId: 's', sideQuests: []), isNull);
      expect(state.finishError, isNotNull);
      client
        ..failRun = false
        ..lostRun = false;
      expect(await state.stop(sessionId: 's', sideQuests: []), isNotNull);
      expect(client.runPatches, lost ? 1 : 2);
      expect(client.calls, contains('GET /api/running-sessions/s'));
    });
  }
  test(
      'complete overlap blocked and offline reconciliation never sends second PATCH',
      () async {
    final client = ContractClient()
      ..rows = [runRow('s', 0, status: 'in_progress')]
      ..pendingComplete = Completer<Map<String, dynamic>>();
    final state = RunSessionNotifier(RunningSessionApi(client));
    addTearDown(state.dispose);
    final first = state.stop(sessionId: 's', sideQuests: []);
    await Future<void>.delayed(Duration.zero);
    expect(await state.stop(sessionId: 's', sideQuests: []), isNull);
    expect(client.runPatches, 1);
    client.pendingComplete!.completeError(ApiException(0, 'lost'));
    await first;
    client.offline = true;
    expect(await state.stop(sessionId: 's', sideQuests: []), isNull);
    expect(client.runPatches, 1);
  });
  test(
      'progress reload uses server level and remaining EXP; old account response cannot overwrite new',
      () async {
    final client = ContractClient();
    final auth = TestAuth(client)..signIn('a');
    final container = ProviderContainer(overrides: [
      apiClientProvider.overrideWithValue(client),
      authProvider.overrideWith((_) => auth)
    ]);
    addTearDown(container.dispose);
    final first = await container.read(progressProvider.future);
    expect([first.coinBalance, first.level, first.exp, first.expToNext],
        [87, 5, 30, 240]);
    expect(first.fraction, .125);
    client.pendingProgress = Completer<Map<String, dynamic>>();
    container.invalidate(progressProvider);
    final old = container.read(progressProvider.future);
    auth.signOut();
    auth.signIn('b');
    final pending = client.pendingProgress!;
    client.pendingProgress = null;
    client.progress = {
      'coinBalance': 9,
      'level': 8,
      'exp': 25,
      'expToNext': 270
    };
    final next = await container.read(progressProvider.future);
    pending.complete({
      'data': {'coinBalance': 999, 'level': 99, 'exp': 0, 'expToNext': 1000}
    });
    await old;
    expect(container.read(progressProvider).asData!.value.coinBalance,
        next.coinBalance);
    expect(next.level, 8);
    expect(next.fraction, closeTo(25 / 270, .00001));
    container.invalidate(progressProvider);
    expect((await container.read(progressProvider.future)).level, 8);
  });
  test('progress error/loading never masquerades as initial zero balance',
      () async {
    final client = ContractClient()..offline = true;
    final auth = TestAuth(client)..signIn('a');
    final container = ProviderContainer(overrides: [
      apiClientProvider.overrideWithValue(client),
      authProvider.overrideWith((_) => auth)
    ]);
    addTearDown(container.dispose);
    expect(container.read(progressProvider).asData, isNull);
    await expectLater(
        container.read(progressProvider.future), throwsA(isA<ApiException>()));
    expect(container.read(progressProvider).hasError, true);
  });
  for (final environments in [
    ['park', 'park'],
    ['treadmill', 'treadmill'],
    ['park', 'treadmill']
  ]) {
    test(
        '3km main quest accumulates server sessions 1+2 (${environments.join('+')}) and never requests reward twice',
        () async {
      final client = ContractClient()
        ..rows = [runRow('s1', 1, environment: environments[0])];
      var rewards = 0;
      final state = DailyQuestNotifier(
          ProgramApi(client), RunningSessionApi(client), 'a', day,
          onConfirmed: () => rewards++);
      addTearDown(state.dispose);
      await state.refresh();
      expect(state.saved, 1);
      expect(client.questPatches, 0);
      client.rows.add(runRow('s2', 2, environment: environments[1]));
      await Future.wait([state.refresh(), state.refresh()]);
      expect(state.saved, 3);
      expect(state.completed, true);
      expect(client.questPatches, 1);
      expect(rewards, 1);
      final restarted = DailyQuestNotifier(
          ProgramApi(client), RunningSessionApi(client), 'a', day);
      await restarted.refresh();
      expect(restarted.saved, 3);
      expect(restarted.completed, true);
      expect(client.questPatches, 1);
      restarted.dispose();
    });
  }
  test(
      'session IDs deduplicate; abandoned/pending, different type/day, foreign owner excluded',
      () async {
    final q = questRow();
    final valid = runRow('1', 1);
    expect(
        savedQuestValue(
            q,
            [
              valid,
              valid,
              runRow('2', 2, status: 'abandoned'),
              runRow('3', 2, status: 'in_progress'),
              runRow('4', 2, ended: '2026-10-16T10:00:00Z'),
              runRow('5', 2)..['session_type'] = 'tempo'
            ],
            day),
        1);
    q['running_session_id'] = '2';
    expect(savedQuestValue(q, [valid, runRow('2', 2)], day), 2);
    final client = ContractClient()
      ..rows = [runRow('foreign', 3)..['user_id'] = 'b'];
    final state = DailyQuestNotifier(
        ProgramApi(client), RunningSessionApi(client), 'a', day);
    await state.refresh();
    expect(client.questPatches, 0);
    expect(state.error, isNotNull);
    state.dispose();
  });
  for (final lost in [false, true]) {
    test(
        'goal reached but Main Quest fails: no fake reward, retry checks status (lost=$lost)',
        () async {
      final client = ContractClient()
        ..rows = [runRow('s', 3)]
        ..failQuest = !lost
        ..lostQuest = lost;
      final state = DailyQuestNotifier(
          ProgramApi(client), RunningSessionApi(client), 'a', day);
      await state.refresh();
      expect(state.completed, false);
      expect(state.reward, isNull);
      expect(
          state.error, contains('ครบเป้าหมายแล้ว แต่ยังบันทึกภารกิจไม่สำเร็จ'));
      client
        ..failQuest = false
        ..lostQuest = false;
      await state.refresh();
      expect(state.completed, true);
      expect(client.questPatches, lost ? 1 : 2);
      state.dispose();
    });
  }
  test(
      'minutes quest uses actual seconds and Bangkok completion-day midnight rule',
      () async {
    final client = ContractClient()
      ..quest = questRow(unit: 'minutes', target: 30)
      ..rows = [
        runRow('1', 100, seconds: 600, ended: '2026-10-16T17:00:00Z'),
        runRow('2', 100, seconds: 1200, ended: '2026-10-17T16:59:59Z'),
        runRow('old', 100, seconds: 9999, ended: '2026-10-16T16:59:59Z'),
        runRow('next', 100, seconds: 9999, ended: '2026-10-17T17:00:00Z')
      ];
    final state = DailyQuestNotifier(
        ProgramApi(client), RunningSessionApi(client), 'a', day);
    await state.refresh();
    expect(state.saved, 30);
    expect(state.completed, true);
    state.dispose();
  });
  test(
      'Side Quest confirmation, overlap, retry, daily persistence/account/day isolation and no reassign',
      () async {
    final client = ContractClient();
    var today = day;
    var active = true;
    var refreshes = 0;
    RunSetupNotifier setup(String owner) =>
        RunSetupNotifier(QuestApi(client), RunningSessionApi(client),
            owner: owner,
            store: const DailySideQuestStore(),
            day: () => today,
            isRunning: () => active,
            onReward: () => refreshes++);
    final first = setup('a');
    await first.selectEnvironment(env: 'park', mainQuestSessionType: 'easy');
    expect(await first.startRun(mainQuestSessionType: 'easy'), true);
    active = false;
    await first.completeSideQuest('i1');
    expect(client.sidePatches, 0);
    active = true;
    client.failSide = true;
    await first.completeSideQuest('i1');
    expect(first.isDone('i1'), false);
    expect(first.errorMessage, contains('ลองใหม่ได้'));
    client.failSide = false;
    client.pendingSide = Completer<Map<String, dynamic>>();
    final finishing = first.completeSideQuest('i1');
    await Future<void>.delayed(Duration.zero);
    await first.completeSideQuest('i1');
    expect(client.sidePatches, 2);
    client.pendingSide!.complete(client.sideResult('i1'));
    await finishing;
    client.pendingSide = null;
    expect(first.isDone('i1'), true);
    expect(refreshes, 1);
    await first.completeSideQuest('i1');
    expect(client.sidePatches, 2);
    await first.selectEnvironment(env: 'road', mainQuestSessionType: 'tempo');
    expect(client.generated, 1);
    final restarted = setup('a');
    await restarted.restoreDaily();
    expect(restarted.isDone('i1'), true);
    expect(restarted.activeSideQuests.first.confirmedCoins,
        isNull); // no cached reward claim
    await restarted.selectEnvironment(env: 'city', mainQuestSessionType: null);
    client.rows.first['status'] = 'completed';
    expect(await restarted.startRun(mainQuestSessionType: null), true);
    await restarted.completeSideQuest('i2');
    expect(client.sidePatches, 2);
    expect(client.activations, 1);
    final other = setup('b');
    await other.restoreDaily();
    expect(other.sideQuests, isEmpty);
    today = '2026-10-18';
    restarted.checkDay();
    expect(restarted.sideQuests, isEmpty);
    await restarted.selectEnvironment(env: 'park', mainQuestSessionType: null);
    expect(client.generated, 2);
    first.dispose();
    restarted.dispose();
    other.dispose();
  });
  test(
      'all Side Quests done retains day completion through restart and new session',
      () async {
    final client = ContractClient();
    final setup = RunSetupNotifier(QuestApi(client), RunningSessionApi(client),
        owner: 'a', store: const DailySideQuestStore(), day: () => day);
    await setup.selectEnvironment(env: 'park', mainQuestSessionType: 'easy');
    await setup.startRun(mainQuestSessionType: 'easy');
    for (final id in ['i1', 'i2', 'i3']) {
      await setup.completeSideQuest(id);
    }
    expect(setup.dailyComplete, true);
    expect(client.sidePatches, 3);
    client.rows.first['status'] = 'completed';
    setup.reset();
    await setup.selectEnvironment(env: 'park', mainQuestSessionType: null);
    await setup.startRun(mainQuestSessionType: null);
    expect(setup.dailyComplete, true);
    expect(client.activations, 1);
    setup.dispose();
  });
  testWidgets(
      'prepare finish freezes elapsed time before draft storage is drained',
      (tester) async {
    final run = RunSessionNotifier(RunningSessionApi(ContractClient()))
      ..start();
    await tester.pump(const Duration(seconds: 2));
    final elapsed = run.elapsedSeconds;
    run.prepareFinish();
    await tester.pump(const Duration(seconds: 4));
    expect(run.elapsedSeconds, elapsed);
    expect(run.isRunning, false);
    run.dispose();
  });
  test(
      'new Thai day is checked on foreground and an old-day Main Quest cannot complete',
      () async {
    var today = day;
    final clock = TrainingDay(today: () => today);
    final container = ProviderContainer(
        overrides: [trainingDayProvider.overrideWith((_) => clock)]);
    expect(container.read(trainingDayProvider), day);
    today = '2026-10-18';
    clock.didChangeAppLifecycleState(AppLifecycleState.resumed);
    expect(container.read(trainingDayProvider), today);
    final client = ContractClient()..rows = [runRow('s', 3)];
    final main = DailyQuestNotifier(
        ProgramApi(client), RunningSessionApi(client), 'a', day,
        currentDay: () => today);
    await main.refresh();
    expect(client.questPatches, 0);
    main.dispose();
    container.dispose();
  });
  test(
      'uncertain Side Quest generation does not generate a replacement daily set',
      () async {
    final client = ContractClient()..offline = true;
    final first = RunSetupNotifier(QuestApi(client), RunningSessionApi(client),
        owner: 'a', store: const DailySideQuestStore(), day: () => day);
    await first.selectEnvironment(env: 'park', mainQuestSessionType: 'easy');
    expect(first.errorMessage, isNotNull);
    client.offline = false;
    final restarted = RunSetupNotifier(
        QuestApi(client), RunningSessionApi(client),
        owner: 'a', store: const DailySideQuestStore(), day: () => day);
    await restarted.selectEnvironment(
        env: 'road', mainQuestSessionType: 'easy');
    expect(client.generated, 0);
    expect(restarted.errorMessage, contains('ไม่สร้างชุดซ้ำ'));
    first.dispose();
    restarted.dispose();
  });
  test(
      'cached unfinished run blocks a new session instead of overwriting its checkpoint',
      () async {
    final client = ContractClient()
      ..rows = [runRow('s', 0, status: 'in_progress')];
    await runDraftStore.save({'ownerUserId': 'a', 'sessionId': 's'});
    final setup = RunSetupNotifier(QuestApi(client), RunningSessionApi(client),
        owner: 'a')
      ..environment = 'park';
    expect(await setup.startRun(mainQuestSessionType: 'easy'), false);
    expect(client.starts, 0);
    expect((await runDraftStore.loadForUser('a'))!['sessionId'], 's');
    setup.dispose();
  });
  test('Thai day keys do not depend on device local timezone', () {
    expect(trainingDateKey('2026-10-16T16:59:59Z'), '2026-10-16');
    expect(trainingDateKey('2026-10-16T17:00:00Z'), day);
  });
}
