import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
// ignore: implementation_imports
import 'package:google_fonts/src/google_fonts_base.dart' as fonts;
import 'package:pacegasus/models/training_date.dart';
import 'package:pacegasus/models/training_models.dart';
import 'package:pacegasus/providers/program_provider.dart';
import 'package:pacegasus/providers/training_plan_provider.dart';
import 'package:pacegasus/providers/wallet_provider.dart';
import 'package:pacegasus/providers/wellness_provider.dart';
import 'package:pacegasus/screens/home/home_screen.dart';
import 'package:pacegasus/screens/training/training_schedule_screen.dart';
import 'package:pacegasus/services/api_client.dart';
import 'package:pacegasus/services/onboarding_api.dart';
import 'package:pacegasus/services/program_api.dart';
import 'package:pacegasus/services/wellness_api.dart';
import 'package:pacegasus/widgets/common.dart';

class _Fonts extends Fake implements AssetManifest {
  @override
  List<String> listAssets() => [
        for (final family in ['Kanit', 'Sarabun'])
          for (final weight in ['Regular', 'Medium', 'SemiBold', 'Bold'])
            'test-fonts/$family-$weight.ttf',
      ];
}

class _Api extends ProgramApi {
  _Api() : super(ApiClient(baseUrl: 'http://localhost'));
  final refreshed = Completer<Map<String, dynamic>>();
  int reads = 0;
  int writes = 0;

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
    if (reads++ > 0) return refreshed.future;
    return {
      'data': {
        'userProgramId': 'plan-1',
        'templateLevel': 'beginner',
        'startDate': trainingDateKey(trainingToday()),
        'quests': [],
      },
    };
  }

  @override
  Future<Map<String, dynamic>> getQuestsInRange(
          {required String from, required String to}) async =>
      {
        'data': {'quests': []}
      };

  @override
  Future<Map<String, dynamic>> addQuestsBatch(
      List<Map<String, String>> quests) async {
    writes++;
    return {'data': {}};
  }
}

class _Onboarding extends OnboardingApi {
  _Onboarding() : super(ApiClient(baseUrl: 'http://localhost'));
  @override
  Future<Map<String, dynamic>> status() async => {'data': {}};
}

class _Wellness extends WellnessNotifier {
  _Wellness() : super(WellnessApi(ApiClient(baseUrl: 'http://localhost'))) {
    completedToday = true;
  }
  @override
  Future<bool> loadToday() async => true;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    GoogleFonts.config.allowRuntimeFetching = false;
    fonts.assetManifest = _Fonts();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMessageHandler('flutter/assets', (message) async {
      if (message != null &&
          utf8.decode(message.buffer.asUint8List()).startsWith('test-fonts/')) {
        return ByteData(0);
      }
      return null;
    });
  });

  for (final readFails in [false, true]) {
    testWidgets('saved week returns Home after refresh (readFails=$readFails)',
        (tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final api = _Api();
      final program = ProgramNotifier(api, _Onboarding());
      await program.restore();
      await tester.pumpWidget(ProviderScope(
        overrides: [
          programProvider.overrideWith((ref) => program),
          wellnessProvider.overrideWith((ref) => _Wellness()),
          walletProvider.overrideWith((ref) async => 42),
        ],
        child: MaterialApp(
          theme: ThemeData.dark(),
          home: const TrainingScheduleScreen(),
        ),
      ));
      await tester.pumpAndSettle();
      final container = ProviderScope.containerOf(
          tester.element(find.byType(TrainingScheduleScreen)));
      final plan = container.read(trainingPlanProvider);
      for (final day in [0, 1, 2]) {
        if (plan.selectedType != SessionType.easy) {
          plan.selectType(SessionType.easy);
        }
        expect(plan.handleDayTap(day), isNull);
      }
      plan.selectType(SessionType.long);
      expect(plan.handleDayTap(4), isNull);
      expect(plan.isWeekComplete(0), isTrue);
      await tester.pumpAndSettle();
      final save = find.widgetWithText(GradientButton, 'บันทึกตารางสัปดาห์');
      await tester.ensureVisible(save);
      final saveElement = tester.element(save);
      await tester.tap(save);
      await tester.pump(const Duration(milliseconds: 100));
      expect(api.writes, 1);
      expect(program.isLoading, isTrue);
      // The submit callback must keep its context during this delayed read.
      expect(saveElement.mounted, isTrue);
      if (readFails) {
        api.refreshed.completeError(ApiException(503, 'read unavailable'));
      } else {
        // Legacy APIs omit scheduleSaved even though the quest was saved.
        api.refreshed.complete({
          'data': {
            'userProgramId': 'plan-1',
            'quests': [
              {
                'scheduled_date': trainingDateKey(trainingToday()),
                'session_type': 'easy',
                'planned_value': 5,
                'unit': 'km',
                'status': 'pending',
              },
            ],
          },
        });
      }
      await tester.pumpAndSettle();
      expect(find.byType(TrainingScheduleScreen), findsNothing);
      expect(find.byType(HomeScreen), findsOneWidget);
      expect(find.text('เริ่มวิ่ง'), findsOneWidget);
      expect(program.isScheduleSaved, isTrue);
      expect(api.writes, 1);
      expect(tester.takeException(), isNull);
    }, variant: TargetPlatformVariant({TargetPlatform.windows}));
  }
}
