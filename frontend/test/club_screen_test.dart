import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
// ignore: implementation_imports
import 'package:google_fonts/src/google_fonts_base.dart' as fonts;
import 'package:pacegasus/services/api_client.dart';
import 'package:pacegasus/services/club_api.dart';
import 'package:pacegasus/screens/club/club_screen.dart';

class _Fonts extends Fake implements AssetManifest {
  @override
  List<String> listAssets() => [
        for (final family in ['Kanit', 'Sarabun'])
          for (final weight in ['Regular', 'Medium', 'SemiBold', 'Bold'])
            'test-fonts/$family-$weight.ttf'
      ];
}

class _Client extends ApiClient {
  Map<String, dynamic>? saved;
  bool failSave = true;
  final calls = <String>[];
  String role = 'member';
  @override
  Future<Map<String, dynamic>> get(String path, {bool auth = false}) async {
    expect(auth, isTrue);
    calls.add(path);
    if (path.contains('join-requests')) {
      return {
        'data': {
          'requests': [
            {
              'requestId': 'request-1',
              'club': {'name': 'Test Club'},
              'message': '',
            }
          ]
        }
      };
    }
    if (path == '/api/clubs/me') return {'data': null};
    if (path.startsWith('/api/clubs?')) {
      return {
        'data': {'clubs': [], 'total': 0}
      };
    }
    return {
      'data': {
        'club': {
          'id': 'club-1',
          'name': 'Test Club',
          'description': '',
          'imageUrl': null,
          'memberCount': 1,
          'maxMembers': 50
        },
        'myMembership': {
          'role': role,
          'permissions': {
            'canApproveRequests': role == 'leader',
            'canInvite': role == 'leader',
            'canKick': role == 'leader',
            'canEditInfo': role == 'leader'
          }
        },
        'members': [],
        'myPendingRequest': null,
      }
    };
  }

  @override
  Future<Map<String, dynamic>> post(String path,
      {Map<String, dynamic>? body, bool auth = false}) async {
    expect(auth, isTrue);
    saved = body;
    if (failSave) throw ApiException(409, 'ชื่อคลับนี้ถูกใช้แล้ว');
    return {
      'data': {'id': 'club-1'}
    };
  }

  @override
  Future<Map<String, dynamic>> patch(String path,
      {Map<String, dynamic>? body, bool auth = false}) async {
    expect(auth, isTrue);
    calls.add(path);
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
  Future<void> open(WidgetTester tester, _Client client, Widget page) async {
    tester.view.physicalSize = const Size(320, 750);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(ProviderScope(
        overrides: [clubApiProvider.overrideWithValue(ClubApi(client))],
        child: MaterialApp(theme: ThemeData.dark(), home: page)));
    await tester.pumpAndSettle();
  }

  testWidgets(
      'discovery omits marked sections and create errors preserve form for retry',
      (tester) async {
    final client = _Client();
    await open(tester, client, const ClubScreen());
    expect(find.text('ใกล้ฉัน'), findsNothing);
    expect(find.byType(SegmentedButton<String>), findsNothing);
    await tester.tap(find.text('สร้างคลับ'));
    await tester.pumpAndSettle();
    expect(find.text('พื้นที่'), findsNothing);
    await tester.enterText(find.byType(TextFormField).first, 'My Runners');
    await tester.ensureVisible(find.byType(FilledButton));
    await tester.tap(find.byType(FilledButton));
    await tester.pumpAndSettle();
    expect(find.text('ชื่อคลับนี้ถูกใช้แล้ว'), findsOneWidget);
    expect(client.saved!['name'], 'My Runners');
    expect(client.saved!.containsKey('location'), isFalse);
    client.failSave = false;
    await tester.ensureVisible(find.byType(FilledButton));
    await tester.tap(find.byType(FilledButton));
    await tester.pumpAndSettle();
    expect(find.byType(ClubFormScreen), findsNothing);
    expect(tester.takeException(), isNull);
  });
  testWidgets('management actions are based on membership permissions',
      (tester) async {
    final client = _Client();
    await open(tester, client, const ClubManageScreen(clubId: 'club-1'));
    expect(find.text('คำขอเข้าร่วม'), findsNothing);
    expect(find.text('บทบาทและสิทธิ์'), findsNothing);
    expect(find.text('ยุบคลับ'), findsNothing);
    client.role = 'leader';
    await tester.pumpWidget(const SizedBox());
    await open(tester, client, const ClubManageScreen(clubId: 'club-1'));
    expect(find.text('คำขอเข้าร่วม'), findsOneWidget);
    expect(find.text('บทบาทและสิทธิ์'), findsOneWidget);
    expect(find.text('โอนหัวหน้าคลับ'), findsNothing);
    expect(find.text('จัดการกิจกรรม'), findsNothing);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
      'accepting own invite calls accept endpoint instead of approval endpoint',
      (tester) async {
    final client = _Client();
    await open(tester, client, const ClubRequestsScreen());
    await tester.tap(find.text('ตอบรับ'));
    await tester.pumpAndSettle();
    expect(
        client.calls, contains('/api/clubs/me/join-requests/request-1/accept'));
    expect(tester.takeException(), isNull);
  });
}
