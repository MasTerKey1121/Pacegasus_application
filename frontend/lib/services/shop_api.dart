import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/auth_provider.dart';
import 'api_client.dart';

final shopApiProvider =
    Provider((ref) => ShopApi(ref.watch(apiClientProvider)));

class ShopItem {
  final String id, name, rarity, image, description;
  final int price;
  final bool owned;
  const ShopItem(
      {required this.id,
      required this.name,
      required this.rarity,
      required this.image,
      required this.description,
      required this.price,
      required this.owned});
  factory ShopItem.fromJson(Map<String, dynamic> json) {
    final item = json['item'] as Map<String, dynamic>;
    return ShopItem(
        id: json['listingId'] as String,
        name: item['name'] as String,
        rarity: item['rarity'] as String,
        image: item['thumbnailUrl'] as String? ?? '',
        description: item['description'] as String? ?? '',
        price: (json['priceCoins'] as num).toInt(),
        owned: json['owned'] == true);
  }
}

class ShopPage {
  final List<ShopItem> items;
  final int total;
  const ShopPage(this.items, this.total);
}

class ShopApi {
  final ApiClient client;
  ShopApi(this.client);
  Future<ShopPage> list(String slots,
      {String sort = 'featured',
      String? rarity,
      int offset = 0,
      int limit = 30}) async {
    final query = Uri(queryParameters: {
      'slot': slots,
      'sort': sort,
      'offset': '$offset',
      'limit': '$limit',
      if (rarity != null) 'rarity': rarity,
    }).query;
    final response = await client.get('/api/shop/items?$query', auth: true);
    final data = response['data'] as Map<String, dynamic>;
    return ShopPage(
        (data['items'] as List)
            .map((item) => ShopItem.fromJson(item as Map<String, dynamic>))
            .toList(),
        (data['total'] as num).toInt());
  }

  Future<int> balance() async {
    final response = await client.get('/api/users/me/progress', auth: true);
    return (response['data']['coinBalance'] as num).toInt();
  }
}
