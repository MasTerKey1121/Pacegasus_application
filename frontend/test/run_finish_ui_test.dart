import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart' hide Feedback;
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
// ignore: implementation_imports
import 'package:google_fonts/src/google_fonts_base.dart' as fonts;
import 'package:pacegasus/models/run_result.dart';
import 'package:pacegasus/providers/auth_provider.dart';
import 'package:pacegasus/providers/daily_quest_provider.dart';
import 'package:pacegasus/providers/post_run_quest_provider.dart';
import 'package:pacegasus/providers/progress_provider.dart';
import 'package:pacegasus/providers/rpe_provider.dart';
import 'package:pacegasus/providers/run_provider.dart';
import 'package:pacegasus/providers/run_rewards_provider.dart';
import 'package:pacegasus/providers/run_setup_provider.dart';
import 'package:pacegasus/screens/run/reward_screen.dart';
import 'package:pacegasus/screens/run/run_session_screen.dart';
import 'package:pacegasus/screens/run/run_summary_screen.dart';
import 'package:pacegasus/services/program_api.dart';
import 'package:pacegasus/services/quest_api.dart';
import 'package:pacegasus/services/run_draft_store.dart';
import 'package:pacegasus/services/running_session_api.dart';
import 'daily_quest_surfaces_test.dart' show Fonts, Feedback;
import 'run_quest_regression_test.dart'
    show ContractClient, TestAuth, day, runRow, DelayedStorage;

class DelayedQuest extends DailyQuestNotifier {
  DelayedQuest(ContractClient client)
      : super(ProgramApi(client), RunningSessionApi(client), 'a', day);
  final gate = Completer<void>();
  int reads = 0;
  @override
  Future<void> refresh() {
    reads++;
    return gate.future;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
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

  testWidgets(
      'checkpoint has loading UI; background/resume and repeat taps cannot duplicate finish; slow quests do not block Summary',
      (tester) async {
    await size(tester);
    final client = ContractClient()
      ..rows = [runRow('s', 0, status: 'in_progress')];
    final daily = DelayedQuest(client);
    final storage = DelayedStorage();
    final store = RunDraftStore(storage: storage);
    final run = RunSessionNotifier(RunningSessionApi(client),
        ownerUserId: 'a', elapsedClock: () => Duration.zero)
      ..restore(elapsed: 2803, distance: 4.98, paused: false);
    final setup = RunSetupNotifier(QuestApi(client), RunningSessionApi(client))
      ..environment = 'treadmill'
      ..sessionId = 's';
    await tester.pumpWidget(ProviderScope(
        overrides: [
          apiClientProvider.overrideWithValue(client),
          authProvider.overrideWith((_) => TestAuth(client)..signIn('a')),
          runProvider.overrideWith((_) => run),
          runSetupProvider.overrideWith((_) => setup),
          dailyQuestProvider.overrideWith((_) => daily),
          runDraftStoreProvider.overrideWithValue(store),
        ],
        child: MaterialApp(
            theme: ThemeData.dark(), home: const RunSessionScreen())));
    await tester.pumpAndSettle();
    await tester.tap(find.text('■ จบการวิ่ง'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField), '4.98');
    await tester.tap(find.text('จบการวิ่ง'));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('กำลังเก็บข้อมูลการวิ่ง'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsWidgets);
    expect(run.elapsedSeconds, 2803);
    expect(run.finishBusy, true);
    for (final state in [
      AppLifecycleState.inactive,
      AppLifecycleState.hidden,
      AppLifecycleState.paused,
      AppLifecycleState.hidden,
      AppLifecycleState.inactive,
      AppLifecycleState.resumed
    ]) {
      tester.binding.handleAppLifecycleStateChanged(state);
    }
    await tester.pump();
    expect(client.runPatches, 0);
    storage.gate.complete();
    await tester.pumpAndSettle();
    expect(find.byType(RunSummaryScreen), findsOneWidget);
    expect(find.byType(RunSessionScreen), findsNothing);
    expect(find.text('บันทึกผลวิ่งแล้ว กำลังตรวจสอบภารกิจและรางวัล'),
        findsOneWidget);
    expect(client.runPatches, 1);
    expect(client.questPatches + client.sidePatches, 0);
    final container = ProviderScope.containerOf(
        tester.element(find.byType(RunSummaryScreen)));
    daily.error = 'offline';
    daily.gate.complete();
    await tester.pumpAndSettle();
    expect(find.text('ผลวิ่งบันทึกแล้ว รางวัลรอตรวจสอบ · ลองใหม่'),
        findsOneWidget);
    expect(client.runPatches, 1);
    expect(container.read(postRunQuestCheckProvider('s')).hasError, true);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets(
      'feedback navigation does not await pending quest reward; no duplicate reward write',
      (tester) async {
    await size(tester);
    final client = ContractClient()..rows = [runRow('s', 1)..['rpe_logs'] = []];
    final daily = DelayedQuest(client);
    final feedback = Feedback(client);
    final setup = RunSetupNotifier(QuestApi(client), RunningSessionApi(client))
      ..sessionId = 's'
      ..mainQuestAtStart = 'q'
      ..environment = 'treadmill';
    final result = RunResult(
        distanceKm: 1,
        duration: const Duration(seconds: 2803),
        avgPace: '46:43',
        calories: 62,
        rpe: 3,
        stressLevel: 2,
        moodIndex: 2,
        hasInjury: false);
    await tester.pumpWidget(ProviderScope(
        overrides: [
          apiClientProvider.overrideWithValue(client),
          authProvider.overrideWith((_) => TestAuth(client)..signIn('a')),
          dailyQuestProvider.overrideWith((_) => daily),
          runSetupProvider.overrideWith((_) => setup),
          rpeApiProvider.overrideWithValue(feedback),
          progressProvider
              .overrideWith((_) async => const GameProgress(148, 2, 35, 210)),
        ],
        child: MaterialApp(
            theme: ThemeData.dark(), home: RunSummaryScreen(result: result))));
    await tester.pumpAndSettle();
    await tester.tap(find.text('ส่งข้อมูล'));
    await tester.tap(find.text('ส่งข้อมูล'), warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(find.byType(RewardScreen), findsOneWidget);
    expect(find.text('รางวัลภารกิจรอตรวจสอบ'), findsOneWidget);
    expect(feedback.writes, 1);
    expect(client.questPatches + client.sidePatches, 0);
    daily.error = 'offline';
    daily.gate.complete();
    await tester.pumpAndSettle();
    expect(find.text('รางวัลภารกิจรอตรวจสอบ · ลองใหม่'), findsOneWidget);
    expect(feedback.writes, 1);
    expect(setup.mainQuestAtStart, isNull); // feedback already reset setup
    daily.error = null;
    daily.quest = {'id': 'q', 'status': 'completed'};
    await tester.tap(find.text('รางวัลภารกิจรอตรวจสอบ · ลองใหม่'));
    await tester.pumpAndSettle();
    final container =
        ProviderScope.containerOf(tester.element(find.byType(RewardScreen)));
    final ledger = container.read(runRewardsProvider);
    expect(ledger.hasMissing('s'), true); // completed is not a reward receipt
    expect(ledger.total('s'), isNull);
    expect(feedback.writes, 1);
    expect(client.questPatches + client.sidePatches, 0);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
