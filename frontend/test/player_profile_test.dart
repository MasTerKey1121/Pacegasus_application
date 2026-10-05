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
  int kicks = 0, sends = 0;
  String role = 'member', relationship = 'none';
  @override
  Future<Map<String, dynamic>> get(String path, {bool auth = false}) async {
    expect(auth, true);
    return {
      'data': {
        'user': {
          'id': 'target',
          'uid': 'ABCDE23456',
          'displayName': 'Runner',
          'level': 3,
          'avatarUrl': null
        },
        'relationship': {'status': relationship, 'direction': 'outgoing'},
        'club': kicked ? null : {'id': 'club', 'name': 'Club', 'role': role},
        'canManageMember': leader && !kicked,
        'avatar': {'equipment': []},
        'distanceKm': 42.5,
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
            home: const Scaffold(
                body: PlayerProfileDialog(identifier: 'ABCDE23456')))));
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
