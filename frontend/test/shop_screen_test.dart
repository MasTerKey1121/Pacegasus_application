import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
// ignore: implementation_imports
import 'package:google_fonts/src/google_fonts_base.dart' as fonts;
import 'package:pacegasus/services/api_client.dart';
import 'package:pacegasus/services/shop_api.dart';
import 'package:pacegasus/screens/shop/shop_screen.dart';

class _Fonts extends Fake implements AssetManifest {
  @override
  List<String> listAssets() => [
        for (final family in ['Kanit', 'Sarabun'])
          for (final weight in ['Regular', 'Medium', 'SemiBold', 'Bold'])
            'test-fonts/$family-$weight.ttf'
      ];
}

class _Client extends ApiClient {
  final calls = <Uri>[];
  bool fail = false;
  bool populated = false;
  @override
  Future<Map<String, dynamic>> get(String path, {bool auth = false}) async {
    expect(auth, isTrue);
    calls.add(Uri.parse(path));
    if (fail) throw ApiException(503, 'เซิร์ฟเวอร์ไม่พร้อม');
    if (path.contains('/progress')) {
      return {
        'data': {'coinBalance': 42}
      };
    }
    final offset = int.parse(Uri.parse(path).queryParameters['offset'] ?? '0');
    return {
      'data': {
        'items': populated
            ? [
                {
                  'listingId': 'item-$offset',
                  'priceCoins': 50 + offset,
                  'owned': false,
                  'item': {
                    'name': 'Test item $offset',
                    'rarity': 'rare',
                    'thumbnailUrl': '',
                    'description': ''
                  },
                }
              ]
            : [],
        'total': populated ? 2 : 0
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
  Future<void> open(WidgetTester tester, _Client client, Widget screen) async {
    tester.view.physicalSize = const Size(320, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(ProviderScope(
        overrides: [shopApiProvider.overrideWithValue(ShopApi(client))],
        child: MaterialApp(theme: ThemeData.dark(), home: screen)));
    await tester.pumpAndSettle();
  }

  testWidgets('shop shows real balance, empty category and see-all navigation',
      (tester) async {
    final client = _Client();
    await open(tester, client, const ShopScreen());
    expect(find.text('42'), findsOneWidget);
    expect(find.text('ยังไม่มีสินค้าในหมวดนี้'), findsWidgets);
    await tester.tap(find.text('ดูทั้งหมด ›').first);
    await tester.pumpAndSettle();
    expect(find.byType(ShopCategoryScreen), findsOneWidget);
    expect(client.calls.last.queryParameters['slot'], 'hair');
    expect(tester.takeException(), isNull);
  });
  testWidgets(
      'price and rarity selections issue server queries with reset offset',
      (tester) async {
    final client = _Client();
    await open(tester, client, const ShopCategoryScreen(categoryIndex: 3));
    await tester.tap(find.byType(DropdownButtonFormField<String>).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('ความหายาก: สูง → ต่ำ').last);
    await tester.pumpAndSettle();
    expect(client.calls.last.queryParameters['sort'], 'rarity_desc');
    expect(client.calls.last.queryParameters['slot'], 'inner_top,outer_top');
    expect(client.calls.last.queryParameters['offset'], '0');
    await tester.tap(find.byType(DropdownButtonFormField<String>).last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('ตำนาน').last);
    await tester.pumpAndSettle();
    expect(client.calls.last.queryParameters['rarity'], 'legendary');
    expect(tester.takeException(), isNull);
  });
  testWidgets('pagination appends items and changing sort resets the page',
      (tester) async {
    final client = _Client()..populated = true;
    await open(tester, client, const ShopCategoryScreen(categoryIndex: 0));
    await tester.ensureVisible(find.text('โหลดเพิ่มเติม'));
    await tester.tap(find.text('โหลดเพิ่มเติม'));
    await tester.pumpAndSettle();
    expect(client.calls.last.queryParameters['offset'], '1');
    expect(find.text('Test item 1'), findsOneWidget);
    await tester.tap(find.byType(DropdownButtonFormField<String>).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('ราคา: ต่ำ → สูง').last);
    await tester.pumpAndSettle();
    expect(client.calls.last.queryParameters['offset'], '0');
    expect(client.calls.last.queryParameters['sort'], 'price_asc');
    expect(find.text('Test item 1'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('failed catalog is not an empty catalog and retry works',
      (tester) async {
    final client = _Client()..fail = true;
    await open(tester, client, const ShopCategoryScreen(categoryIndex: 0));
    expect(find.text('เซิร์ฟเวอร์ไม่พร้อม'), findsOneWidget);
    client.fail = false;
    await tester.tap(find.text('ลองอีกครั้ง'));
    await tester.pumpAndSettle();
    expect(find.text('ไม่พบสินค้าที่ตรงกับตัวกรอง'), findsOneWidget);
  });
}
