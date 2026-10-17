import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'progress_provider.dart';

// Account-scoped server balance. Never display the old mock 500 coins on Home.
final walletProvider = FutureProvider<int>((ref) async {
  return (await ref.watch(progressProvider.future)).coinBalance;
});
