import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../app_theme.dart';
import '../home/home_avatar.dart';

/// Portrait storefront layout. Home navigation remains disabled until the
/// catalog, wallet and purchase APIs are available; no sample inventory is used.
class ShopScreen extends StatefulWidget {
  const ShopScreen({super.key});

  @override
  State<ShopScreen> createState() => _ShopScreenState();
}

class _ShopScreenState extends State<ShopScreen> {
  static const _background = Color(0xFF110E20);
  static const _panel = Color(0xFF201A32);
  static const _accent = Color(0xFFC5A2FF);
  static const _middle = .46;
  static const _maximum = .86;
  static const _categories = [
    (Icons.apps_rounded, 'ทั้งหมด'),
    (Icons.checkroom_rounded, 'เสื้อผ้า'),
    (Icons.directions_run_rounded, 'รองเท้า'),
    (Icons.auto_awesome_outlined, 'เครื่องประดับ'),
    (Icons.landscape_outlined, 'พื้นหลัง'),
  ];
  final _sheet = DraggableScrollableController();
  int _category = 0;

  @override
  void dispose() {
    _sheet.dispose();
    super.dispose();
  }

  void _move(double size) {
    if (!_sheet.isAttached) return;
    _sheet.animateTo(size,
        duration: const Duration(milliseconds: 240),
        curve: Curves.easeOutCubic);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: _background,
    body: SafeArea(child: LayoutBuilder(builder: (context, constraints) {
      final height = constraints.maxHeight;
      final minimum = (48 / height).clamp(.06, .2);
      return Stack(children: [
        Positioned.fill(child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => _move(minimum),
          child: const DecoratedBox(decoration: BoxDecoration(
            gradient: RadialGradient(center: Alignment(0, -.3), radius: .85,
              colors: [Color(0xFF49345C), _background]),
          )),
        )),
        // Keep the character visible above the initial catalog position.
        Positioned(top: 86, left: 48, right: 48,
          height: math.max(80, math.min(330, height * .54 - 96)),
          child: const Semantics(label: 'ตัวละครของคุณ',
            child: HomeAvatar())),
        Positioned(top: 12, left: 12, right: 20, child: Row(children: [
          IconButton(tooltip: 'กลับ', onPressed: () => Navigator.maybePop(context),
            style: IconButton.styleFrom(backgroundColor: _panel),
            icon: const Icon(Icons.arrow_back_rounded, size: 21)),
          const SizedBox(width: 12),
          Expanded(child: Text('ร้านค้า', style: AppText.heading(size: 24))),
          Tooltip(message: 'ยอดเหรียญจะแสดงเมื่อเปิดใช้งานร้านค้า',
            child: Container(padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(color: _panel,
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: AppColors.borderHi)),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.toll_outlined, color: AppColors.gold2, size: 19),
                const SizedBox(width: 7),
                Text('—', style: AppText.heading(size: 16, color: AppColors.gold2)),
              ]))),
        ])),
        DraggableScrollableSheet(
          controller: _sheet, initialChildSize: _middle,
          minChildSize: minimum, maxChildSize: _maximum,
          snap: true, snapSizes: const [_middle],
          builder: (context, scrollController) => Material(
            color: _panel,
            shape: const RoundedRectangleBorder(
              borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
              side: BorderSide(color: AppColors.borderHi)),
            clipBehavior: Clip.antiAlias,
            child: Column(children: [
              Semantics(button: true, label: 'ย่อหรือขยายร้านค้า', child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => _move(_sheet.size < _middle - .02 ? _middle
                  : _sheet.size < _maximum - .02 ? _maximum : _middle),
                onVerticalDragUpdate: (details) => _sheet.jumpTo(
                  (_sheet.size - details.delta.dy / height).clamp(minimum, _maximum)),
                onVerticalDragEnd: (details) {
                  final current = _sheet.size;
                  final stops = [minimum, _middle, _maximum];
                  final velocity = details.primaryVelocity ?? 0;
                  if (velocity.abs() > 250) {
                    final next = stops.where((stop) => velocity < 0
                      ? stop > current + .01 : stop < current - .01);
                    _move(next.isEmpty ? (velocity < 0 ? _maximum : minimum)
                      : velocity < 0 ? next.first : next.last);
                  } else {
                    stops.sort((a, b) => (a - current).abs().compareTo((b - current).abs()));
                    _move(stops.first);
                  }
                },
                child: SizedBox(height: 48, width: double.infinity,
                  child: Center(child: Container(width: 36, height: 4,
                    decoration: BoxDecoration(color: const Color(0xFF80708F),
                      borderRadius: BorderRadius.circular(4))))),
              )),
              Expanded(child: ListView(controller: scrollController,
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 28), children: [
                  Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('สไตล์ในแบบคุณ', style: AppText.heading(size: 22)),
                      const SizedBox(height: 3),
                      Text('แต่งเติมทุกก้าวให้เป็นตัวคุณ',
                        style: AppText.body(size: 12, color: AppColors.textSecondary)),
                    ])),
                    const SizedBox(width: 8),
                    Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(color: const Color(0xFF352845),
                        borderRadius: BorderRadius.circular(20)),
                      child: Text('เร็ว ๆ นี้', style: AppText.body(size: 11, color: _accent))),
                  ]),
                  const SizedBox(height: 20),
                  const TextField(enabled: false,
                    decoration: InputDecoration(hintText: 'ค้นหาไอเทม',
                      prefixIcon: Icon(Icons.search_rounded),
                      filled: true, fillColor: Color(0xFF171322),
                      disabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.all(Radius.circular(16)),
                        borderSide: BorderSide(color: AppColors.border)))),
                  const SizedBox(height: 16),
                  SingleChildScrollView(scrollDirection: Axis.horizontal,
                    child: Row(children: [
                      for (final (index, category) in _categories.indexed)
                        Padding(padding: const EdgeInsets.only(right: 8),
                          child: ChoiceChip(
                            selected: _category == index, showCheckmark: false,
                            selectedColor: const Color(0xFF493460),
                            avatar: Icon(category.$1, size: 16,
                              color: _category == index ? _accent : AppColors.textSecondary),
                            label: Text(category.$2, style: AppText.body(size: 12,
                              color: _category == index ? AppColors.textPrimary : AppColors.textSecondary)),
                            onSelected: (_) => setState(() => _category = index),
                          )),
                    ])),
                  const SizedBox(height: 24),
                  Text(_category == 0 ? 'สำรวจไอเทม' : _categories[_category].$2,
                    style: AppText.heading(size: 16)),
                  const SizedBox(height: 16),
                  Container(padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
                    decoration: BoxDecoration(color: const Color(0xFF1A1528),
                      borderRadius: BorderRadius.circular(22),
                      border: Border.all(color: AppColors.border)),
                    child: Column(children: [
                      const Icon(Icons.storefront_outlined, size: 34, color: _accent),
                      const SizedBox(height: 14),
                      Text('พบกันเร็ว ๆ นี้', style: AppText.heading(size: 17)),
                      const SizedBox(height: 6),
                      Text('ไอเทมใหม่สำหรับตัวละครของคุณ\nจะพร้อมให้เลือกเมื่อร้านค้าเปิด',
                        textAlign: TextAlign.center,
                        style: AppText.body(size: 12, color: AppColors.textSecondary)),
                    ])),
                ])),
            ]),
          ),
        ),
      ]);
    })),
  );
}
