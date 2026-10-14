import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
// ignore: implementation_imports
import 'package:google_fonts/src/google_fonts_base.dart' as fonts;
import 'package:pacegasus/providers/auth_provider.dart';
import 'package:pacegasus/services/api_client.dart';
import 'package:pacegasus/widgets/player_profile_dialog.dart';

class _Fonts extends Fake implements AssetManifest {
  @override
  List<String> listAssets() => [
        for (final family in ['Kanit', 'Sarabun'])
          for (final weight in ['Regular', 'Medium', 'SemiBold', 'Bold'])
            'test-fonts/$family-$weight.ttf'
      ];
}

class _Client extends ApiClient {
  bool leader = true, kicked = false, failKick = false;
  bool failProfile = false, failLookup = false;
  final paths = <String>[];
  int kicks = 0, sends = 0;
  String role = 'member', relationship = 'none';
  @override
  Future<Map<String, dynamic>> get(String path, {bool auth = false}) async {
    expect(auth, true);
    paths.add(path);
    if (path == '/api/friends/lookup/ABCDE23456') {
      if (failLookup) throw ApiException(503, 'lookup unavailable');
      return {
        'data': {
          'relationship': {'status': relationship, 'direction': 'outgoing'}
        }
      };
    }
    if (path == '/api/clubs/me') {
      return {
        'data': leader
            ? {
                'club': {'id': 'club'}
              }
            : null
      };
    }
    if (path == '/api/clubs/club') {
      return {
        'data': {
          'myMembership': {'role': leader ? 'leader' : 'member'},
          'members': [
            {
              'user': {'id': 'target', 'uid': 'ABCDE23456'},
              'role': role
            }
          ]
        }
      };
    }
    expect(path, '/api/users/profile/ABCDE23456');
    if (failProfile) throw ApiException(404, 'ไม่พบผู้ใช้');
    return {
      'data': {
        'user': {
          'uid': 'ABCDE23456',
          'displayName': 'Runner',
          'level': 3,
          'avatarUrl': null
        },
        'relationship': relationship == 'accepted' ? 'friend' : 'none',
        'club': kicked ? null : {'id': 'club', 'name': 'Club', 'role': role},
        'avatar': {'equipment': []},
        'stats': {'totalDistanceKm': 42.5, 'totalRuns': 99},
      }
    };
  }

  @override
  Future<Map<String, dynamic>> post(String path,
      {Map<String, dynamic>? body, bool auth = false}) async {
    sends++;
    relationship = 'pending';
    return {
      'data': {'autoAccepted': false}
    };
  }

  @override
  Future<Map<String, dynamic>> patch(String path,
      {Map<String, dynamic>? body, bool auth = false}) async {
    expect(path, '/api/clubs/club/members/target/role');
    role = body!['role'] as String;
    return {'data': {}};
  }

  @override
  Future<Map<String, dynamic>> delete(String path,
      {Map<String, dynamic>? body, bool auth = false}) async {
    expect(path, '/api/clubs/club/members/target');
    kicks++;
    if (failKick) throw ApiException(403, 'ไม่มีสิทธิ์');
    kicked = true;
    return {'data': {}};
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
    tester.view.physicalSize = const Size(390, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(ProviderScope(
        overrides: [apiClientProvider.overrideWithValue(client)],
        child: MaterialApp(
            theme: ThemeData.dark(),
            home: Scaffold(
                body: PlayerProfileDialog(
                    identifier: 'ABCDE23456',
                    avatarRendererBuilder: (_) => const SizedBox())))));
    await tester.pumpAndSettle();
  }

  testWidgets(
      'ordinary viewer can send one request and has no leader controls or removed sections',
      (tester) async {
    final client = _Client()..leader = false;
    await open(tester, client);
    expect(find.text('จัดการสมาชิก'), findsNothing);
    expect(find.text('สัตว์เลี้ยง'), findsNothing);
    expect(find.text('จำนวนครั้งที่วิ่ง'), findsNothing);
    await tester.ensureVisible(find.text('เพิ่มเพื่อน'));
    await tester.tap(find.text('เพิ่มเพื่อน'));
    await tester.pumpAndSettle();
    expect(client.sends, 1);
    expect(find.text('ส่งคำขอแล้ว'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets('new API accepted friend status disables duplicate request',
      (tester) async {
    final client = _Client()
      ..relationship = 'accepted'
      ..leader = false;
    await open(tester, client);
    expect(find.text('42.5 กม.'), findsOneWidget);
    await tester.ensureVisible(find.text('เป็นเพื่อนแล้ว'));
    expect(
        tester
            .widget<FilledButton>(
                find.widgetWithText(FilledButton, 'เป็นเพื่อนแล้ว'))
            .onPressed,
        isNull);
    expect(client.paths, contains('/api/users/profile/ABCDE23456'));
    expect(client.paths, isNot(contains('/api/friends/lookup/ABCDE23456')));
    expect(client.sends, 0);
  });
  testWidgets(
      'profile failure retries correct endpoint; lookup failure preserves profile without enabling requests',
      (tester) async {
    final client = _Client()
      ..failProfile = true
      ..leader = false;
    await open(tester, client);
    expect(find.text('ไม่พบผู้ใช้'), findsOneWidget);
    client.failProfile = false;
    client.failLookup = true;
    await tester.tap(find.text('ลองอีกครั้ง'));
    await tester.pumpAndSettle();
    expect(find.text('Runner'), findsOneWidget);
    await tester.ensureVisible(find.text('ตรวจสอบเพื่อนไม่สำเร็จ'));
    expect(
        tester
            .widget<FilledButton>(
                find.widgetWithText(FilledButton, 'ตรวจสอบเพื่อนไม่สำเร็จ'))
            .onPressed,
        isNull);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
      'leader changes role, cancel does not kick and failed kick stays retryable',
      (tester) async {
    final client = _Client();
    await open(tester, client);
    await tester.ensureVisible(find.text('จัดการสมาชิก'));
    await tester.tap(find.text('จัดการสมาชิก'));
    await tester.pumpAndSettle();
    await tester.tap(find.byWidgetPredicate((widget) =>
        widget is CheckedPopupMenuItem<String> &&
        widget.value == 'sub_leader'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('ยืนยัน'));
    await tester.pumpAndSettle();
    expect(client.role, 'sub_leader');
    await tester.tap(find.text('นำออกจากคลับ'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('ยกเลิก'));
    await tester.pumpAndSettle();
    expect(client.kicks, 0);
    client.failKick = true;
    await tester.tap(find.text('นำออกจากคลับ'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('ยืนยัน'));
    await tester.pumpAndSettle();
    expect(find.text('ไม่มีสิทธิ์'), findsOneWidget);
    expect(find.text('จัดการสมาชิก'), findsOneWidget);
    client.failKick = false;
    await tester.tap(find.text('นำออกจากคลับ'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('ยืนยัน'));
    await tester.pumpAndSettle();
    expect(client.kicked, true);
    expect(find.text('จัดการสมาชิก'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
