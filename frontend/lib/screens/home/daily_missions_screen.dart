import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../app_theme.dart';
import '../../providers/mission_provider.dart';
import '../../providers/user_provider.dart';
import '../../widgets/common.dart';
import '../wellness/daily_wellness_screen.dart';

class DailyMissionsScreen extends ConsumerWidget {
  const DailyMissionsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final missionNotifier = ref.read(missionProvider);
    final missions = ref.watch(missionProvider).missions;
    final total = missions.length;
    final done = missions.where((m) => m.done).length;

    return Scaffold(
      body: AppBackground(
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  RoundIconButton(icon: Icons.arrow_back, onTap: () => Navigator.of(context).pop()),
                  const SizedBox(width: 14),
                  Text('ภารกิจประจำวัน', style: AppText.heading(size: 19)),
                ]),
                const SizedBox(height: 6),
                Padding(
                  padding: const EdgeInsets.only(left: 52),
                  child: Text('วันนี้', style: AppText.body(size: 12.5, color: AppColors.textSecondary)),
                ),
                const SizedBox(height: 22),
                Text('ต้องทำวันนี้', style: AppText.body(size: 12.5, color: AppColors.textSecondary)),
                const SizedBox(height: 12),
                Expanded(
                  child: ListView.separated(
                    itemCount: missions.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 12),
                    itemBuilder: (context, i) {
                      final m = missions[i];
                      return GestureDetector(
                        onTap: () {
                          if (m.done) return;
                          if (m.id == 'wellness') {
                            Navigator.of(context)
                                .push(MaterialPageRoute(builder: (_) => const DailyWellnessScreen()));
                            return;
                          }
                          missionNotifier.setDone(m.id, true);
                          ref.read(userProvider).addReward(coin: m.coinReward);
                        },
                        child: AppCard(
                          borderColor: m.done ? AppColors.green1.withOpacity(.4) : AppColors.border,
                          child: Row(
                            children: [
                              Container(
                                width: 44,
                                height: 44,
                                alignment: Alignment.center,
                                decoration: BoxDecoration(
                                  color: Colors.white.withOpacity(.05),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Text(m.icon, style: const TextStyle(fontSize: 19)),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(m.title, style: AppText.heading(size: 14.5)),
                                    const SizedBox(height: 2),
                                    Text(m.subtitle, style: AppText.body(size: 12, color: AppColors.textSecondary)),
                                  ],
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                decoration: BoxDecoration(
                                  color: m.done ? AppColors.green1.withOpacity(.15) : Colors.white.withOpacity(.06),
                                  borderRadius: BorderRadius.circular(999),
                                ),
                                child: Text(
                                  m.done ? '✓ สำเร็จ' : '+${m.coinReward} 🌙',
                                  style: AppText.heading(
                                      size: 12, color: m.done ? AppColors.green2 : AppColors.gold1),
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 6),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('ความคืบหน้า', style: AppText.body(size: 12.5, color: AppColors.textSecondary)),
                    Text('$done / $total', style: AppText.heading(size: 13)),
                  ],
                ),
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(999),
                  child: LinearProgressIndicator(
                    value: total == 0 ? 0 : done / total,
                    minHeight: 8,
                    backgroundColor: Colors.white.withOpacity(.07),
                    valueColor: AlwaysStoppedAnimation(AppColors.purple2),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
