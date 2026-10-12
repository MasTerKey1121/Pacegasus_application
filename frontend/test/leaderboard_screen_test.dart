import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
// ignore: implementation_imports
import 'package:google_fonts/src/google_fonts_base.dart' as fonts;
import 'package:pacegasus/services/api_client.dart';
import 'package:pacegasus/services/leaderboard_api.dart';
import 'package:pacegasus/screens/leaderboard/leaderboard_screen.dart';

class _Fonts extends Fake implements AssetManifest {
  @override
  List<String> listAssets() => [
        for (final family in ['Kanit', 'Sarabun'])
          for (final weight in ['Regular', 'Medium', 'SemiBold', 'Bold'])
            'test-fonts/$family-$weight.ttf'
      ];
}

class _Client extends ApiClient {
  int? rank = 18;
  bool fail = false;
  final calls = <String>[];
  @override
  Future<Map<String, dynamic>> get(String path, {bool auth = false}) async {
    expect(auth, isTrue);
    calls.add(path);
    if (fail) throw ApiException(503, 'โหลดอันดับไม่สำเร็จ');
    return {
      'data': {
        'entries': [
          for (var i = 1; i <= 50; i++)
            {
              'id': 'player-$i',
              'name': 'Runner $i',
              'rank': i,
              'distanceKm': 101 - i
            }
        ],
        'myEntry': {
          'id': 'player-18',
          'name': 'Me',
          'rank': rank,
          'distanceKm': rank == null ? 0.0 : 83.0
        },
        'period': {
          'startsAt': '2026-09-27T17:00:00Z',
          'endsAt': '2026-10-04T17:00:00Z'
        },
      }
    };
  }
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
  Future<void> open(WidgetTester tester, _Client client) async {
    tester.view.physicalSize = const Size(320, 750);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(ProviderScope(
        overrides: [
          leaderboardApiProvider.overrideWithValue(LeaderboardApi(client))
        ],
        child: MaterialApp(
            theme: ThemeData.dark(), home: const LeaderboardScreen())));
    await tester.pumpAndSettle();
  }

  testWidgets('personal rank stays visible while list scrolls to rank 50',
      (tester) async {
    await open(tester, _Client());
    final pinned = find.byKey(const Key('my-ranking'));
    final position = tester.getTopLeft(pinned);
    expect(
        find.descendant(of: pinned, matching: find.text('18')), findsOneWidget);
    await tester.dragUntilVisible(
        find.text('Runner 50'), find.byType(ListView), const Offset(0, -350));
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(pinned), position);
    expect(find.text('Runner 50'), findsOneWidget);
    expect(find.text('Runner 51'), findsNothing);
    expect(tester.takeException(), isNull);
  });
  testWidgets('unranked player shows no rank and guild selector reloads API',
      (tester) async {
    final client = _Client()..rank = null;
    await open(tester, client);
    expect(
        find.descendant(
            of: find.byKey(const Key('my-ranking')),
            matching: find.text('ไม่มีอันดับ')),
        findsOneWidget);
    await tester.tap(find.byType(DropdownButton<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('กิลด์').last);
    await tester.pumpAndSettle();
    expect(client.calls.last, '/api/leaderboard?scope=guild');
    expect(find.text('อันดับกิลด์ของคุณ'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets('API failure is distinct from no rank and retry restores data',
      (tester) async {
    final client = _Client()..fail = true;
    await open(tester, client);
    expect(find.text('ไม่มีอันดับ'), findsNothing);
    client.fail = false;
    await tester.tap(find.text('ลองอีกครั้ง'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('my-ranking')), findsOneWidget);
  });
}
