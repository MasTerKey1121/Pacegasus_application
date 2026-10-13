import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'auth_provider.dart';
import '../services/shop_api.dart';

// Account-scoped server balance. Never display the old mock 500 coins on Home.
final walletProvider = FutureProvider<int>((ref) async {
  final userId = ref.watch(authProvider.select((state) => state.user?['id']));
  if (userId == null) return 0;
  return ref.read(shopApiProvider).balance();
});
