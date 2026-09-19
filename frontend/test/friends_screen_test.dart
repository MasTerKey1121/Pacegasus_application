import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
// ignore: implementation_imports
import 'package:google_fonts/src/google_fonts_base.dart' as fonts;
import 'package:pacegasus/screens/friends/friends_screen.dart';
import 'package:pacegasus/services/api_client.dart';
import 'package:pacegasus/services/friend_api.dart';

class _Fonts extends Fake implements AssetManifest {
  @override
  List<String> listAssets() => [
        for (final family in ['Kanit', 'Sarabun'])
          for (final weight in ['Regular', 'Medium', 'SemiBold', 'Bold'])
            'test-fonts/$family-$weight.ttf',
      ];
}

class _Api extends FriendApi {
  _Api() : super(ApiClient(baseUrl: 'http://localhost'));
  List<FriendEntry> friends = [];
  List<FriendEntry> requests = [];
  bool fail = false;
  String? sent;
  @override
  Future<List<FriendEntry>> list({String? direction}) async {
    if (fail) throw ApiException(503, 'ลองใหม่ภายหลัง');
    return direction == null ? friends : requests;
  }

  @override
  Future<bool> send(String uid) async {
    sent = uid;
    return false;
  }

  @override
  Future<void> accept(String id) async {
    friends = [...requests];
    requests = [];
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

  Future<void> open(WidgetTester tester, _Api api) async {
    tester.view.physicalSize = const Size(320, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(ProviderScope(
        overrides: [friendApiProvider.overrideWithValue(api)],
        child:
            MaterialApp(theme: ThemeData.dark(), home: const FriendsScreen())));
    await tester.pumpAndSettle();
  }

  testWidgets('empty list, UID validation, send and disabled QR on small phone',
      (tester) async {
    final api = _Api();
    await open(tester, api);
    expect(find.text('ยังไม่มีเพื่อน'), findsOneWidget);
    await tester.tap(find.byKey(const Key('add-friend')));
    await tester.pumpAndSettle();
    expect(tester.widget<OutlinedButton>(find.byType(OutlinedButton)).onPressed,
        isNull);
    await tester.tap(find.text('ส่งคำขอเป็นเพื่อน'));
    await tester.pumpAndSettle();
    expect(api.sent, isNull);
    expect(find.textContaining('กรอก UID 10 ตัว'), findsOneWidget);
    await tester.enterText(find.byKey(const Key('friend-uid')), 'ABCDE23456');
    await tester.tap(find.text('ส่งคำขอเป็นเพื่อน'));
    await tester.pumpAndSettle();
    expect(api.sent, 'ABCDE23456');
    expect(find.text('ส่งคำขอแล้ว รอเพื่อนตอบรับ'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'search filters real results and accepting moves request to friends',
      (tester) async {
    final api = _Api()
      ..friends = [
        const FriendEntry(
            friendshipId: 'one', name: 'Alice', uid: 'ABCDE23456'),
        const FriendEntry(friendshipId: 'two', name: 'Bob', uid: 'ABCDE23457'),
      ];
    api.requests = [
      const FriendEntry(
          friendshipId: 'three', name: 'Charlie', uid: 'ABCDE23458')
    ];
    await open(tester, api);
    await tester.enterText(find.byType(TextField), 'ali');
    await tester.pumpAndSettle();
    expect(find.text('Alice'), findsOneWidget);
    expect(find.text('Bob'), findsNothing);
    await tester.ensureVisible(find.text('คำขอที่ได้รับ'));
    await tester.tap(find.text('คำขอที่ได้รับ'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('ตอบรับ'));
    await tester.pumpAndSettle();
    expect(find.text('ยังไม่มีคำขอ'), findsOneWidget);
    await tester.ensureVisible(find.text('เพื่อนของฉัน'));
    await tester.tap(find.text('เพื่อนของฉัน'));
    await tester.pumpAndSettle();
    expect(find.text('Charlie'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('network failure is distinct from an empty list and can retry',
      (tester) async {
    final api = _Api()..fail = true;
    await open(tester, api);
    expect(find.text('โหลดรายการไม่สำเร็จ'), findsOneWidget);
    expect(find.text('ยังไม่มีเพื่อน'), findsNothing);
    api.fail = false;
    await tester.tap(find.text('ลองอีกครั้ง'));
    await tester.pumpAndSettle();
    expect(find.text('ยังไม่มีเพื่อน'), findsOneWidget);
  });
}
