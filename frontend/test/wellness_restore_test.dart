import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pacegasus/providers/auth_provider.dart';
import 'package:pacegasus/providers/program_provider.dart';
import 'package:pacegasus/providers/wellness_provider.dart';
import 'package:pacegasus/screens/home/main_shell.dart';
import 'package:pacegasus/services/api_client.dart';
import 'package:pacegasus/services/auth_api.dart';
import 'package:pacegasus/services/onboarding_api.dart';
import 'package:pacegasus/services/program_api.dart';
import 'package:pacegasus/services/wellness_api.dart';

const done = <String, dynamic>{
  'data': {
    'status': 'done',
    'record': {
      'sleep_quality': 4,
      'energy_level': 4,
      'muscle_soreness': 2,
      'stress_level': 2,
      'motivation': 5,
    },
  },
};
const notDone = <String, dynamic>{
  'data': {'status': 'not_done', 'record': null}
};

class TestWellnessApi extends WellnessApi {
  TestWellnessApi() : super(ApiClient(baseUrl: 'http://localhost'));
  Future<Map<String, dynamic>> Function() today = () async => done;
  int reads = 0;
  int creates = 0;
  int updates = 0;
  @override
  Future<Map<String, dynamic>> getToday() {
    reads++;
    return today();
  }

  @override
  Future<Map<String, dynamic>> create(Map<String, dynamic> body) async {
    creates++;
    return {
      'data': {
        'status': 'done',
        'record': {
          'reward': {'awarded': true, 'coins': 5}
        }
      }
    };
  }

  @override
  Future<Map<String, dynamic>> update(Map<String, dynamic> body) async {
    updates++;
    return done;
  }
}

class TestAuth extends AuthNotifier {
  TestAuth()
      : super(AuthApi(ApiClient(baseUrl: 'http://localhost')),
            ApiClient(baseUrl: 'http://localhost'));
  void signIn(String userId) =>
      state = AuthState(status: AuthStatus.authenticated, user: {'id': userId});
  void signOut() => state = const AuthState(status: AuthStatus.unauthenticated);
}

class TestProgram extends ProgramNotifier {
  TestProgram()
      : super(ProgramApi(ApiClient(baseUrl: 'http://localhost')),
            OnboardingApi(ApiClient(baseUrl: 'http://localhost')));
  final pending = Completer<void>();
  @override
  Future<void> restore({bool force = false}) => pending.future;
}

void fillEntry(WellnessNotifier state) => state.update((e) {
      e.sleepQuality = 4;
      e.energyLevel = 4;
      e.muscleSoreness = 2;
      e.stressLevel = 2;
      e.motivation = 5;
    });

void main() {
  test('logout and login to the same account restores completed check-in',
      () async {
    final auth = TestAuth()..signIn('user-1');
    final api = TestWellnessApi();
    final container = ProviderContainer(overrides: [
      authProvider.overrideWith((ref) => auth),
      wellnessApiProvider.overrideWithValue(api),
    ]);
    addTearDown(container.dispose);
    final state = container.read(wellnessProvider);
    expect(await state.loadToday(), isTrue);
    expect(state.completedToday, isTrue);
    auth.signOut();
    expect(state.hasLoadedToday, isFalse);
    auth.signIn('user-1');
    expect(await state.loadToday(), isTrue);
    expect(state.completedToday, isTrue);
    expect(state.entry.sleepQuality, 4);
    expect(await state.submit(), isTrue);
    expect(api.creates, 0);
    expect(api.updates, 1);
    expect(state.awardedCoins, 0);
  });

  test('failed or malformed status cannot unlock a new check-in', () async {
    final api = TestWellnessApi()
      ..today = () async => throw ApiException(503, 'Unavailable');
    final state = WellnessNotifier(api);
    addTearDown(state.dispose);
    expect(await state.loadToday(), isFalse);
    fillEntry(state);
    expect(await state.submit(), isFalse);
    expect(api.creates, 0);
    api.today = () async => {'data': {}};
    expect(await state.loadToday(), isFalse);
    expect(await state.submit(), isFalse);
    api.today = () async => done;
    expect(await state.loadToday(), isTrue);
    expect(state.completedToday, isTrue);
  });

  test('late response from logged-out account cannot overwrite next account',
      () async {
    final oldRead = Completer<Map<String, dynamic>>();
    final api = TestWellnessApi()..today = () => oldRead.future;
    final state = WellnessNotifier(api);
    addTearDown(state.dispose);
    final stale = state.loadToday();
    state.reset();
    api.today = () async => notDone;
    expect(await state.loadToday(), isTrue);
    oldRead.complete(done);
    expect(await stale, isFalse);
    expect(state.completedToday, isFalse);
    expect(state.entry.isComplete, isFalse);
  });

  test('first check-in uses awarded coins; editing gives no additional reward',
      () async {
    final api = TestWellnessApi()..today = () async => notDone;
    final state = WellnessNotifier(api);
    addTearDown(state.dispose);
    await state.loadToday();
    fillEntry(state);
    expect(await state.submit(), isTrue);
    expect(state.awardedCoins, 5);
    expect(await state.submit(), isTrue);
    expect(state.awardedCoins, 0);
    expect(api.creates, 1);
    expect(api.updates, 1);
  });

  test('concurrent restores share one request', () async {
    final pending = Completer<Map<String, dynamic>>();
    final api = TestWellnessApi()..today = () => pending.future;
    final state = WellnessNotifier(api);
    addTearDown(state.dispose);
    final first = state.loadToday();
    final second = state.loadToday();
    expect(api.reads, 1);
    pending.complete(done);
    expect(await first, isTrue);
    expect(await second, isTrue);
    expect(state.isLoadingToday, isFalse);
  });

  testWidgets('home waits for wellness; failure offers retry before check-in',
      (tester) async {
    final pending = Completer<Map<String, dynamic>>();
    final api = TestWellnessApi()..today = () => pending.future;
    final program = TestProgram();
    final state = WellnessNotifier(api);
    await tester.pumpWidget(ProviderScope(overrides: [
      wellnessProvider.overrideWith((ref) => state),
      programProvider.overrideWith((ref) => program),
    ], child: const MaterialApp(home: MainShell())));
    await tester.pump();
    expect(
        api.reads, 1); // It starts even while program restoration is pending.
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.text('เช็กอินก่อนวิ่ง'), findsNothing);
    pending.completeError(ApiException(503, 'Unavailable'));
    await tester.pump();
    expect(find.text('ลองใหม่'), findsOneWidget);
    expect(find.text('เช็กอินก่อนวิ่ง'), findsNothing);
    final retry = Completer<Map<String, dynamic>>();
    api.today = () => retry.future;
    await tester.tap(find.text('ลองใหม่'));
    await tester.pump();
    expect(api.reads, 2);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    // Finish outstanding requests after the shell is removed.
    await tester.pumpWidget(const SizedBox());
    retry.complete(notDone);
    program.pending.complete();
    await tester.pump();
  });
}
