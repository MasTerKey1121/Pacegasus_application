import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../app_theme.dart';
import '../home/home_avatar.dart';

/// Prepared for the clothing inventory API; navigation stays disabled on Home.
class WardrobeScreen extends StatefulWidget {
  const WardrobeScreen({super.key});

  @override
  State<WardrobeScreen> createState() => _WardrobeScreenState();
}

class _WardrobeScreenState extends State<WardrobeScreen> {
  final _sheet = DraggableScrollableController();
  static const _background = Color(0xFF110E20);
  static const _panel = Color(0xFF201A32);
  static const _middle = .4;
  static const _maximum = .76;

  @override
  void dispose() {
    _sheet.dispose();
    super.dispose();
  }

  void _move(double extent) {
    if (!_sheet.isAttached) return;
    _sheet.animateTo(extent,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: _background,
        body: SafeArea(child: LayoutBuilder(builder: (context, constraints) {
          final height = constraints.maxHeight;
          final minimum = (48 / height).clamp(.04, .16);
          final avatarHeight = math.min(330.0, height * .46);
          return Stack(children: [
            Positioned.fill(
                child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => _move(minimum),
              child: const DecoratedBox(
                  decoration: BoxDecoration(
                gradient: RadialGradient(
                    center: Alignment(0, .2),
                    radius: .85,
                    colors: [Color(0xFF443057), _background]),
              )),
            )),
            Positioned(
                top: height * .12,
                left: 0,
                right: 0,
                height: avatarHeight,
                child: const Center(
                    child: SizedBox(width: 230, child: HomeAvatar()))),
            Positioned(
                top: 12,
                left: 12,
                right: 20,
                child: Row(children: [
                  IconButton(
                      tooltip: 'กลับ',
                      onPressed: () => Navigator.maybePop(context),
                      icon: const Icon(Icons.arrow_back_rounded)),
                  const SizedBox(width: 8),
                  Text('แต่งตัว', style: AppText.heading(size: 22)),
                  const Spacer(),
                  const Icon(Icons.checkroom_outlined,
                      color: AppColors.purple2),
                ])),
            DraggableScrollableSheet(
              controller: _sheet,
              initialChildSize: _middle,
              minChildSize: minimum,
              maxChildSize: _maximum,
              snap: true,
              snapSizes: const [_middle],
              builder: (context, scrollController) => Material(
                color: _panel,
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(28)),
                clipBehavior: Clip.antiAlias,
                child: Column(children: [
                  Semantics(
                    button: true,
                    label: 'เปิดหรือขยายแผงเครื่องแต่งกาย',
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () => _move(_sheet.size < _middle - .02
                          ? _middle
                          : _sheet.size < _maximum - .02
                              ? _maximum
                              : _middle),
                      onVerticalDragUpdate: (details) => _sheet.jumpTo(
                          (_sheet.size - details.delta.dy / height)
                              .clamp(minimum, _maximum)),
                      onVerticalDragEnd: (details) {
                        final stops = [minimum, _middle, _maximum];
                        final current = _sheet.size;
                        final velocity = details.primaryVelocity ?? 0;
                        if (velocity.abs() > 250) {
                          final next = stops.where((stop) => velocity < 0
                              ? stop > current + .01
                              : stop < current - .01);
                          _move(next.isEmpty
                              ? (velocity < 0 ? _maximum : minimum)
                              : velocity < 0
                                  ? next.first
                                  : next.last);
                        } else {
                          stops.sort((a, b) => (a - current)
                              .abs()
                              .compareTo((b - current).abs()));
                          _move(stops.first);
                        }
                      },
                      child: SizedBox(
                          height: 48,
                          width: double.infinity,
                          child: Center(
                              child: Container(
                                  width: 36,
                                  height: 4,
                                  decoration: BoxDecoration(
                                      color: const Color(0xFF80708F),
                                      borderRadius:
                                          BorderRadius.circular(4))))),
                    ),
                  ),
                  Expanded(
                      child: ListView(
                    controller: scrollController,
                    padding: const EdgeInsets.fromLTRB(24, 0, 24, 32),
                    children: [
                      Text('เครื่องแต่งกาย', style: AppText.heading(size: 20)),
                      const SizedBox(height: 8),
                      Text('เสื้อผ้าและไอเทมของคุณ',
                          style: AppText.body(
                              size: 13, color: AppColors.textSecondary)),
                      const SizedBox(height: 32),
                      const Icon(Icons.checkroom_outlined,
                          size: 36, color: AppColors.textTertiary),
                      const SizedBox(height: 12),
                      Text('เร็ว ๆ นี้',
                          textAlign: TextAlign.center,
                          style: AppText.heading(
                              size: 16, color: AppColors.textSecondary)),
                      const SizedBox(height: 6),
                      Text('เครื่องแต่งกายจะปรากฏที่นี่เมื่อเปิดใช้งาน',
                          textAlign: TextAlign.center,
                          style: AppText.body(
                              size: 12, color: AppColors.textSecondary)),
                    ],
                  )),
                ]),
              ),
            ),
          ]);
        })),
      );
}
