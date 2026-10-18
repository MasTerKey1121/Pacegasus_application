import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/shop_api.dart';
import 'auth_provider.dart';

class AvatarOutfit {
  const AvatarOutfit(this.equipment);
  factory AvatarOutfit.fromEquipment(List<dynamic> entries) {
    final equipment = <String, ShopItem>{};
    for (final entry in entries) {
      final item = Map<String, dynamic>.from(entry['item'] as Map);
      final slot = entry['slot'] as String;
      equipment[slot] = ShopItem(
        id: item['id'] as String,
        name: item['name'] as String,
        rarity: item['rarity'] as String,
        image: item['thumbnailUrl'] as String? ?? '',
        description: item['description'] as String? ?? '',
        price: 0,
        owned: true,
        slot: slot,
        equipped: true,
        code: item['code'] as String?,
        renderData: Map<String, dynamic>.from(item['renderData'] as Map? ?? {}),
      );
    }
    return AvatarOutfit(equipment);
  }
  final Map<String, ShopItem> equipment;
  AvatarOutfit preview(Map<String, ShopItem?> changes) {
    final result = Map<String, ShopItem>.of(equipment);
    for (final entry in changes.entries) {
      final item = entry.value;
      if (item == null) {
        result.remove(entry.key);
      } else {
        result[entry.key] = item;
      }
    }
    return AvatarOutfit(result);
  }

  String? get variant =>
      equipment['inner_top']?.renderData['variant'] as String?;
  String get assetPath =>
      (equipment['back']?.renderData['avatarAsset'] as String?)
          ?.replaceFirst('asset:', '') ??
      'assets/models/pacegasus_starter_v9.glb';
}

final avatarOutfitProvider = FutureProvider<AvatarOutfit>((ref) async {
  final auth = ref.watch(authProvider);
  if (auth.status != AuthStatus.authenticated) return const AvatarOutfit({});
  final response =
      await ref.read(apiClientProvider).get('/api/avatar/me', auth: true);
  return AvatarOutfit.fromEquipment(response['data']['equipment'] as List);
});
