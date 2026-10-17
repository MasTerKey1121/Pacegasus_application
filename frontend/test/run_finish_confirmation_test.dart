import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
// ignore: implementation_imports
import 'package:google_fonts/src/google_fonts_base.dart' as fonts;
import 'package:pacegasus/models/run_result.dart';
import 'package:pacegasus/models/side_quest.dart';
import 'package:pacegasus/providers/run_provider.dart';
import 'package:pacegasus/providers/run_setup_provider.dart';
import 'package:pacegasus/screens/run/run_session_screen.dart';
import 'package:pacegasus/services/api_client.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:pacegasus/providers/auth_provider.dart';
import 'run_quest_regression_test.dart' show TestAuth;
import 'package:pacegasus/services/quest_api.dart';
import 'package:pacegasus/services/running_session_api.dart';

class _Fonts extends Fake implements AssetManifest {
  @override
  List<String> listAssets() => [
        for (final family in ['Kanit', 'Sarabun'])
          for (final weight in ['Regular', 'Medium', 'SemiBold', 'Bold'])
            'test-fonts/$family-$weight.ttf'
      ];
}

class _Run extends RunSessionNotifier {
  _Run() : super(RunningSessionApi(ApiClient(baseUrl: 'http://localhost'))) {
    isRunning = true;
  }
  int stops = 0;
  @override
  Future<RunResult?> stop(
      {required String sessionId,
      required List<ActiveSideQuest> sideQuests,
      double? endLat,
      double? endLng,
      List<Map<String, double>> routePoints = const []}) async {
    expect(sessionId, 'run');
    stops++;
    return null;
  }
}

void main() {
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
  Future<void> open(WidgetTester tester, _Run run) async {
    tester.view.physicalSize = const Size(390, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final client = ApiClient(baseUrl: 'http://localhost');
    final setup = RunSetupNotifier(QuestApi(client), RunningSessionApi(client))
      ..environment = 'treadmill'
      ..sessionId = 'run';
    await tester.pumpWidget(ProviderScope(
        overrides: [
          authProvider.overrideWith((ref) => TestAuth(client)..signIn('a')),
          runProvider.overrideWith((ref) => run),
          runSetupProvider.overrideWith((ref) => setup)
        ],
        child: MaterialApp(
            theme: ThemeData.dark(), home: const RunSessionScreen())));
    await tester.pumpAndSettle();
  }

  testWidgets(
      'finish requires confirmation, cancel keeps running and invalid distance does not finish',
      (tester) async {
    final run = _Run();
    await open(tester, run);
    await tester.tap(find.text('■ จบการวิ่ง'));
    await tester.pumpAndSettle();
    expect(find.text('ต้องการจบการวิ่งไหม?'), findsOneWidget);
    expect(run.stops, 0);
    await tester.tap(find.text('วิ่งต่อ'));
    await tester.pumpAndSettle();
    expect(run.isRunning, true);
    expect(run.stops, 0);
    await tester.tap(find.text('■ จบการวิ่ง'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField), '-1');
    await tester.tap(find.text('จบการวิ่ง'));
    await tester.pumpAndSettle();
    expect(find.text('กรุณากรอกระยะทางที่ถูกต้อง'), findsOneWidget);
    expect(run.stops, 0);
    await tester.enterText(find.byType(TextFormField), '2.5');
    await tester.tap(find.text('จบการวิ่ง'));
    await tester.pumpAndSettle();
    expect(run.stops, 1);
    expect(run.distanceKm, 2.5);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets(
      'back while running opens confirmation and never silently finishes',
      (tester) async {
    final run = _Run();
    await open(tester, run);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('ต้องการจบการวิ่งไหม?'), findsOneWidget);
    expect(run.stops, 0);
    await tester.tap(find.text('วิ่งต่อ'));
    await tester.pumpAndSettle();
    expect(find.byType(RunSessionScreen), findsOneWidget);
    expect(run.isRunning, true);
    await tester.pumpWidget(const SizedBox());
  });
}
