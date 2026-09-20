import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:pacegasus/providers/avatar_provider.dart';

void main() {
  test('late restore cannot undo a newly selected shirt', () async {
    final saved = Completer<String?>();
    final wardrobe =
        AvatarWardrobe(read: () => saved.future, write: (_) async {});
    final restoring = wardrobe.restore();
    await wardrobe.selectShirt(RunnerShirt.cloud);
    saved.complete('starter');
    await restoring;
    expect(wardrobe.shirt, RunnerShirt.cloud);
    wardrobe.dispose();
  });

  test('rapid selections persist in order and restore after restart', () async {
    String? stored;
    final first = Completer<void>();
    var writes = 0;
    final wardrobe = AvatarWardrobe(
        read: () async => stored,
        write: (value) async {
          if (writes++ == 0) await first.future;
          stored = value;
        });
    final a = wardrobe.selectShirt(RunnerShirt.cloud);
    final b = wardrobe.selectShirt(RunnerShirt.starter);
    first.complete();
    await Future.wait([a, b]);
    expect(jsonDecode(stored!)['shirt'], 'starter');
    final restored =
        AvatarWardrobe(read: () async => stored, write: (_) async {});
    await restored.restore();
    expect(restored.shirt, RunnerShirt.starter);
    wardrobe.dispose();
    restored.dispose();
  });

  test('storage failure is visible and a subsequent selection can recover',
      () async {
    var fail = true;
    final wardrobe = AvatarWardrobe(
        read: () async => 'unknown',
        write: (_) async {
          if (fail) throw StateError('storage unavailable');
        });
    await wardrobe.restore();
    expect(wardrobe.shirt, RunnerShirt.starter);
    await wardrobe.selectShirt(RunnerShirt.cloud);
    expect(wardrobe.storageError, isNotNull);
    fail = false;
    await wardrobe.selectShirt(RunnerShirt.cloud);
    expect(wardrobe.storageError, isNull);
    wardrobe.dispose();
  });

  test('stage changes preserve shirt and both choices survive restart',
      () async {
    String? saved;
    final wardrobe = AvatarWardrobe(
        read: () async => saved,
        write: (value) async {
          saved = value;
        });
    await wardrobe.selectShirt(RunnerShirt.cloud);
    await wardrobe.selectStage(RunnerStage.orbit);
    expect(wardrobe.shirt, RunnerShirt.cloud);
    final restored =
        AvatarWardrobe(read: () async => saved, write: (_) async {});
    await restored.restore();
    expect(restored.shirt, RunnerShirt.cloud);
    expect(restored.stage, RunnerStage.orbit);
    wardrobe.dispose();
    restored.dispose();
  });

  test('bundled models have consistent slots and a looping idle animation', () {
    for (final (shirt, stage) in [
      for (final shirt in RunnerShirt.values)
        for (final stage in RunnerStage.values) (shirt, stage),
    ]) {
      final bytes = File(shirt.modelAsset(stage)).readAsBytesSync();
      final data = ByteData.sublistView(bytes);
      expect(data.getUint32(0, Endian.little), 0x46546c67);
      expect(data.getUint32(4, Endian.little), 2);
      expect(data.getUint32(8, Endian.little), bytes.length);
      final jsonLength = data.getUint32(12, Endian.little);
      final gltf =
          jsonDecode(utf8.decode(bytes.sublist(20, 20 + jsonLength))) as Map;
      final names = (gltf['nodes'] as List).map((n) => n['name']);
      expect(names, contains('Slot_Stage'));
      expect(names, contains('Stage_${stage.name}'));
      expect(
          names,
          isNot(contains(
              'Stage_${stage == RunnerStage.track ? 'orbit' : 'track'}')));
      expect(
          names,
          containsAll([
            'AvatarRoot',
            'Slot_Hair',
            'Slot_Top',
            'Slot_Bottom',
            'Slot_Shoes',
            'Socket_Back',
            'Socket_Hand_L',
            'Socket_Hand_R'
          ]));
      final animations = gltf['animations'] as List;
      expect(animations, hasLength(1));
      expect(animations.first['channels'], isNotEmpty);
      final accessors = gltf['accessors'] as List;
      final views = gltf['bufferViews'] as List;
      final binaryOffset = 20 + jsonLength + 8;
      for (final sampler in animations.first['samplers']) {
        final output = accessors[sampler['output']];
        final view = views[output['bufferView']];
        final offset = binaryOffset +
            (view['byteOffset'] as int? ?? 0) +
            (output['byteOffset'] as int? ?? 0);
        final components = output['type'] == 'VEC4' ? 4 : 3;
        final count = output['count'] as int;
        for (var i = 0; i < components; i++) {
          expect(
              data.getFloat32(offset + i * 4, Endian.little),
              closeTo(
                  data.getFloat32(offset + ((count - 1) * components + i) * 4,
                      Endian.little),
                  .00001));
        }
      }
    }
  });
}
