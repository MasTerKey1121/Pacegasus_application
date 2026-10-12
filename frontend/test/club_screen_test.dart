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
  bool hasClub = false;
  bool failMine = false;
  final calls = <String>[];
  String role = 'member';
  bool failPatch = false;
  final clubChanges = <String, dynamic>{};
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
    if (path == '/api/clubs/me') {
      if (failMine) throw ApiException(503, 'โหลดคลับของฉันไม่สำเร็จ');
      return {
        'data': hasClub
            ? {
                'club': {'id': 'club-1', 'name': 'Test Club'}
              }
            : null,
      };
    }
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
          'maxMembers': 50,
          ...clubChanges
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
    calls.add(path);
    if (path.endsWith('/leave')) {
      hasClub = false;
      return {'data': <String, dynamic>{}};
    }
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
    if (failPatch) throw ApiException(503, 'บันทึกไม่สำเร็จ');
    saved = body;
    if (path == '/api/clubs/club-1') clubChanges.addAll(body ?? {});
    return {'data': <String, dynamic>{}};
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

  testWidgets('existing members go directly to their club without discovery',
      (tester) async {
    final client = _Client()..hasClub = true;
    await open(tester, client, const ClubScreen());
    expect(find.byType(ClubDetailScreen), findsOneWidget);
    expect(find.text('Test Club'), findsOneWidget);
    expect(find.text('ค้นพบคลับ'), findsNothing);
    expect(find.text('ค้นหาชื่อคลับ'), findsNothing);
    expect(client.calls, contains('/api/clubs/club-1'));
    expect(
        client.calls.where((path) => path.startsWith('/api/clubs?')), isEmpty);
    expect(tester.takeException(), isNull);
  });
  testWidgets('back from own club returns to the previous page',
      (tester) async {
    final client = _Client()..hasClub = true;
    await open(
        tester,
        client,
        Builder(
            builder: (context) => Scaffold(
                  body: TextButton(
                    onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                            builder: (_) => const ClubScreen())),
                    child: const Text('เปิด Club'),
                  ),
                )));
    await tester.tap(find.text('เปิด Club'));
    await tester.pumpAndSettle();
    expect(find.byType(ClubDetailScreen), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('เปิด Club'), findsOneWidget);
    expect(find.byType(ClubScreen), findsNothing);
    expect(tester.takeException(), isNull);
  });
  testWidgets('membership lookup failure retries instead of opening a club',
      (tester) async {
    final client = _Client()
      ..hasClub = true
      ..failMine = true;
    await open(tester, client, const ClubScreen());
    expect(find.text('โหลดคลับของฉันไม่สำเร็จ'), findsOneWidget);
    expect(find.text('สร้างคลับ'), findsNothing);
    expect(find.byType(ClubDetailScreen), findsNothing);
    client.failMine = false;
    await tester.ensureVisible(find.text('ลองอีกครั้ง'));
    await tester.tap(find.text('ลองอีกครั้ง'));
    await tester.pumpAndSettle();
    expect(find.byType(ClubDetailScreen), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
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
    expect(find.text('คำขอสมัคร'), findsNothing);
    expect(find.text('บทบาทและสิทธิ์'), findsNothing);
    expect(find.text('ยุบคลับ'), findsNothing);
    client.role = 'leader';
    await tester.pumpWidget(const SizedBox());
    await open(tester, client, const ClubManageScreen(clubId: 'club-1'));
    expect(find.text('คำขอสมัคร'), findsOneWidget);
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
  testWidgets(
      'member management is an inline menu with confirmation; cancel never leaves',
      (tester) async {
    final client = _Client()..hasClub = true;
    await open(tester, client, const ClubDetailScreen(clubId: 'club-1'));
    expect(find.byTooltip('แก้ไขชื่อคลับ'), findsNothing);
    await tester.tap(find.text('จัดการคลับ'));
    await tester.pumpAndSettle();
    expect(find.text('คำขอสมัคร'), findsNothing);
    expect(find.text('บทบาทและสิทธิ์'), findsNothing);
    await tester.tap(find.text('ออกจากคลับ'));
    await tester.pumpAndSettle();
    expect(find.text('ยืนยันออกจากคลับ'), findsOneWidget);
    await tester.tap(find.text('ยกเลิก'));
    await tester.pumpAndSettle();
    expect(client.calls.any((path) => path.endsWith('/leave')), isFalse);
    await tester.tap(find.text('จัดการคลับ'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('ออกจากคลับ'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'ออกจากคลับ'));
    await tester.pumpAndSettle();
    expect(client.calls.where((path) => path.endsWith('/leave')).length, 1);
    expect(find.text('ค้นพบคลับ'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
      'leader has three edit controls and exactly the approved management actions; leaving is blocked',
      (tester) async {
    final client = _Client()..role = 'leader';
    await open(tester, client, const ClubDetailScreen(clubId: 'club-1'));
    expect(find.byTooltip('แก้ไขตราคลับ'), findsOneWidget);
    expect(find.byTooltip('แก้ไขชื่อคลับ'), findsOneWidget);
    expect(find.byTooltip('แก้ไขคำขวัญคลับ'), findsOneWidget);
    await tester.tap(find.text('จัดการคลับ'));
    await tester.pumpAndSettle();
    expect(find.text('คำขอสมัคร'), findsOneWidget);
    expect(find.text('บทบาทและสิทธิ์'), findsOneWidget);
    expect(find.text('ยุบคลับ'), findsNothing);
    expect(find.text('เชิญสมาชิกด้วย UID'), findsNothing);
    await tester.tap(find.text('ออกจากคลับ'));
    await tester.pumpAndSettle();
    expect(find.text('โอนสิทธิ์หัวหน้าก่อน'), findsOneWidget);
    await tester.tap(find.text('รับทราบ'));
    await tester.pumpAndSettle();
    expect(client.calls.any((path) => path.endsWith('/leave')), isFalse);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
      'leader edits only the selected field; failure keeps the dialog for retry',
      (tester) async {
    final client = _Client()
      ..role = 'leader'
      ..failPatch = true;
    await open(tester, client, const ClubDetailScreen(clubId: 'club-1'));
    await tester.tap(find.byTooltip('แก้ไขชื่อคลับ'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField), 'New Club');
    await tester.tap(find.text('บันทึก'));
    await tester.pumpAndSettle();
    expect(find.text('บันทึกไม่สำเร็จ'), findsOneWidget);
    client.failPatch = false;
    await tester.tap(find.text('บันทึก'));
    await tester.pump();
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    expect(client.saved, {'name': 'New Club'});
    expect(find.text('New Club'), findsOneWidget);
    await tester.ensureVisible(find.byTooltip('แก้ไขคำขวัญคลับ'));
    await tester.tap(find.byTooltip('แก้ไขคำขวัญคลับ'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField), 'วิ่งไปด้วยกัน');
    await tester.tap(find.text('บันทึก'));
    await tester.pumpAndSettle();
    expect(client.saved, {'description': 'วิ่งไปด้วยกัน'});
    expect(find.text('วิ่งไปด้วยกัน'), findsOneWidget);
    await tester.ensureVisible(find.byTooltip('แก้ไขตราคลับ'));
    await tester.tap(find.byTooltip('แก้ไขตราคลับ'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('บันทึก'));
    await tester.pumpAndSettle();
    expect(client.saved, {'imageUrl': null});
    expect(tester.takeException(), isNull);
  });
}
