import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
// ignore: implementation_imports
import 'package:google_fonts/src/google_fonts_base.dart' as fonts;
import 'package:pacegasus/models/run_result.dart';
import 'package:pacegasus/providers/run_provider.dart';
import 'package:pacegasus/providers/run_setup_provider.dart';
import 'package:pacegasus/screens/run/run_summary_screen.dart';
import 'package:pacegasus/services/api_client.dart';
import 'package:pacegasus/services/quest_api.dart';
import 'package:pacegasus/services/running_session_api.dart';
import 'package:pacegasus/widgets/run_route_map.dart';

class _Fonts extends Fake implements AssetManifest {
  @override
  List<String> listAssets() => [
        for (final family in ['Kanit', 'Sarabun'])
          for (final weight in ['Regular', 'Medium', 'SemiBold', 'Bold'])
            'test-fonts/$family-$weight.ttf'
      ];
}

class _Sessions extends RunningSessionApi {
  _Sessions() : super(ApiClient());
  bool fail = false;
  String? fetchedId;
  Map<String, dynamic> data = {
    'distance_km': '2.5',
    'duration_seconds': 900,
    'environment': 'park',
    'route_points': [
      {'lat': 13.75, 'lng': 100.5},
      {'lat': 13.76, 'lng': 100.51}
    ]
  };
  @override
  Future<Map<String, dynamic>> getDetail({required String sessionId}) async {
    fetchedId = sessionId;
    if (fail) throw ApiException(503, 'Offline');
    return {'data': data};
  }

  @override
  Future<Map<String, dynamic>> complete(
          {required String sessionId,
          required double distanceKm,
          required int durationSeconds,
          required double endLat,
          required double endLng,
          List<Map<String, double>> routePoints = const []}) async =>
      {'data': {}};
}

void main() {
  setUp(() {
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
  RunResult snapshot({List<RunRoutePoint> points = const []}) => RunResult(
      distanceKm: 1,
      duration: const Duration(minutes: 5),
      avgPace: '5:00',
      calories: 62,
      routePoints: points);

  Future<void> open(WidgetTester tester, _Sessions api,
      {RunResult? result, String environment = 'park'}) async {
    tester.view.physicalSize = const Size(320, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final setup = RunSetupNotifier(QuestApi(ApiClient()), api)
      ..sessionId = 'just-ended-session'
      ..environment = environment;
    await tester.pumpWidget(ProviderScope(
        overrides: [
          runningSessionApiProvider.overrideWithValue(api),
          runSetupProvider.overrideWith((ref) => setup)
        ],
        child: MaterialApp(
            theme: ThemeData.dark(),
            home: RunSummaryScreen(result: result ?? snapshot()))));
    await tester.pumpAndSettle();
  }

  test('stop preserves recorded GPS coordinates in the result', () async {
    final run = RunSessionNotifier(_Sessions());
    addTearDown(run.dispose);
    final result =
        await run.stop(sessionId: 'run', sideQuests: [], routePoints: [
      {'lat': 13.7, 'lng': 100.5},
      {'lat': 13.8, 'lng': 100.6}
    ]);
    expect(result!.routePoints.length, 2);
    expect(result.routePoints.last.longitude, 100.6);
    expect(
        RunRoutePoint.parse([
          {'lat': 'NaN', 'lng': 100},
          {'lat': 91, 'lng': 100},
          {'lat': '13.7', 'lng': '100.5'}
        ]).length,
        1);
  });
  testWidgets(
      'summary map uses the just-ended session and accepts snake-case coordinates',
      (tester) async {
    final api = _Sessions();
    await open(tester, api);
    expect(api.fetchedId, 'just-ended-session');
    final map = tester.widget<RunRouteMap>(find.byType(RunRouteMap));
    expect(map.points.length, 2);
    expect(map.points.first.latitude, 13.75);
    expect(find.text('วิ่งเสร็จแล้ว!'), findsNothing);
    expect(find.text('2.50'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
      'injury choices start neutral and only the chosen option turns blue',
      (tester) async {
    await open(tester, _Sessions());
    Finder button(String label) => find.ancestor(
        of: find.text(label), matching: find.byType(OutlinedButton));
    Color? background(String label) => tester
        .widget<OutlinedButton>(button(label))
        .style!
        .backgroundColor!
        .resolve({});
    await tester.ensureVisible(button('ไม่มี'));
    await tester.pumpAndSettle();
    final neutral = background('ไม่มี');
    expect(background('มีอาการ'), neutral);
    await tester.tap(button('ไม่มี'));
    await tester.pumpAndSettle();
    expect(background('ไม่มี'), const Color(0xFF268DDB));
    expect(background('มีอาการ'), neutral);
    await tester.tap(button('มีอาการ'));
    await tester.pumpAndSettle();
    expect(background('มีอาการ'), const Color(0xFF268DDB));
    expect(background('ไม่มี'), neutral);
    expect(find.byType(TextField), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
      'detail failure preserves the GPS snapshot; absent GPS has an honest empty state',
      (tester) async {
    final api = _Sessions()..fail = true;
    await open(tester, api,
        result: snapshot(points: const [RunRoutePoint(13.5, 100.2)]));
    expect(
        tester
            .widget<RunRouteMap>(find.byType(RunRouteMap))
            .points
            .single
            .latitude,
        13.5);
    expect(find.text('ไม่มีข้อมูลเส้นทาง GPS สำหรับการวิ่งนี้'), findsNothing);
    await tester.pumpWidget(const SizedBox());
    api.fail = false;
    api.data = {'routePoints': [], 'environment': 'park'};
    await open(tester, api);
    expect(
        find.text('ไม่มีข้อมูลเส้นทาง GPS สำหรับการวิ่งนี้'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets('treadmill has no fabricated map', (tester) async {
    final api = _Sessions()
      ..data = {'environment': 'treadmill', 'route_points': []};
    await open(tester, api, environment: 'treadmill');
    expect(find.text('วิ่งบนลู่วิ่ง • ไม่มีเส้นทาง GPS'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
