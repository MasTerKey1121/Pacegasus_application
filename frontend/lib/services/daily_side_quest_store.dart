import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class DailySideQuestStore {
  const DailySideQuestStore({this.storage = const FlutterSecureStorage()});
  final FlutterSecureStorage storage;
  String _key(String user, String day) => 'daily_side_v1_${user}_$day';
  Future<Map<String, dynamic>?> load(String user, String day) async {
    final raw = await storage.read(key: _key(user, day));
    if (raw == null) return null;
    // Corruption must not silently generate another rewarding set.
    return Map<String, dynamic>.from(jsonDecode(raw) as Map);
  }

  Future<void> save(String user, String day, Map<String, dynamic> data) =>
      storage.write(key: _key(user, day), value: jsonEncode(data));
}
