// Standalone memory-only wardrobe fixture; no auth, purchases or database writes.
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
  final entries = jsonDecode(
          await rootBundle.loadString('assets/models/starter_catalog.json'))
      as List;
  final api = _DemoApi(entries);
  runApp(ProviderScope(
      overrides: [
        shopApiProvider.overrideWithValue(api),
        avatarOutfitProvider
            .overrideWith((ref) async => AvatarOutfit(Map.of(api.outfit))),
      ],
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: ThemeData.dark(),
        navigatorObservers: [homeRouteObserver],
        home: const Banner(
            message: 'DEMO',
            location: BannerLocation.topEnd,
            child: ShopScreen(wardrobe: true)),
      )));
}

class _DemoApi extends ShopApi {
  _DemoApi(List entries) : super(ApiClient(baseUrl: 'http://localhost')) {
    for (final entry in entries) {
      final item = ShopItem(
          id: entry['id'],
          code: entry['code'],
          slot: entry['slot'],
          name: entry['name'],
          image: entry['thumbnail'],
          description: 'ไอเทมเริ่มต้นฟรี',
          rarity: 'common',
          price: 0,
          owned: true,
          renderData: Map<String, dynamic>.from(entry['render']));
      items.add(item);
      if (entry['render']['starterEquipped'] == true) outfit[item.slot!] = item;
    }
  }
  final items = <ShopItem>[];
  final outfit = <String, ShopItem>{};
  @override
  Future<ShopPage> inventory(String slots,
      {String sort = 'newest',
      String? rarity,
      int offset = 0,
      int limit = 30}) async {
    final matches = items
        .where((i) =>
            slots.split(',').contains(i.slot) &&
            (rarity == null || rarity == i.rarity))
        .toList();
    return ShopPage(
        matches
            .skip(offset)
            .take(limit)
            .map((i) => ShopItem(
                id: i.id,
                name: i.name,
                rarity: i.rarity,
                image: i.image,
                description: i.description,
                price: 0,
                owned: true,
                slot: i.slot,
                code: i.code,
                renderData: i.renderData,
                equipped: outfit[i.slot]?.id == i.id))
            .toList(),
        matches.length);
  }

  @override
  Future<void> saveOutfit(Map<String, ShopItem?> changes) async {
    for (final entry in changes.entries) {
      if (entry.value == null) {
        outfit.remove(entry.key);
      } else {
        outfit[entry.key] = entry.value!;
      }
    }
  }
}
