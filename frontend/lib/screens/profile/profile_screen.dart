import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../app_theme.dart';
import '../../providers/user_provider.dart';
import '../../widgets/common.dart';

const _badges = [
  ('🥇', 'นักวิ่งใหม่', true),
  ('⚡', 'Streak 3', true),
  ('🏃', '10K run', false),
  ('🎯', 'Goal', false),
];

class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(userProvider);
    final earned = _badges.where((b) => b.$3).length;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 30),
      child: Column(
        children: [
          Align(alignment: Alignment.centerLeft, child: Text('Profile', style: AppText.heading(size: 19))),
          const SizedBox(height: 20),
          Container(
            width: 96,
            height: 96,
            decoration: BoxDecoration(shape: BoxShape.circle, gradient: AppColors.purpleGradient),
            alignment: Alignment.center,
            child: const Text('🙂', style: TextStyle(fontSize: 40)),
          ),
          const SizedBox(height: 14),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(user.username, style: AppText.heading(size: 18)),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(gradient: AppColors.purpleGradient, borderRadius: BorderRadius.circular(999)),
                child: Text('Lv.${user.level}', style: AppText.heading(size: 11, color: Colors.white)),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text('เป้าหมาย: ${user.goalLabel} ✏️', style: AppText.body(size: 13, color: AppColors.purple2)),
          const SizedBox(height: 4),
          Text('"วิ่งทุกวัน กว่าจะไปถึงเป้าหมาย" ✏️',
              style: AppText.body(size: 12.5, color: AppColors.textSecondary, weight: FontWeight.w500)),
          const SizedBox(height: 22),
          Row(children: [
            Expanded(child: _StatBox(value: user.totalKm.toStringAsFixed(0), label: 'กม.รวม')),
            const SizedBox(width: 10),
            Expanded(child: _StatBox(value: '${user.totalSessions}', label: 'session')),
            const SizedBox(width: 10),
            Expanded(child: _StatBox(value: '${user.streak}', label: 'สตรีค')),
          ]),
          const SectionLabel(title: 'BADGE สำคัญ'),
          GridView.count(
            crossAxisCount: 4,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 10,
            crossAxisSpacing: 10,
            children: _badges.map((b) {
              final (icon, label, unlocked) = b;
              return Opacity(
                opacity: unlocked ? 1 : .35,
                child: Column(
                  children: [
                    Container(
                      width: 54,
                      height: 54,
                      decoration: BoxDecoration(color: AppColors.card, shape: BoxShape.circle, border: Border.all(color: AppColors.border)),
                      alignment: Alignment.center,
                      child: Text(icon, style: const TextStyle(fontSize: 22)),
                    ),
                    const SizedBox(height: 6),
                    Text(label, style: AppText.body(size: 10.5, color: AppColors.textSecondary), textAlign: TextAlign.center),
                  ],
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 10),
          Text('ครบแล้ว $earned / ${_badges.length} badge', style: AppText.body(size: 12, color: AppColors.textSecondary)),
        ],
      ),
    );
  }
}

class _StatBox extends StatelessWidget {
  final String value;
  final String label;
  const _StatBox({required this.value, required this.label});

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Column(children: [
        Text(value, style: AppText.heading(size: 20)),
        const SizedBox(height: 4),
        Text(label, style: AppText.body(size: 11.5, color: AppColors.textSecondary)),
      ]),
    );
  }
}
