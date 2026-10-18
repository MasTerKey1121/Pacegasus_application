import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'auth_provider.dart';
import 'run_setup_provider.dart';

class RewardReceipt {
  final String source, sourceId, sessionId;
  final int? coins, exp;
  const RewardReceipt(
      this.source, this.sourceId, this.sessionId, this.coins, this.exp);
  String get key => '$source/$sourceId';
  Map<String, dynamic> toJson() => {
        'source': source,
        'sourceId': sourceId,
        'sessionId': sessionId,
        'coins': coins,
        'exp': exp
      };
  factory RewardReceipt.fromJson(Map row) => RewardReceipt(
      '${row['source']}',
      '${row['sourceId']}',
      '${row['sessionId']}',
      amount(row['coins']),
      amount(row['exp']));
  static int? amount(Object? value) =>
      value is num && value.isFinite && value >= 0 ? value.toInt() : null;
}

class RunRewards extends ChangeNotifier {
  RunRewards(this.owner, {this.storage = const FlutterSecureStorage()});
  final String owner;
  final FlutterSecureStorage storage;
  final Map<String, Map<String, RewardReceipt>> _runs = {};
  final Map<String, Set<String>> _missing = {};
  final Map<String, Future<void>> _loading = {};
  final Set<String> _loaded = {};
  Future<void> _writes = Future.value();
  bool _alive = true;
  List<RewardReceipt> receipts(String session) =>
      _runs[session]?.values.toList() ?? [];
  bool hasSource(String session, String source) =>
      receipts(session).any((r) => r.source == source);
  bool hasMissing(String session) => (_missing[session]?.isNotEmpty ?? false);
  // A subtotal of acknowledged amounts, never a replacement for an unknown
  // complete total. The UI must label it explicitly as partial.
  int? confirmedTotal(String session, {bool exp = false}) {
    final amounts =
        receipts(session).map((r) => exp ? r.exp : r.coins).whereType<int>();
    return amounts.isEmpty ? null : amounts.fold<int>(0, (sum, n) => sum + n);
  }

  int? total(String session, {bool exp = false}) {
    final rows = receipts(session);
    if (rows.isEmpty ||
        hasMissing(session) ||
        rows.any((r) => (exp ? r.exp : r.coins) == null)) {
      return null;
    }
    return rows.fold<int>(0, (sum, r) => sum + (exp ? r.exp! : r.coins!));
  }

  Future<void> load(String session) async {
    if (_loaded.contains(session)) return;
    if (_loading[session] != null) return _loading[session];
    final future = _read(session);
    _loading[session] = future;
    try {
      await future;
    } finally {
      _loading.remove(session);
    }
  }

  Future<void> _read(String session) async {
    final raw = owner.isEmpty
        ? null
        : await storage.read(key: 'run_rewards_v1_${owner}_$session');
    if (!_alive) return;
    if (raw != null) {
      final data = jsonDecode(raw) as Map;
      for (final row in (data['receipts'] as List? ?? [])) {
        final r = RewardReceipt.fromJson(row as Map);
        if (r.sessionId == session) (_runs[session] ??= {})[r.key] = r;
      }
      (_missing[session] ??= {})
          .addAll((data['missing'] as List? ?? []).map((e) => '$e'));
    }
    _loaded.add(session);
  }

  Future<void> _save(String session) {
    if (owner.isEmpty) return Future.value();
    final snapshot = jsonEncode({
      'receipts': receipts(session).map((r) => r.toJson()).toList(),
      'missing': (_missing[session] ?? {}).toList()
    });
    final next = _writes.then((_) => storage.write(
        key: 'run_rewards_v1_${owner}_$session', value: snapshot));
    _writes = next.then((_) {}, onError: (Object _, StackTrace __) {});
    return next;
  }

  Future<void> record(RewardReceipt receipt) async {
    await load(receipt.sessionId);
    if (!_alive) return;
    (_runs[receipt.sessionId] ??= {}).putIfAbsent(receipt.key, () => receipt);
    _missing[receipt.sessionId]?.remove(receipt.source);
    notifyListeners();
    await _save(receipt.sessionId);
  }

  Future<void> expectSource(String session, String source) async {
    await load(session);
    if (!_alive || hasSource(session, source)) return;
    (_missing[session] ??= {}).add(source);
    notifyListeners();
    await _save(session);
  }

  @override
  void dispose() {
    _alive = false;
    super.dispose();
  }
}

final runRewardsProvider = ChangeNotifierProvider<RunRewards>((ref) =>
    RunRewards(
        ref.watch(authProvider.select((s) => s.user?['id']))?.toString() ??
            ''));

// Retry only read-only endpoints; never repeat a reward write to reconstruct UI.
final rewardReloadProvider = Provider((ref) => (String session) async {
      final owner = ref.read(authProvider).user?['id']?.toString();
      final result = await ref
          .read(runningSessionApiProvider)
          .getDetail(sessionId: session);
      final row = result['data'] as Map;
      if (owner == null ||
          ref.read(authProvider).user?['id']?.toString() != owner ||
          row['user_id'] != owner ||
          row['status'] != 'completed') {
        throw StateError('ยังยืนยันรางวัลของการวิ่งนี้ไม่ได้');
      }
      await ref.read(runRewardsProvider).load(session);
    });
