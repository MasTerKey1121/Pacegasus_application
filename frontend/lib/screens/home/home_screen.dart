import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../app_theme.dart';
import '../../providers/user_provider.dart';
import '../../providers/wellness_provider.dart';
import '../../providers/mission_provider.dart';
import '../../widgets/common.dart';
import '../wellness/daily_wellness_screen.dart';
import '../home/daily_missions_screen.dart';
import '../run/run_session_screen.dart';
import '../training/training_schedule_screen.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(userProvider);
    final wellness = ref.watch(wellnessProvider);
    final missions = ref.watch(missionProvider);

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 30),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(user.username, style: AppText.heading(size: 19)),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: AppColors.card,
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: AppColors.border),
                ),
                child: Row(children: [
                  Text('${user.coin}', style: AppText.heading(size: 14, color: AppColors.gold1)),
                  const SizedBox(width: 6),
                  const Text('🌙', style: TextStyle(fontSize: 13)),
                ]),
              ),
            ],
          ),
          const SizedBox(height: 18),

          if (!wellness.completedToday)
            GestureDetector(
              onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const DailyWellnessScreen())),
              child: AppCard(
                borderColor: AppColors.green1.withOpacity(.35),
                backgroundGradient: LinearGradient(
                  colors: [AppColors.green1.withOpacity(.14), AppColors.green1.withOpacity(.02)],
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Daily Wellness Check-in',
                              style: AppText.heading(size: 15, color: AppColors.green2)),
                          const SizedBox(height: 4),
                          Text('ทำเพื่อรับ +500', style: AppText.body(size: 12.5, color: AppColors.textSecondary)),
                        ],
                      ),
                    ),
                    const Icon(Icons.play_arrow_rounded, color: Colors.white),
                  ],
                ),
              ),
            )
          else
            GestureDetector(
              onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const DailyMissionsScreen())),
              child: AppCard(
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('ภารกิจประจำวัน', style: AppText.heading(size: 15, color: AppColors.gold1)),
                          const SizedBox(height: 4),
                          Text('ทำครบแล้ว ${missions.doneCount} / ${missions.missions.length}',
                              style: AppText.body(size: 12.5, color: AppColors.textSecondary)),
                        ],
                      ),
                    ),
                    Icon(Icons.chevron_right_rounded, color: AppColors.textSecondary),
                  ],
                ),
              ),
            ),

          const SizedBox(height: 16),
          GradientButton(
            label: '▶ เริ่ม Session การวิ่ง',
            onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const RunSessionScreen())),
          ),

          const SizedBox(height: 16),
          GestureDetector(
            onTap: () =>
                Navigator.of(context).push(MaterialPageRoute(builder: (_) => const TrainingScheduleScreen())),
            child: AppCard(
              child: Row(
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: AppColors.purple1.withOpacity(.16),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppColors.purple2.withOpacity(.35)),
                    ),
                    alignment: Alignment.center,
                    child: const Text('📅', style: TextStyle(fontSize: 18)),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('ตารางซ้อมของฉัน', style: AppText.heading(size: 14.5)),
                        const SizedBox(height: 2),
                        Text(user.goalLabel, style: AppText.body(size: 12, color: AppColors.textSecondary)),
                      ],
                    ),
                  ),
                  Icon(Icons.chevron_right_rounded, color: AppColors.textSecondary),
                ],
              ),
            ),
          ),

          const SectionLabel(title: 'แผนวันนี้'),
          AppCard(
            child: Column(
              children: [
                Text(wellness.completedToday ? '🏃' : '🔒',
                    style: const TextStyle(fontSize: 30)),
                const SizedBox(height: 10),
                Text(
                  wellness.completedToday
                      ? 'Easy run 5 km · Zone 2 · ประมาณ 35 นาที'
                      : 'ทำ Daily Wellness Check-in เพื่อปลดล็อค',
                  textAlign: TextAlign.center,
                  style: AppText.body(
                    size: 12.5,
                    weight: FontWeight.w600,
                    color: wellness.completedToday ? AppColors.textPrimary : AppColors.gold1,
                  ),
                ),
              ],
            ),
          ),

          const SectionLabel(title: 'สัปดาห์นี้'),
          Row(
            children: List.generate(3, (i) {
              return Expanded(
                child: Container(
                  margin: EdgeInsets.only(right: i == 2 ? 0 : 10),
                  height: 90,
                  decoration: BoxDecoration(
                    color: AppColors.card,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: AppColors.border),
                  ),
                ),
              );
            }),
          ),
        ],
      ),
    );
  }
}
