import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../app_theme.dart';
import '../../providers/user_provider.dart';
import '../../widgets/common.dart';

class StatsScreen extends ConsumerWidget {
  const StatsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(userProvider);

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 30),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('สถิติ', style: AppText.heading(size: 20)),
          const SizedBox(height: 4),
          Text('ภาพรวมการซ้อมของคุณ', style: AppText.body(size: 12.5, color: AppColors.textSecondary)),
          const SizedBox(height: 20),
          Row(children: [
            Expanded(child: _StatCard(value: user.totalKm.toStringAsFixed(1), label: 'กม.รวม')),
            const SizedBox(width: 10),
            Expanded(child: _StatCard(value: '${user.totalSessions}', label: 'Session')),
            const SizedBox(width: 10),
            Expanded(child: _StatCard(value: '${user.streak}', label: 'สตรีค')),
          ]),
          const SectionLabel(title: 'แนวโน้มระยะทาง'),
          AppCard(
            child: SizedBox(
              height: 140,
              child: Center(
                child: Text(
                  'ยังไม่มีข้อมูลกราฟ\nจะเริ่มแสดงเมื่อเชื่อมต่อ backend',
                  textAlign: TextAlign.center,
                  style: AppText.body(size: 12.5, color: AppColors.textTertiary),
                ),
              ),
            ),
          ),
          const SectionLabel(title: 'ประวัติการวิ่งล่าสุด'),
          AppCard(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: Text('ยังไม่มีประวัติการวิ่ง', style: AppText.body(size: 12.5, color: AppColors.textTertiary)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  final String value;
  final String label;
  const _StatCard({required this.value, required this.label});

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: const EdgeInsets.symmetric(vertical: 18),
      child: Column(children: [
        Text(value, style: AppText.heading(size: 20)),
        const SizedBox(height: 4),
        Text(label, style: AppText.body(size: 11.5, color: AppColors.textSecondary)),
      ]),
    );
  }
}
