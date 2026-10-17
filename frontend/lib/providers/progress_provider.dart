import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'auth_provider.dart';

class GameProgress {
  final int coinBalance, level, exp, expToNext;
  const GameProgress(this.coinBalance, this.level, this.exp, this.expToNext);
  factory GameProgress.fromJson(Map data) {
    final values = ['coinBalance', 'level', 'exp', 'expToNext']
        .map((key) => int.tryParse('${data[key]}'))
        .toList();
    if (values.any((v) => v == null || v < 0) || values[3] == 0) {
      throw const FormatException('ข้อมูล progress ไม่ครบ');
    }
    return GameProgress(values[0]!, values[1]!, values[2]!, values[3]!);
  }
  double get fraction => (exp / expToNext).clamp(0.0, 1.0);
}

// Rebuilt on account changes. Riverpod discards results of disposed requests;
// no response belonging to a previous account can become the current balance.
final progressProvider = FutureProvider<GameProgress>((ref) async {
  final id = ref.watch(authProvider.select((s) => s.user?['id']));
  if (id == null) throw StateError('กรุณาเข้าสู่ระบบ');
  final result = await ref
      .read(apiClientProvider)
      .get('/api/users/me/progress', auth: true);
  return GameProgress.fromJson(result['data'] as Map);
});
