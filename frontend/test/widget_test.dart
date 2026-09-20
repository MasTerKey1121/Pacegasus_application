import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
// The package exposes this hook specifically for offline font-loading tests.
// ignore: implementation_imports
import 'package:google_fonts/src/google_fonts_base.dart' as fonts;
import 'package:pacegasus/providers/auth_provider.dart';
import 'package:pacegasus/providers/avatar_provider.dart';
import 'package:pacegasus/screens/home/home_avatar.dart';
import 'package:pacegasus/providers/program_provider.dart';
import 'package:pacegasus/providers/wellness_provider.dart';
import 'package:pacegasus/screens/home/home_screen.dart';
import 'package:pacegasus/screens/profile/profile_screen.dart';
import 'package:pacegasus/screens/run/run_select_screen.dart';
import 'package:pacegasus/screens/wellness/daily_wellness_screen.dart';
import 'package:pacegasus/screens/training/training_registration_screen.dart';
import 'package:pacegasus/screens/training/training_schedule_screen.dart';
import 'package:pacegasus/services/api_client.dart';
import 'package:pacegasus/services/auth_api.dart';
import 'package:pacegasus/services/onboarding_api.dart';
import 'package:pacegasus/services/program_api.dart';
import 'package:pacegasus/services/wellness_api.dart';

class _FontManifest extends Fake implements AssetManifest {
  @override
  List<String> listAssets() => [
        for (final family in ['Kanit', 'Sarabun'])
          for (final weight in ['Regular', 'Medium', 'SemiBold', 'Bold'])
            'test-fonts/$family-$weight.ttf',
      ];
}

class _Auth extends AuthNotifier {
  _Auth({String? uid = '1234567890'})
      : super(AuthApi(ApiClient(baseUrl: 'http://localhost')),
            ApiClient(baseUrl: 'http://localhost')) {
    state = AuthState(status: AuthStatus.authenticated, user: {
      'id': 'internal-uuid-not-the-public-uid',
      'uid': uid,
      'displayName': 'นักวิ่งทดสอบ'
    });
  }
}

class _Program extends ProgramNotifier {
  _Program()
      : super(ProgramApi(ApiClient(baseUrl: 'http://localhost')),
            OnboardingApi(ApiClient(baseUrl: 'http://localhost')));
  bool registered = true;
  bool scheduled = true;
  Map<String, dynamic>? quest = {
    'session_type': 'easy',
    'planned_value': 5,
    'unit': 'km',
    'status': 'pending'
  };
  @override
  bool get isRegistered => registered;
  @override
  bool get isScheduleSaved => scheduled;
  @override
  Map<String, dynamic>? get todayQuest => quest;
  @override
  Future<bool> loadCurrentWeek() async => true;
}

class _RestoreApi extends ProgramApi {
  _RestoreApi() : super(ApiClient(baseUrl: 'http://localhost'));
  int calls = 0;
  @override
  Future<Map<String, dynamic>> getCurrentWeek() async {
    calls++;
    throw ApiException(calls == 1 ? 503 : 404, 'temporary error');
  }
}

class _OnboardingApi extends OnboardingApi {
  _OnboardingApi() : super(ApiClient(baseUrl: 'http://localhost'));
  @override
  Future<Map<String, dynamic>> status() async => {'data': {}};
}

class _RegistrationApi extends ProgramApi {
  _RegistrationApi({this.active = false})
      : super(ApiClient(baseUrl: 'http://localhost'));
  bool active;
  int starts = 0;
  @override
  Future<Map<String, dynamic>> getTemplates() async => {
        'data': [
          {
            'level': 'beginner',
            'goal_label': 'sub_50',
            'duration_weeks_min': 4,
            'duration_weeks_max': 4,
          }
        ],
      };
  @override
  Future<Map<String, dynamic>> getCurrentWeek() async {
    if (!active) throw ApiException(404, 'no active plan');
    return {
      'data': {
        'templateLevel': 'beginner',
        'startDate': '2026-09-19',
        'scheduleSaved': false,
        'quests': <dynamic>[],
      }
    };
  }

  @override
  Future<Map<String, dynamic>> start({required String level}) async {
    starts++;
    active = true;
    return getCurrentWeek();
  }

