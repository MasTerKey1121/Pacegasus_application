import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'auth_provider.dart';

enum RunnerShirt {
  starter('ดำ–ทอง', 'starter'),
  cloud('เทาอ่อน–ทอง', 'cloud');

  const RunnerShirt(this.label, this.assetId);
  final String label;
  final String assetId;
  String modelAsset(RunnerStage stage) =>
      'assets/models/runner_${assetId}_${stage.name}.glb';
  String previewAsset(RunnerStage stage) =>
      'assets/models/runner_${assetId}_${stage.name}.png';
}

enum RunnerStage {
  track('ลู่วิ่งดำ–ทอง'),
  orbit('วงแหวนม่วง');

  const RunnerStage(this.label);
  final String label;
}

/// Device-local prototype wardrobe, isolated by signed-in account.
final avatarProvider = ChangeNotifierProvider<AvatarWardrobe>((ref) {
  final userId =
      ref.watch(authProvider.select((s) => s.user?['id']?.toString()));
  const storage = FlutterSecureStorage();
  final key = 'avatar_top_v1_${userId ?? 'guest'}';
  return AvatarWardrobe(
    read: () => storage.read(key: key),
    write: (value) => storage.write(key: key, value: value),
  )..restore();
});

class AvatarWardrobe extends ChangeNotifier {
  AvatarWardrobe({required this.read, required this.write});
  final Future<String?> Function() read;
  final Future<void> Function(String) write;
  RunnerShirt shirt = RunnerShirt.starter;
  RunnerStage stage = RunnerStage.track;
  bool motion = true;
  String? storageError;
  int _revision = 0;
  bool _disposed = false;
  Future<void> _writes = Future.value();

  Future<void> restore() async {
    final revision = _revision;
    try {
      final saved = await read();
      if (_disposed || revision != _revision) return;
      final data = saved != null && saved.startsWith('{')
          ? jsonDecode(saved) as Map<String, dynamic>
          : <String, dynamic>{'shirt': saved};
      shirt = RunnerShirt.values.firstWhere((s) => s.name == data['shirt'],
          orElse: () => RunnerShirt.starter);
      stage = RunnerStage.values.firstWhere((s) => s.name == data['stage'],
          orElse: () => RunnerStage.track);
    } catch (_) {
      if (_disposed || revision != _revision) return;
      storageError = 'อ่านชุดที่บันทึกไว้ไม่ได้ ลองเลือกชุดอีกครั้ง';
    }
    if (!_disposed) notifyListeners();
  }

  Future<void> selectShirt(RunnerShirt value) {
    shirt = value;
    return _save();
  }

  Future<void> selectStage(RunnerStage value) {
    stage = value;
    return _save();
  }

  Future<void> _save() {
    final revision = ++_revision;
    final value = jsonEncode({'shirt': shirt.name, 'stage': stage.name});
    storageError = null;
    notifyListeners();
    // Serialize writes so rapid taps cannot persist an older choice last.
    _writes = _writes.then((_) async {
      try {
        await write(value);
      } catch (_) {
        if (!_disposed && revision == _revision) {
          storageError = 'บันทึกชุดไม่ได้ ชุดนี้อาจหายเมื่อเปิดแอปใหม่';
          notifyListeners();
        }
      }
    });
    return _writes;
  }

  void toggleMotion(bool enabled) {
    motion = enabled;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
