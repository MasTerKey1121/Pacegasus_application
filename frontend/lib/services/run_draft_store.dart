import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'running_session_api.dart';

/// Serializes writes/deletes. seal closes the writer before queued writes drain.
class RunDraftStore {
  RunDraftStore({FlutterSecureStorage storage = const FlutterSecureStorage()})
      : _storage = storage;
  final FlutterSecureStorage _storage;
  static const _legacyKey = 'active_run_draft_v1';
  Future<void> _tail = Future.value();
  final Set<String> _sealed = {};
  String _key(String owner) => 'active_run_draft_v2_$owner';
  String _identity(Map draft) =>
      '${draft['ownerUserId']}/${draft['sessionId']}';
  Future<void> _enqueue(Future<void> Function() action) {
    final next = _tail.then((_) => action());
    _tail = next.then((_) {}, onError: (Object _, StackTrace __) {});
    return next;
  }

  Future<Map<String, dynamic>?> load({String? userId}) async {
    await _tail;
    final raw =
        await _storage.read(key: userId == null ? _legacyKey : _key(userId));
    if (raw == null) return null;
    try {
      return Map<String, dynamic>.from(jsonDecode(raw) as Map);
    } catch (_) {
      throw const FormatException(
          'อ่านข้อมูลการวิ่งที่เก็บไว้ไม่ได้ ข้อมูลยังไม่ถูกลบ');
    }
  }

  Future<Map<String, dynamic>?> loadForUser(String? userId) async {
    if (userId == null) return null;
    final saved = await load(userId: userId);
    if (saved != null) return saved['ownerUserId'] == userId ? saved : null;
    final legacy = await load();
    if (legacy == null) return null;
    if (legacy['ownerUserId'] == null) {
      await clear();
      return null;
    }
    if (legacy['ownerUserId'] != userId) return null;
    await save(legacy);
    await clear();
    return legacy;
  }

  Future<void> save(Map<String, dynamic> draft) {
    if (_sealed.contains(_identity(draft))) return Future.value();
    final snapshot = jsonEncode(draft);
    final owner = draft['ownerUserId']?.toString();
    return _enqueue(() => _storage.write(
        key: owner == null ? _legacyKey : _key(owner), value: snapshot));
  }

  void reopen(String owner, String session) =>
      _sealed.remove('$owner/$session');
  Future<void> seal(String owner, String session) {
    _sealed.add('$owner/$session');
    return _tail;
  }

  Future<void> clear({String? userId}) => _enqueue(
      () => _storage.delete(key: userId == null ? _legacyKey : _key(userId)));
}

/// Offline/404 are errors, never evidence that a checkpoint should be deleted.
Future<Map<String, dynamic>?> verifiedRunDraft(
    RunDraftStore store, RunningSessionApi api, String userId) async {
  final draft = await store.loadForUser(userId);
  if (draft == null) return null;
  final response =
      await api.getDetail(sessionId: draft['sessionId'].toString());
  final detail = response['data'] as Map;
  if (detail['user_id']?.toString() != userId ||
      detail['id']?.toString() != draft['sessionId']) {
    throw StateError('ไม่สามารถยืนยันเจ้าของ Session ได้');
  }
  if (detail['status'] == 'completed' || detail['status'] == 'abandoned') {
    await store.seal(userId, draft['sessionId'].toString());
    await store.clear(userId: userId);
    return null;
  }
  if (detail['status'] != 'in_progress') {
    throw StateError('ไม่ทราบสถานะ Session');
  }
  store.reopen(userId, draft['sessionId'].toString());
  return {
    ...draft,
    'environment': detail['environment'] ?? draft['environment'],
    'sessionType': detail['session_type'] ?? draft['sessionType'],
    'elapsedSeconds': draft['elapsedSeconds'] ??
        num.tryParse('${detail['duration_seconds']}')?.toInt() ??
        0,
    'distanceKm': draft['distanceKm'] ??
        num.tryParse('${detail['distance_km']}')?.toDouble() ??
        0,
    'routePoints': (draft['routePoints'] as List?)?.isNotEmpty == true
        ? draft['routePoints']
        : detail['route_points'] ?? [],
  };
}

final runDraftStore = RunDraftStore();