  @override
  Future<Map<String, dynamic>> getQuestsInRange(
          {required String from, required String to}) async =>
      {
        'data': {'quests': <dynamic>[]}
      };
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
      'retry after a restore failure allows an account with no plan to register',
      () async {
    final api = _RestoreApi();
    final program = ProgramNotifier(api, _OnboardingApi());
    addTearDown(program.dispose);
    await program.restore();
    expect(program.errorMessage, isNotNull);
    await program.restore();
    expect(api.calls, 1);
    await program.restore(force: true);
    expect(api.calls, 2);
    expect(program.errorMessage, isNull);
    expect(program.isRegistered, isFalse);
    expect(program.isLoading, isFalse);
  });
  setUp(() {
    // Stub font bytes so interaction tests use Flutter's test font without HTTP.
    GoogleFonts.config.allowRuntimeFetching = false;
    fonts.assetManifest = _FontManifest();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMessageHandler('flutter/assets', (message) async {
      if (message != null &&
          utf8.decode(message.buffer.asUint8List()).startsWith('test-fonts/')) {
        return ByteData(0);
      }
      return null;
    });
  });

  Future<void> home(WidgetTester tester,
      {bool checkedIn = false,
      _Program? program,
      Size size = const Size(390, 844)}) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(ProviderScope(overrides: [
      avatarViewerBuilderProvider.overrideWithValue(
          (shirt, stage, animate, interactive) => const SizedBox()),
      authProvider.overrideWith((ref) => _Auth()),
      programProvider.overrideWith((ref) => program ?? _Program()),
      wellnessProvider.overrideWith((ref) =>
          WellnessNotifier(WellnessApi(ApiClient(baseUrl: 'http://localhost')))
            ..completedToday = checkedIn),
    ], child: MaterialApp(theme: ThemeData.dark(), home: const HomeScreen())));
    await tester.pumpAndSettle();
  }

  testWidgets(
      'wardrobe selection is shared with home and motion can be stopped',
      (tester) async {
    await home(tester);
    final container =
        ProviderScope.containerOf(tester.element(find.byType(HomeScreen)));
    await tester.tap(find.text('แต่งตัว'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('shirt-cloud')));
    await tester.pumpAndSettle();
    expect(container.read(avatarProvider).shirt, RunnerShirt.cloud);
    await tester.drag(find.text('เครื่องแต่งกาย'), const Offset(0, -280));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('stage-orbit')));
    await tester.pumpAndSettle();
    expect(container.read(avatarProvider).stage, RunnerStage.orbit);
    await tester.tap(find.text('ขยับเบา ๆ'));
    await tester.pumpAndSettle();
    expect(container.read(avatarProvider).motion, isFalse);
    await tester.tap(find.byTooltip('กลับ'));
    await tester.pumpAndSettle();
    expect(find.byType(HomeScreen), findsOneWidget);
    expect(container.read(avatarProvider).shirt, RunnerShirt.cloud);
    expect(tester.takeException(), isNull);
  });

  double extent(WidgetTester tester) => tester
      .widget<DraggableScrollableSheet>(
          find.byKey(const Key('home-quest-sheet')))
      .controller!
      .size;

  for (final existing in [false, true]) {
    testWidgets('registration screen opens schedule (existing=$existing)',
        (tester) async {
      tester.view.physicalSize = const Size(800, 1200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final api = _RegistrationApi(active: existing);
      await tester.pumpWidget(ProviderScope(
          overrides: [
            programProvider
                .overrideWith((ref) => ProgramNotifier(api, _OnboardingApi())),
          ],
          child: MaterialApp(
              theme: ThemeData.dark(),
              home: const TrainingRegistrationScreen())));
      await tester.pumpAndSettle();
      if (!existing) {
        await tester.tap(find.text('5K'));
        await tester.pumpAndSettle();
      }
      await tester.tap(find.text(existing
          ? 'จัดตารางซ้อมของแผนปัจจุบัน'
          : 'บันทึกและลงทะเบียนตารางซ้อม'));
      await tester.pumpAndSettle();
      expect(find.byType(TrainingScheduleScreen), findsOneWidget);
      expect(api.starts, existing ? 0 : 1);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('sheet collapses outside, opens at two levels, and drags down',
      (tester) async {
    await home(tester);
    expect(extent(tester), closeTo(.4, .005));
    await tester.tapAt(const Offset(8, 280));
    await tester.pumpAndSettle();
    expect(extent(tester), lessThan(.1));
    await tester.tap(find.byKey(const Key('home-sheet-handle')));
    await tester.pumpAndSettle();
    expect(extent(tester), closeTo(.4, .005));
    await tester.tap(find.byKey(const Key('home-sheet-handle')));
    await tester.pumpAndSettle();
    expect(extent(tester), closeTo(.76, .005));
    await tester.drag(
        find.byKey(const Key('home-sheet-handle')), const Offset(0, 650));
    await tester.pumpAndSettle();
    expect(extent(tester), lessThan(.1));
    expect(tester.takeException(), isNull);
  });

  testWidgets('avatar hides controls and restores the sheet', (tester) async {
    await home(tester);
    final avatar = find.byKey(const Key('home-avatar'));
    await tester.tapAt(tester.getTopLeft(avatar) + const Offset(110, 55));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('home-profile')), findsNothing);
    expect(find.byKey(const Key('home-quest-sheet')), findsNothing);
    await tester.tap(avatar);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('home-profile')), findsOneWidget);
    expect(extent(tester), closeTo(.4, .005));
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'right drawer is 25 percent and closes outside without a close button',
      (tester) async {
    await home(tester);
    await tester.tap(find.text('เมนู'));
    await tester.pumpAndSettle();
    expect(tester.getSize(find.byKey(const Key('home-menu'))).width,
        closeTo(390 * .25, 1));
    expect(find.byIcon(Icons.close), findsNothing);
    await tester.tapAt(const Offset(20, 260));
    await tester.pumpAndSettle();
    expect(
        tester
            .state<ScaffoldState>(find.byType(Scaffold).first)
            .isEndDrawerOpen,
        isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('primary action sends an unchecked runner to wellness',
      (tester) async {
    // Destination screens predate this redesign; use a wide viewport for this
    // navigation assertion with Flutter's deliberately wide test font.
    await home(tester, size: const Size(800, 1000));
    expect(find.text('เช็กอินก่อนวิ่ง'), findsOneWidget);
    await tester.tap(find.byKey(const Key('home-primary')));
    await tester.pumpAndSettle();
    expect(find.byType(DailyWellnessScreen), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('ready runner reaches run selection', (tester) async {
    await home(tester, checkedIn: true, size: const Size(800, 1000));
    await tester.tap(find.byKey(const Key('home-primary')));
    await tester.pumpAndSettle();
    expect(find.byType(RunTypeSelectScreen), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('wellness task disappears immediately after check-in',
      (tester) async {
    await home(tester);
    await tester.tap(find.byKey(const Key('home-sheet-handle')));
    await tester.pumpAndSettle();
    expect(find.text('เช็กอินสุขภาพ'), findsOneWidget);
    final container =
        ProviderScope.containerOf(tester.element(find.byType(HomeScreen)));
    container.read(wellnessProvider)
      ..completedToday = true
      ..notifyListeners();
    await tester.pumpAndSettle();
    expect(find.text('เช็กอินสุขภาพ'), findsNothing);
    expect(find.text('เริ่มวิ่ง'), findsOneWidget);
  });

  testWidgets('unrelated registration error does not block a loaded plan',
      (tester) async {
    final program = _Program()..errorMessage = 'registration error';
    await home(tester, checkedIn: true, program: program);
    expect(find.text('ลองโหลดอีกครั้ง'), findsNothing);
    expect(find.text('เริ่มวิ่ง'), findsOneWidget);
  });

  testWidgets(
      'registration, schedule, rest and completion keep the correct next action',
      (tester) async {
    final program = _Program()..registered = false;
    await home(tester, checkedIn: true, program: program);
    expect(find.text('เลือกแผนซ้อม'), findsOneWidget);
    program.registered = true;
    program.scheduled = false;
    program.notifyListeners();
    await tester.pumpAndSettle();
    expect(find.text('จัดตารางซ้อม'), findsOneWidget);
    program.scheduled = true;
    program.quest = null;
    program.notifyListeners();
    await tester.pumpAndSettle();
    expect(find.text('วันพักของคุณ'), findsOneWidget);
    expect(find.text('เริ่มวิ่ง'), findsNothing);
    program.quest = {'status': 'completed', 'session_type': 'easy'};
    program.notifyListeners();
    await tester.pumpAndSettle();
    expect(find.text('ทำแผนวันนี้สำเร็จ'), findsOneWidget);
    expect(find.text('เริ่มวิ่ง'), findsNothing);
  });

  testWidgets('profile displays and copies public UID, not database id',
      (tester) async {
    String? copied;
    tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') {
        copied = (call.arguments as Map)['text'] as String;
      }
      return null;
    });
    addTearDown(() => tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null));
    await home(tester);
    await tester.tap(find.byKey(const Key('home-profile')));
    await tester.pumpAndSettle();
    expect(find.byType(ProfileScreen), findsOneWidget);
    expect(find.text('UID: 1234567890'), findsOneWidget);
    expect(find.textContaining('internal-uuid'), findsNothing);
    await tester.tap(find.byTooltip('คัดลอก UID'));
    await tester.pumpAndSettle();
    expect(copied, '1234567890');
    await tester.pump(const Duration(seconds: 3));
    expect(tester.takeException(), isNull);
  });

  testWidgets('missing UID has no fabricated value or copy action',
      (tester) async {
    await tester.pumpWidget(ProviderScope(
        overrides: [authProvider.overrideWith((ref) => _Auth(uid: null))],
        child: const MaterialApp(home: Scaffold(body: ProfileScreen()))));
    await tester.pumpAndSettle();
    expect(find.text('UID: ยังไม่พร้อมใช้งาน'), findsOneWidget);
    expect(find.byTooltip('คัดลอก UID'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('compact phone supports sheet and menu without overflow',
      (tester) async {
    await home(tester, size: const Size(320, 568));
    await tester.tap(find.byKey(const Key('home-sheet-handle')));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('เมนู'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
