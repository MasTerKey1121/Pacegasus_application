import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pacegasus/providers/auth_provider.dart';
import 'package:pacegasus/providers/run_provider.dart';
import 'package:pacegasus/services/api_client.dart';
import 'package:pacegasus/services/run_draft_store.dart';
import 'package:pacegasus/services/run_finish_operation.dart';
import 'package:pacegasus/services/running_session_api.dart';
import 'auth_recovery_test.dart' show RecoveryApi;
import 'run_quest_regression_test.dart' show runRow, DelayedStorage;

class FinishApi extends RunningSessionApi {
  FinishApi() : super(ApiClient(baseUrl: 'http://localhost'));
  Map<String, dynamic> row = runRow('s', 0, status: 'in_progress');
  int reads = 0, writes = 0, healthReads = 0;
  int? readFailure, writeFailure, healthFailure;
  bool loseWrite = false;
  Completer<void>? detailGate, writeGate;
  final calls = <String>[];
  @override
  Future<Map<String, dynamic>> getDetail({required String sessionId}) async {
    reads++;
    calls.add('detail');
    if (detailGate != null) await detailGate!.future;
    if (readFailure != null) {
      final code = readFailure!;
      readFailure = null;
      throw ApiException(code, 'temporary');
    }
    return {'data': Map<String, dynamic>.from(row)};
  }

  @override
  Future<Map<String, dynamic>> health() async {
    healthReads++;
    calls.add('health');
    if (healthFailure != null) throw ApiException(healthFailure!, 'not ready');
    return {'success': true, 'message': 'Pacegasus API is running'};
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
    writes++;
    calls.add('complete');
    if (writeGate != null) await writeGate!.future;
    if (writeFailure != null) throw ApiException(writeFailure!, 'unavailable');
    row = {
      ...row,
      'status': 'completed',
      'distance_km': '$distanceKm',
      'duration_seconds': durationSeconds,
      'route_points': routePoints
    };
    if (loseWrite) throw ApiException(0, 'response lost');
    return {'data': row};
  }
}

Future<dynamic> finish(
  RunSessionNotifier run, {
  Future<void> Function()? save,
  Future<void> Function()? gps,
}) =>
    run.finish(
        sessionId: 's',
        sideQuests: [],
        persistCheckpoint: save ?? () async {},
        stopGps: gps ?? () async {},
        endLat: 13.7,
        endLng: 100.5,
        routePoints: [
          {'lat': 13.7, 'lng': 100.5},
          {'lat': 13.8, 'lng': 100.6}
        ]);

