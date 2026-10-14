// Memory-only purchase/preview fixture. No real account coins or database calls.
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pacegasus/services/api_client.dart';
import 'package:pacegasus/services/shop_api.dart';
import 'package:pacegasus/providers/avatar_provider.dart';
import 'package:pacegasus/navigation/home_route_observer.dart';
import 'package:pacegasus/screens/shop/shop_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final starter = jsonDecode(
          await rootBundle.loadString('assets/models/starter_catalog.json'))
      as List;
  final paid =
      jsonDecode(await rootBundle.loadString('assets/models/shop_catalog.json'))
          as List;
  final store = _Store(starter, paid);
  runApp(ProviderScope(
      overrides: [
        shopApiProvider.overrideWithValue(store),
        avatarOutfitProvider
            .overrideWith((ref) async => AvatarOutfit(Map.of(store.outfit))),
      ],
      child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: ThemeData.dark(),
          navigatorObservers: [homeRouteObserver],
          home: const _Preview())));
}

class _Preview extends StatelessWidget {
  const _Preview();
  @override
  Widget build(BuildContext context) => Scaffold(
      appBar: AppBar(title: const Text('DEMO · เงินทดสอบ'), actions: [
        TextButton(
            onPressed: () => Navigator.push(
                context,
                MaterialPageRoute<void>(
                    builder: (_) => const ShopScreen(wardrobe: true))),
            child: const Text('แต่งตัว')),
      ]),
      body: const ShopScreen());
}

class _Store extends ShopApi {
  _Store(List starter, List paid)
      : super(ApiClient(baseUrl: 'http://localhost')) {
    for (final e in starter) {
      final i = ShopItem(
          id: e['id'],
          code: e['code'],
          slot: e['slot'],
          name: e['name'],
          image: e['thumbnail'],
          description: 'ไอเทมเริ่มต้นฟรี',
          rarity: 'common',
          price: 0,
          owned: true,
          renderData: Map<String, dynamic>.from(e['render']));
      owned[i.id] = i;
      if (e['render']['starterEquipped'] == true) outfit[i.slot!] = i;
    }
    for (final e in paid) {
      actualIds[e['listingId']] = e['id'];
      listings.add(ShopItem(
          id: e['listingId'],
          code: e['code'],
          slot: 'inner_top',
          name: e['name'],
          image: 'asset:assets/models/items/${e['code']}.png',
          description: 'เสื้อวิ่ง โลโก้สีทอง',
          rarity: 'common',
          price: e['price'],
          owned: false,
          renderData: Map<String, dynamic>.from(e['render'])));
    }
  }
  int coins = 30;
  final actualIds = <String, String>{};
  final listings = <ShopItem>[];
  final owned = <String, ShopItem>{};
  final outfit = <String, ShopItem>{};
  @override
  Future<int> balance() async => coins;
  @override
  Future<int> purchase(String id) async {
    final item = listings.firstWhere((i) => i.id == id);
    if (owned.containsKey(actualIds[id])) {
      throw ApiException(409, 'คุณมีไอเทมนี้อยู่แล้ว');
    }
    if (coins < item.price) throw ApiException(400, 'เหรียญไม่พอ');
    coins -= item.price;
    owned[actualIds[id]!] = _copy(item, actualIds[id]!, false);
    return coins;
  }

  ShopItem _copy(ShopItem i, String id, bool equipped) => ShopItem(
      id: id,
      code: i.code,
      slot: i.slot,
      name: i.name,
      image: i.image,
      description: i.description,
      rarity: i.rarity,
      price: 0,
      owned: true,
      equipped: equipped,
      renderData: i.renderData);
  @override
  Future<ShopPage> list(String slots,
      {String sort = 'featured',
      String? rarity,
      int offset = 0,
      int limit = 30}) async {
    final result = listings
        .where((i) =>
            slots.split(',').contains(i.slot) &&
            !owned.containsKey(actualIds[i.id]) &&
            (rarity == null || rarity == i.rarity))
        .toList();
    if (sort == 'price_desc') result.sort((a, b) => b.price.compareTo(a.price));
    return ShopPage(result.skip(offset).take(limit).toList(), result.length);
  }

  @override
  Future<ShopPage> inventory(String slots,
      {String sort = 'newest',
      String? rarity,
      int offset = 0,
      int limit = 30}) async {
    final result = owned.values
        .where((i) =>
            slots.split(',').contains(i.slot) &&
            (rarity == null || rarity == i.rarity))
        .toList();
    return ShopPage(
        result
            .skip(offset)
            .take(limit)
            .map((i) => _copy(i, i.id, outfit[i.slot]?.id == i.id))
            .toList(),
        result.length);
  }

  @override
  Future<void> saveOutfit(Map<String, ShopItem> changes) async =>
      outfit.addAll(changes);
}
