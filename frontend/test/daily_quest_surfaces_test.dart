import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:pacegasus/services/onboarding_api.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
// ignore: implementation_imports
import 'package:google_fonts/src/google_fonts_base.dart' as fonts;
import 'package:pacegasus/providers/auth_provider.dart';
import 'package:pacegasus/providers/daily_quest_provider.dart';
import 'package:pacegasus/providers/progress_provider.dart';
import 'package:pacegasus/providers/run_provider.dart';
import 'package:pacegasus/providers/run_setup_provider.dart';
import 'package:pacegasus/screens/home/home_screen.dart';
import 'package:pacegasus/screens/home/main_shell.dart';
import 'package:pacegasus/screens/run/run_select_screen.dart';
import 'package:pacegasus/screens/run/run_session_screen.dart';
import 'package:pacegasus/screens/run/run_summary_screen.dart';
import 'package:pacegasus/screens/run/reward_screen.dart';
import 'package:pacegasus/models/run_result.dart';
import 'package:pacegasus/providers/rpe_provider.dart';
import 'package:pacegasus/services/rpe_api.dart';
import 'package:pacegasus/services/program_api.dart';
import 'package:pacegasus/services/quest_api.dart';
import 'package:pacegasus/services/running_session_api.dart';
import 'package:pacegasus/services/run_draft_store.dart';
import 'package:pacegasus/providers/program_provider.dart';
import 'package:pacegasus/providers/wellness_provider.dart';
import 'package:pacegasus/services/wellness_api.dart';
import 'run_quest_regression_test.dart'
    show ContractClient, TestAuth, runRow, questRow, day;

class Fonts extends Fake implements AssetManifest {
  @override
  List<String> listAssets() => [
        for (final family in ['Kanit', 'Sarabun'])
          for (final weight in ['Regular', 'Medium', 'SemiBold', 'Bold'])
            'test-fonts/$family-$weight.ttf'
      ];
}

class Feedback extends RpeApi {
  Feedback(super.client);
  int writes = 0;
  @override
  Future<Map<String, dynamic>> logRunFeedback(
      {required String runningSessionId,
      required int durationMinutes,
      required int rpeScore,
      required int stressLevel,
      required String mood,
      required bool hasPain,
      String? painNote}) async {
    writes++;
    return {
      'success': true,
      'data': {
        'id': 'feedback',
        'reward': {
          'awarded': true,
          'coins': 5,
          'exp': 5,
          'progress': {
            'coinBalance': 87,
            'level': 5,
            'exp': 30,
            'expToNext': 240
          }
        }
      }
    };
  }
}

void screenTest(String name, WidgetTesterCallback body) =>
    testWidgets(name, body,
        variant: TargetPlatformVariant.only(TargetPlatform.windows));