RunSessionNotifier runner(FinishApi api, {Duration? limit}) =>
    RunSessionNotifier(api,
        ownerUserId: 'a',
        finishLimit: limit ?? const Duration(seconds: 2),
        localStepLimit: const Duration(milliseconds: 40),
        gpsStopLimit: const Duration(milliseconds: 40),
        recoveryDelay: Duration.zero)
      ..elapsedSeconds = 2803
      ..distanceKm = 4.98;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));
  test(
      'checkpoint drains earlier timer writes and remains sealed until server confirmation',
      () async {
    final storage = DelayedStorage();
    final store = RunDraftStore(storage: storage);
    final old = store
        .save({'ownerUserId': 'a', 'sessionId': 's', 'elapsedSeconds': 100});
    final pending = store.savePendingCompletion({
      'ownerUserId': 'a',
      'sessionId': 's',
      'elapsedSeconds': 2803,
      'distanceKm': 4.98,
      'routePoints': [
        {'lat': 13.7, 'lng': 100.5}
      ]
    });
    await store
        .save({'ownerUserId': 'a', 'sessionId': 's', 'elapsedSeconds': 101});
    storage.gate.complete();
    await Future.wait([old, pending]);
    final draft = await store.loadForUser('a');
    expect(draft!['elapsedSeconds'], 2803);
    expect(draft['pendingCompletion'], true);
    expect(draft['routePoints'], hasLength(1));
    final restored = RunSessionNotifier(FinishApi())
      ..restore(
          elapsed: draft['elapsedSeconds'],
          distance: draft['distanceKm'],
          paused: false,
          pendingCompletion: true);
    expect(restored.isRunning, false);
    expect(restored.elapsedSeconds, 2803);
    restored.dispose();
  });
  test(
      'finish has visible stages before HTTP, freezes time and blocks repeated taps',
      () async {
    final api = FinishApi();
    var now = Duration.zero;
    final run =
        RunSessionNotifier(api, ownerUserId: 'a', elapsedClock: () => now)
          ..start();
    now = const Duration(seconds: 2803);
    run.distanceKm = 4.98;
    final saved = Completer<void>();
    final gps = Completer<void>();
    final stages = <String?>[];
    run.addListener(() => stages.add(run.finishStage));
    final first = finish(run, save: () => saved.future, gps: () => gps.future);
    expect(run.finishBusy, true);
    expect(run.finishStage, 'checkpoint');
    now += const Duration(minutes: 5);
    expect(run.elapsedSeconds, 2803);
    expect(await finish(run), isNull);
    expect(api.writes, 0);
    saved.complete();
    await Future<void>.delayed(Duration.zero);
    expect(run.finishStage, 'gps_stop');
    expect(run.checkpointSaved, true);
    gps.complete();
    final result = await first;
    expect(result.duration.inSeconds, 2803);
    expect(api.writes, 1);
    expect(
        stages,
        containsAll([
          'checkpoint',
          'gps_stop',
          'session_detail',
          'complete',
          'confirmed'
        ]));
    expect(run.finishBusy, false);
    run.dispose();
  });
  for (final step in ['storage', 'gps']) {
    test(
        '$step slow callback is bounded; a durable snapshot can finish despite native cleanup delay',
        () async {
      final api = FinishApi();
      final run = runner(api);
      final gate = Completer<void>();
      final result = await finish(run,
          save: step == 'storage' ? () => gate.future : null,
          gps: step == 'gps' ? () => gate.future : null);
      expect(run.finishBusy, false);
      expect(run.checkpointSaved, step == 'gps');
      if (step == 'storage') {
        expect(result, isNull);
        expect(run.finishError, isNotNull);
        expect(api.writes, 0);
      } else {
        expect(result, isNotNull);
        expect(run.finishError, isNull);
        expect(run.finishWarning, contains('GPS'));
        expect(api.writes, 1);
      }
      gate.complete();
      expect(await finish(run), isNotNull);
      expect(api.writes, 1);
      expect(run.elapsedSeconds, 2803);
      run.dispose();
    });
  }
  test(
      'local write failure never sends a request and does not claim durable storage',
      () async {
    final api = FinishApi();
    final run = runner(api);
    await finish(run,
        save: () async => throw StateError('storage unavailable'));
    expect(run.finishError, contains('ข้อมูลยังอยู่ในหน้านี้'));
    expect(run.checkpointSaved, false);
    expect(api.reads + api.writes, 0);
    run.dispose();
  });
  test(
      'native GPS cancellation failure does not block an otherwise confirmed run',
      () async {
    final api = FinishApi();
    final run = runner(api);
    var saved = 0;
    expect(
        await finish(run,
            save: () async {
              saved++;
            },
            gps: () async => throw StateError('native cancel failed')),
        isNotNull);
    expect(saved, 1);
    expect(run.checkpointSaved, true);
    expect(run.finishBusy, false);
    expect(run.finishWarning, contains('GPS'));
    expect(run.finishError, isNull);
    expect(api.writes, 1);
    run.dispose();
  });
  for (final code in [0, 408, 502, 503, 504]) {
    test(
        'transient $code recovers via health then validates session before one PATCH',
        () async {
      final api = FinishApi()..readFailure = code;
      final run = runner(api);
      expect(await finish(run), isNotNull);
      expect(api.calls, ['detail', 'health', 'detail', 'complete']);
      expect(api.writes, 1);
      run.dispose();
    });
  }
  test('health success cannot authorize a foreign or abandoned session',
      () async {
    for (final row in [
      runRow('s', 0)..['user_id'] = 'b',
      runRow('s', 0, status: 'abandoned')
    ]) {
      final api = FinishApi()
        ..readFailure = 503
        ..row = row;
      final run = runner(api);
      expect(await finish(run), isNull);
      expect(api.healthReads, 1);
      expect(api.writes, 0);
      run.dispose();
    }
  });
  test(
      'offline recovery is bounded and a completed response lost is only reconciled',
      () async {
    final api = FinishApi()
      ..readFailure = 0
      ..healthFailure = 503;
    final run = runner(api);
    expect(await finish(run), isNull);
    expect(api.healthReads, 3);
    expect(api.writes, 0);
    api.healthFailure = null;
    api.loseWrite = true;
    expect(await finish(run), isNotNull);
    expect(api.writes, 1);
    expect(api.calls.sublist(api.calls.length - 3),
        ['detail', 'complete', 'detail']);
    run.dispose();
  });
  test('uncertain PATCH with in-progress detail never auto-repeats the write',
      () async {
    final api = FinishApi()..writeFailure = 503;
    final run = runner(api);
    expect(await finish(run), isNull);
    expect(api.writes, 1);
    expect(api.calls, ['detail', 'complete', 'detail']);
    api.writeFailure = null;
    expect(await finish(run), isNotNull);
    expect(api.writes, 2);
    run.dispose();
  });
  test(
      'one total deadline expires; a late write cannot overwrite a new session',
      () async {
    final api = FinishApi()..writeGate = Completer<void>();
    final run = runner(api, limit: const Duration(milliseconds: 65));
    final clock = Stopwatch()..start();
    expect(await finish(run), isNull);
    expect(clock.elapsedMilliseconds, lessThan(500));
    expect(run.finishBusy, false);
    expect(api.writes, 1);
    run.start();
    api.writeGate!.complete();
    await Future<void>.delayed(Duration.zero);
    expect(run.lastResult, isNull);
    expect(run.distanceKm, 0);
    expect(run.isRunning, true);
    run.dispose();
  });
  test(
      'logout/dispose during detail cannot dispatch completion after the late read',
      () async {
    final api = FinishApi()..detailGate = Completer<void>();
    final run = runner(api);
    final saving = finish(run);
    await Future<void>.delayed(Duration.zero);
    run.dispose();
    api.detailGate!.complete();
    expect(await saving, isNull);
    expect(api.writes, 0);
  });
  test(
      '40-minute session refreshes expired access once and records the frozen result',
      () async {
    HttpOverrides.global = null;
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    var writes = 0;
    server.listen((request) async {
      final text = await utf8.decoder.bind(request).join();
      request.response.headers.contentType = ContentType.json;
      if (request.headers.value('authorization') != 'Bearer new-access') {
        request.response.statusCode = 401;
        request.response.write('{"message":"expired"}');
      } else if (request.method == 'PATCH') {
        writes++;
        final body = jsonDecode(text) as Map;
        expect(body['durationSeconds'], 2803);
        request.response
            .write(jsonEncode({'data': runRow('s', 4.98, seconds: 2803)}));
      } else {
        request.response
            .write(jsonEncode({'data': runRow('s', 0, status: 'in_progress')}));
      }
      await request.response.close();
    });
    final client = ApiClient(baseUrl: 'http://127.0.0.1:${server.port}');
    final authApi = RecoveryApi(client);
    final auth = AuthNotifier(authApi, client);
    await auth.completeLogin({
      'accessToken': 'expired-after-run',
      'refreshToken': 'stored',
      'user': {'id': 'a'}
    });
    var elapsed = Duration.zero;
    final run = RunSessionNotifier(RunningSessionApi(client),
        ownerUserId: 'a', elapsedClock: () => elapsed)
      ..start();
    elapsed = const Duration(seconds: 2803);
    run.distanceKm = 4.98;
    expect(await finish(run), isNotNull);
    expect(authApi.refreshes, 1);
    expect(writes, 1);
    expect(auth.state.status, AuthStatus.authenticated);
    expect(run.elapsedSeconds, 2803);
    run.dispose();
    auth.dispose();
  });
  test('a scoped HTTP timeout cannot later refresh or replay a PATCH',
      () async {
    HttpOverrides.global = null;
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    var requests = 0, refreshes = 0;
    server.listen((request) async {
      requests++;
      await request.drain<void>();
      await Future<void>.delayed(const Duration(milliseconds: 80));
      request.response.statusCode = 401;
      await request.response.close();
    });
    final client = ApiClient(baseUrl: 'http://127.0.0.1:${server.port}')
      ..onUnauthorized = () async {
        refreshes++;
        return true;
      };
    final op = RunFinishOperation(
        limit: const Duration(milliseconds: 20),
        isCurrent: () => true,
        logger: (_) {});
    await expectLater(
        op.run(
            () => client.patch('/api/running-sessions/s/complete', auth: true)),
        throwsA(anything));
    op.close();
    await Future<void>.delayed(const Duration(milliseconds: 100));
    expect(requests, 1);
    expect(refreshes, 0);
  });
  test(
      'finish diagnostics contain only stage, elapsed time, status and local reference',
      () {
    final logs = <String>[];
    final op = RunFinishOperation(isCurrent: () => true, logger: logs.add);
    op.stage('checkpoint');
    op.log('http_response', status: 503);
    expect(logs.join(), contains('ref=finish-'));
    expect(logs.join(), contains('status=503'));
    expect(logs.join(), isNot(contains('2803')));
    expect(logs.join(), isNot(contains('13.7')));
    op.close();
  });
}
