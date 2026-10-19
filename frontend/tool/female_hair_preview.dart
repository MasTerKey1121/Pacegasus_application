// Local fit validation only; never reads/writes real onboarding or inventory.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pacegasus/providers/avatar_provider.dart';
import 'package:pacegasus/services/shop_api.dart';
import 'package:pacegasus/screens/home/home_avatar.dart';

void main() => runApp(const ProviderScope(
    child:
        MaterialApp(debugShowCheckedModeBanner: false, home: HairPreview())));

class HairPreview extends StatefulWidget {
  const HairPreview({super.key});
  @override
  State<HairPreview> createState() => _HairPreviewState();
}

class _HairPreviewState extends State<HairPreview> {
  bool female = true, wings = false, white = false;
  ShopItem item(String code, String slot, Map<String, dynamic> data) =>
      ShopItem(
          id: code,
          code: code,
          slot: slot,
          name: code,
          image: '',
          description: '',
          rarity: 'common',
          price: 0,
          owned: true,
          renderData: data);
  @override
  Widget build(BuildContext context) => Scaffold(
      backgroundColor: const Color(0xff201a32),
      appBar: AppBar(title: const Text('ทดลองสวมผม · ไม่แก้บัญชีจริง')),
      body: Column(children: [
        Expanded(
            child: HomeAvatar(
                outfit: AvatarOutfit({
          if (female)
            'hair': item('starter_hair_female', 'hair', {
              'hairStyle': 'ponytail',
              'avatarAsset':
                  'asset:assets/models/pacegasus_female_ponytail.glb',
              'avatarWithWingsAsset':
                  'asset:assets/models/pacegasus_female_ponytail_wings.glb'
            }),
          if (wings)
            'back': item('shop_golden_wings', 'back', {
              'avatarAsset': 'asset:assets/models/pacegasus_golden_wings.glb'
            }),
          if (white)
            'inner_top':
                item('white', 'inner_top', {'variant': 'starter_tee_white'}),
        }))),
        Wrap(spacing: 12, children: [
          FilterChip(
              label: const Text('ผมหางม้า'),
              selected: female,
              onSelected: (v) => setState(() => female = v)),
          FilterChip(
              label: const Text('ปีกทอง'),
              selected: wings,
              onSelected: (v) => setState(() => wings = v)),
          FilterChip(
              label: const Text('เสื้อขาว'),
              selected: white,
              onSelected: (v) => setState(() => white = v)),
        ]),
        const Padding(
            padding: EdgeInsets.all(16),
            child: Text('ลากซ้าย–ขวาเพื่อหมุน 360°',
                style: TextStyle(color: Colors.white))),
      ]));
}