void main() {
  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    GoogleFonts.config.allowRuntimeFetching = false;
    fonts.assetManifest = Fonts();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMessageHandler('flutter/assets', (message) async {
      if (message != null &&
          utf8.decode(message.buffer.asUint8List()).startsWith('test-fonts/')) {
        return ByteData(0);
      }
      return null;
    });
  });
  Future<void> size(WidgetTester tester) async {
    tester.view.physicalSize = const Size(430, 950);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  for (final surface in ['Home', 'select', 'session']) {
    screenTest(
        '$surface shows the same persisted Main Quest and separate Side Quest even after main completion',
        (tester) async {
      await size(tester);
      final client = ContractClient();
      final main = DailyQuestNotifier(
          ProgramApi(client), RunningSessionApi(client), 'a', day)
        ..quest = questRow()
        ..saved = 1;
      final setup =
          RunSetupNotifier(QuestApi(client), RunningSessionApi(client))
            ..environment = 'treadmill'
            ..sessionId = 'run1'
            ..sessionType = 'easy';
      await setup.selectEnvironment(
          env: 'treadmill', mainQuestSessionType: 'easy');
      await setup.startRun(mainQuestSessionType: 'easy');
      final run = RunSessionNotifier(RunningSessionApi(client))
        ..isRunning = true
        ..distanceKm = .5;
      await tester.pumpWidget(ProviderScope(
          overrides: [
            apiClientProvider.overrideWithValue(client),
            authProvider.overrideWith((_) => TestAuth(client)..signIn('a')),
            dailyQuestProvider.overrideWith((_) => main),
            runProvider.overrideWith((_) => run),
            runSetupProvider.overrideWith((_) => setup),
            progressProvider
                .overrideWith((_) async => const GameProgress(87, 5, 30, 240)),
          ],
          child: MaterialApp(
              theme: ThemeData.dark(),
              home: surface == 'Home'
                  ? HomeScreen(avatarRendererBuilder: (_) => const SizedBox())
                  : surface == 'select'
                      ? const RunTypeSelectScreen()
                      : const RunSessionScreen())));
      await tester.pumpAndSettle();
      if (surface == 'session') {
        await tester.tap(find.text('ภารกิจ'));
        await tester.pumpAndSettle();
      }
      expect(find.textContaining('วิ่งแล้ว 1.00 / 3.00 กม.'), findsOneWidget);
      expect(find.text('33.33%'), findsOneWidget);
      if (surface == 'session') {
        expect(find.textContaining('ประมาณการรอบนี้ +0.50'), findsOneWidget);
      }
      client.quest['status'] = 'completed';
      client.rows = [runRow('run1', 1)];
      await main.refresh();
      await tester.pump();
      expect(
          find.text(surface == 'Home'
              ? 'คุณทำภารกิจประจำวันสำเร็จแล้ว'
              : 'คุณทำภารกิจประจำวันเสร็จแล้ว'),
          findsOneWidget);
      if (surface == 'Home') {
        await tester.tap(find.byKey(const Key('home-sheet-handle')));
        await tester.pumpAndSettle();
      }
      expect(find.textContaining('Quest 1'), findsWidgets);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }
  screenTest(
      'feedback double tap writes once; reward amounts and server progress are shown',
      (tester) async {
    await size(tester);
    final client = ContractClient()
      ..rows = [runRow('run1', 3)..['rpe_logs'] = []];
    final feedback = Feedback(client);
    final setup = RunSetupNotifier(QuestApi(client), RunningSessionApi(client))
      ..sessionId = 'run1'
      ..environment = 'treadmill';
    final result = RunResult(
        distanceKm: 3,
        duration: const Duration(minutes: 30),
        avgPace: '10:00',
        calories: 186,
        rpe: 3,
        stressLevel: 2,
        moodIndex: 2,
        hasInjury: false);
    await tester.pumpWidget(ProviderScope(
        overrides: [
          apiClientProvider.overrideWithValue(client),
          authProvider.overrideWith((_) => TestAuth(client)..signIn('a')),
          runSetupProvider.overrideWith((_) => setup),
          rpeApiProvider.overrideWithValue(feedback),
        ],
        child: MaterialApp(
            theme: ThemeData.dark(), home: RunSummaryScreen(result: result))));
    await tester.pumpAndSettle();
    final button = find.text('ส่งข้อมูล');
    await tester.tap(button);
    await tester.tap(button, warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(feedback.writes, 1);
    expect(find.byType(RewardScreen), findsOneWidget);
    expect(find.text('+5 🌙'), findsOneWidget);
    expect(find.text('+5 ⭐'), findsOneWidget);
    final container =
        ProviderScope.containerOf(tester.element(find.byType(RewardScreen)));
    final progress = await container.read(progressProvider.future);
    expect([
      progress.coinBalance,
      progress.level,
      progress.exp,
      progress.expToNext
    ], [
      87,
      5,
      30,
      240
    ]);
    expect(progress.fraction, .125);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
  screenTest(
      'Home keeps offline draft and provides a working retry before resume offer',
      (tester) async {
    await size(tester);
    final client = ContractClient()
      ..offline = true
      ..rows = [runRow('s', 1, status: 'in_progress')];
    await runDraftStore.save(
        {'ownerUserId': 'a', 'sessionId': 's', 'environment': 'treadmill'});
    final wellness = WellnessNotifier(_Wellness(client));
    await tester.pumpWidget(ProviderScope(overrides: [
      apiClientProvider.overrideWithValue(client),
      authProvider.overrideWith((_) => TestAuth(client)..signIn('a')),
      programProvider.overrideWith((ref) => _Program(client)),
      wellnessProvider.overrideWith((_) => wellness),
      progressProvider
          .overrideWith((_) async => const GameProgress(87, 5, 30, 240)),
    ], child: MaterialApp(theme: ThemeData.dark(), home: const MainShell())));
    await tester.pumpAndSettle();
    expect(find.textContaining('ตรวจสถานะ Session ไม่สำเร็จ'), findsOneWidget);
    expect(await runDraftStore.loadForUser('a'), isNotNull);
    client.offline = false;
    await tester.tap(find.text('ลองตรวจสถานะอีกครั้ง'));
    await tester.pumpAndSettle();
    expect(find.text('พบ Session การวิ่งที่ยังไม่เสร็จ'), findsOneWidget);
    await tester.tap(find.text('ไว้ภายหลัง'));
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox());
  });
}

class _Wellness extends WellnessApi {
  _Wellness(super.client);
  @override
  Future<Map<String, dynamic>> getToday() async => {
        'data': {'status': 'done', 'record': null}
      };
}

class _Program extends ProgramNotifier {
  _Program(ContractClient client)
      : super(ProgramApi(client), OnboardingApi(client));
  @override
  Future<void> restore({bool force = false}) async {}
}
