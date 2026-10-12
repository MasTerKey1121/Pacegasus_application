import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
// ignore: implementation_imports
import 'package:google_fonts/src/google_fonts_base.dart' as fonts;
import 'package:pacegasus/models/training_date.dart';
import 'package:pacegasus/providers/auth_provider.dart';
import 'package:pacegasus/screens/stats/stats_screen.dart';
import 'package:pacegasus/services/api_client.dart';
import 'package:pacegasus/services/stats_api.dart';

Map<String, dynamic> row(String date,
        {String id = 'run',
        Object? km = '5',
        Object? seconds = '1800',
        String status = 'completed'}) =>
    {
      'id': id,
      'session_date': date,
      'status': status,
      'distance_km': km,
      'duration_seconds': seconds,
      'environment': 'treadmill',
      'rpe_logs': [
        {'rpeScore': 6, 'stressLevel': 3, 'hasPain': false, 'mood': 'good'}
      ],
    };

class _Fonts extends Fake implements AssetManifest {
  @override
  List<String> listAssets() => [
        for (final family in ['Kanit', 'Sarabun'])
          for (final weight in ['Regular', 'Medium', 'SemiBold', 'Bold'])
            'test-fonts/$family-$weight.ttf'
      ];
}

class _Client extends ApiClient {
  bool fail = false;
  final paths = <String>[];
  List<Map<String, dynamic>> rows = [];
  @override
  Future<Map<String, dynamic>> get(String path, {bool auth = false}) async {
    expect(auth, true);
    paths.add(path);
    if (fail) throw ApiException(503, 'ลองใหม่ภายหลัง');
    return path.contains('history')
        ? {
            'data': {'sessions': rows}
          }
        : {
            'data': {'route_points': []}
          };
  }
}

void main() {
  test('Thai day boundaries, weighted pace and incomplete measurements', () {
    final runs = [
      RunHistoryEntry(row('2026-10-02T17:00:00Z', km: '1', seconds: 600)),
      RunHistoryEntry(row('2026-10-09T09:00:00Z', km: '9', seconds: 2700)),
      RunHistoryEntry(row('2026-10-09', km: null, seconds: 100)),
      RunHistoryEntry(row('2026-10-02T16:59:59Z', km: '50')),
      RunHistoryEntry(row('2026-10-10', km: '50')),
    ];
    final stats = RunStats(runs, 7, DateTime(2026, 10, 9));
    expect(stats.runs.length, 3);
    expect(stats.distance, 10);
    expect(stats.seconds, 3400);
    expect(stats.pace, '5:30');
    expect(stats.longest, 9);
    expect(stats.averageRpe, 6);
    expect(formatPace(300, 0), '—');
    expect(formatRunTime(3661), '1:01:01');
    expect(RunStats([], null, DateTime(2026, 10, 9)).averageRpe, isNull);
  });
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
  Future<void> open(WidgetTester tester, _Client client) async {
    tester.view.physicalSize = const Size(320, 760);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(ProviderScope(
        overrides: [apiClientProvider.overrideWithValue(client)],
        child: MaterialApp(
            theme: ThemeData.dark(),
            home: const Scaffold(body: StatsScreen()))));
    await tester.pumpAndSettle();
  }

  testWidgets(
      'error retries, period filters real history and detail stays read only',
      (tester) async {
    final client = _Client()..fail = true;
    final today = trainingToday();
    client.rows = [
      row(today.toIso8601String()),
      row(today.subtract(const Duration(days: 8)).toIso8601String(),
          id: 'old', km: '8'),
      row(today.toIso8601String(), status: 'abandoned', km: '500')
    ];
    await open(tester, client);
    expect(find.text('โหลดสถิติไม่สำเร็จ'), findsOneWidget);
    client.fail = false;
    await tester.tap(find.text('ลองอีกครั้ง'));
    await tester.pumpAndSettle();
    expect(find.text('5.00 กม.'), findsWidgets);
    expect(find.text('1 ครั้ง'), findsOneWidget);
    await tester.tap(find.text('ทั้งหมด'));
    await tester.pumpAndSettle();
    expect(find.text('13.00 กม.'), findsOneWidget);
    await tester.tap(find.text('7 วัน'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('ประวัติการวิ่ง'), 200,
        scrollable: find.byType(Scrollable).first);
    final date = '${today.day}/${today.month}/${today.year + 543}';
    await tester.ensureVisible(find.text(date));
    await tester.tap(find.text(date));
    await tester.pumpAndSettle();
    expect(client.paths.last, '/api/running-sessions/run');
    expect(find.text('ความรู้สึกหลังวิ่ง'), findsOneWidget);
    expect(find.text('อาการบาดเจ็บ: ไม่มี'), findsOneWidget);
    expect(find.text('ส่งข้อมูล'), findsNothing);
    expect(tester.takeException(), isNull);
  });
  testWidgets('empty history shows truthful empty state', (tester) async {
    await open(tester, _Client());
    await tester.scrollUntilVisible(find.text('ยังไม่มีการวิ่งในช่วงนี้'), 200,
        scrollable: find.byType(Scrollable).first);
    expect(find.text('ยังไม่มีการวิ่งในช่วงนี้'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
