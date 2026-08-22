import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// A device-local checkpoint for an in-progress run.  It intentionally holds
/// no auth token and is cleared only after the run has been submitted.
class RunDraftStore {
  static const _key = 'active_run_draft_v1';
  final FlutterSecureStorage _storage = const FlutterSecureStorage();

  Future<Map<String, dynamic>?> load() async {
    final raw = await _storage.read(key: _key);
    if (raw == null || raw.isEmpty) return null;
    try {
      return Map<String, dynamic>.from(jsonDecode(raw) as Map);
    } catch (_) {
      await clear();
      return null;
    }
  }

  Future<void> save(Map<String, dynamic> draft) =>
      _storage.write(key: _key, value: jsonEncode(draft));

  Future<void> clear() => _storage.delete(key: _key);
}

final runDraftStore = RunDraftStore();
