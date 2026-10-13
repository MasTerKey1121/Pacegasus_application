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
import 'package:pacegasus/screens/home/avatar_layout.dart';
import 'package:pacegasus/screens/home/home_avatar.dart';
import 'package:pacegasus/providers/avatar_provider.dart';

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
  bool starterShirts = false;
  Map<String, dynamic>? saved;
  bool saveFail = false;
  @override
  Future<Map<String, dynamic>> put(String path,
      {Map<String, dynamic>? body, bool auth = false}) async {
    expect(path, '/api/avatar/me');
    expect(auth, isTrue);
    if (saveFail) throw ApiException(503, 'บันทึกไม่ได้');
    saved = body;
    return {'data': {}};
  }

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
    if (path.contains('/inventory')) {
      final slot = Uri.parse(path).queryParameters['slot']!;
      if (starterShirts && slot == 'inner_top,outer_top') {
        return {
          'data': {
            'items': [
              for (final color in ['black', 'white'])
                {
                  'equipped':
                      saved == null ? color == 'black' : color == 'white',
                  'item': {
                    'id': color == 'white'
                        ? '10000000-0000-4000-8000-000000000004'
                        : '10000000-0000-4000-8000-000000000003',
                    'code': 'starter_tee_$color',
                    'slot': 'inner_top',
                    'name':
                        color == 'white' ? 'เสื้อวิ่งสีขาว' : 'เสื้อวิ่งสีดำ',
                    'rarity': 'common',
                    'thumbnailUrl':
                        'asset:assets/models/items/starter_tee_$color.png',
                    'renderData': {
                      'variant': color == 'white' ? 'starter_tee_white' : null
                    },
                  }
                }
            ],
            'total': 2
          }
        };
      }
      return {
        'data': {
          'items': populated && slot == 'hair'
              ? [
                  {
                    'equipped': false,
                    'item': {
                      'id': 'owned-hair',
                      'slot': 'hair',
                      'name': 'ผมของฉัน',
                      'rarity': 'rare',
                      'thumbnailUrl': ''
                    }
                  }
                ]
              : [],
          'total': populated && slot == 'hair' ? 1 : 0
        }
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
        overrides: [
          shopApiProvider.overrideWithValue(ShopApi(client)),
          avatarOutfitProvider
              .overrideWith((ref) async => const AvatarOutfit({}))
        ],
        child: MaterialApp(
            theme: ThemeData.dark(),
            home: screen is ShopScreen
                ? ShopScreen(
                    wardrobe: screen.wardrobe,
                    avatarRendererBuilder: (_) => const SizedBox())
                : screen)));
    await tester.pumpAndSettle();
  }

  for (final wardrobe in [false, true]) {
    testWidgets(
        'collapsed panel expands avatar to Home size (wardrobe=$wardrobe)',
        (tester) async {
      await open(tester, _Client(), ShopScreen(wardrobe: wardrobe));
      final frame = find.byKey(const Key('shop-avatar-frame'));
      final handle = find.byKey(const Key('shop-sheet-handle'));
      final compact = tester.getSize(frame);
      final avatarState = tester.state(find.byType(HomeAvatar));
      final target = AvatarLayout.home(const Size(320, 700));
      await tester.drag(handle, const Offset(0, 500));
      await tester.pumpAndSettle();
      final expanded = tester.getSize(frame);
      expect(expanded.width, closeTo(target.width, .1));
      expect(expanded.height, closeTo(target.height, .1));
      expect(expanded.height, greaterThan(compact.height));
      expect(tester.state(find.byType(HomeAvatar)), same(avatarState));
      await tester.tap(handle);
      await tester.pumpAndSettle();
      expect(tester.getSize(frame).height, closeTo(compact.height, .1));
      expect(tester.takeException(), isNull);
      final sheet = tester.widget<DraggableScrollableSheet>(
          find.byType(DraggableScrollableSheet));
      expect(sheet.maxChildSize, .5);
      await tester.drag(handle, const Offset(0, -1000));
      await tester.pumpAndSettle();
      expect(sheet.controller!.size, closeTo(.5, .001));
      expect(find.text('ถุงเท้า'), findsNothing);
      expect(find.text('แท่นยืน'), findsNothing);
    });
  }

  testWidgets(
      'white shirt has a real thumbnail, previews immediately and failed save retains it',
      (tester) async {
    final client = _Client()..starterShirts = true;
    await open(tester, client, const ShopScreen(wardrobe: true));
    await tester.ensureVisible(find.text('เสื้อ').first);
    await tester.tap(find.text('เสื้อ').first);
    await tester.pumpAndSettle();
    expect(find.text('เสื้อวิ่งสีขาว'), findsOneWidget);
    expect(find.byType(Image), findsNWidgets(2));
    await tester.tap(find.byKey(
        const ValueKey('item-thumbnail-10000000-0000-4000-8000-000000000004')));
    await tester.pumpAndSettle();
    final avatar = tester.widget<HomeAvatar>(find.byType(HomeAvatar));
    expect(avatar.outfitPreview['inner_top']!.renderData['variant'],
        'starter_tee_white');
    client.saveFail = true;
    await tester.tap(find.text('บันทึกการแต่งตัว'));
    await tester.pumpAndSettle();
    expect(
        tester
            .widget<HomeAvatar>(find.byType(HomeAvatar))
            .outfitPreview['inner_top']!
            .code,
        'starter_tee_white');
    client.saveFail = false;
    await tester.tap(find.text('บันทึกการแต่งตัว'));
    await tester.pumpAndSettle();
    expect(client.saved!['equipment'], [
      {'slot': 'inner_top', 'itemId': '10000000-0000-4000-8000-000000000004'}
    ]);
  });

  testWidgets('equipped item or returning to saved shirt leaves save disabled',
      (tester) async {
    final client = _Client()..starterShirts = true;
    await open(tester, client, const ShopScreen(wardrobe: true));
    await tester.ensureVisible(find.text('เสื้อ').first);
    await tester.tap(find.text('เสื้อ').first);
    await tester.pumpAndSettle();
    final black = find.byKey(
        const ValueKey('item-thumbnail-10000000-0000-4000-8000-000000000003'));
    final white = find.byKey(
        const ValueKey('item-thumbnail-10000000-0000-4000-8000-000000000004'));
    expect(tester.getSize(black).width, closeTo(112 * .8, .01));
    await tester.tap(black);
    await tester.pumpAndSettle();
    expect(tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNull);
    await tester.tap(white);
    await tester.pumpAndSettle();
    expect(tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNotNull);
    await tester.tap(black);
    await tester.pumpAndSettle();
    expect(tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNull);
    expect(client.saved, isNull);
  });

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
  testWidgets('filters share one row on a narrow phone', (tester) async {
    await open(tester, _Client(), const ShopCategoryScreen(categoryIndex: 0));
    final fields = find.byType(DropdownButtonFormField<String>);
    expect(
        tester.getTopLeft(fields.first).dy, tester.getTopLeft(fields.last).dy);
    expect(tester.getTopLeft(fields.last).dx,
        greaterThan(tester.getTopRight(fields.first).dx));
    expect(tester.takeException(), isNull);
  });
  testWidgets(
      'wardrobe reads owned inventory without prices and saves selected equipment; failed save keeps draft',
      (tester) async {
    final client = _Client()..populated = true;
    await open(tester, client, const ShopScreen(wardrobe: true));
    expect(find.text('แต่งตัว'), findsOneWidget);
    expect(find.byIcon(Icons.toll), findsNothing);
    expect(client.calls.every((call) => call.path == '/api/avatar/inventory'),
        isTrue);
    expect(find.text('ผมของฉัน'), findsOneWidget);
    expect(tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNull);
    await tester.tap(find.byKey(const ValueKey('item-thumbnail-owned-hair')));
    await tester.pumpAndSettle();
    expect(find.text('✓ เลือกอยู่'), findsOneWidget);
    client.saveFail = true;
    await tester.tap(find.text('บันทึกการแต่งตัว'));
    await tester.pumpAndSettle();
    expect(find.text('บันทึกไม่ได้'), findsOneWidget);
    expect(find.text('✓ เลือกอยู่'), findsOneWidget);
    client.saveFail = false;
    await tester.tap(find.text('บันทึกการแต่งตัว'));
    await tester.pumpAndSettle();
    expect(client.saved, {
      'equipment': [
        {'slot': 'hair', 'itemId': 'owned-hair'}
      ]
    });
    expect(find.text('บันทึกการแต่งตัวแล้ว'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
      'wardrobe category sorting and rarity query inventory, never price',
      (tester) async {
    final client = _Client();
    await open(tester, client,
        const ShopCategoryScreen(categoryIndex: 0, wardrobe: true));
    await tester.tap(find.byType(DropdownButtonFormField<String>).first);
    await tester.pumpAndSettle();
    expect(find.text('ราคา: ต่ำ → สูง'), findsNothing);
    await tester.tap(find.text('หายากมากก่อน').last);
    await tester.pumpAndSettle();
    expect(client.calls.last.path, '/api/avatar/inventory');
    expect(client.calls.last.queryParameters['sort'], 'rarity_desc');
    await tester.tap(find.byType(DropdownButtonFormField<String>).last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('ตำนาน').last);
    await tester.pumpAndSettle();
    expect(client.calls.last.queryParameters['rarity'], 'legendary');
    expect(tester.takeException(), isNull);
  });
}
