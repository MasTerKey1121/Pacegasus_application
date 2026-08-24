import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../app_theme.dart';
import '../../providers/user_provider.dart';
import '../../providers/wellness_provider.dart';
import '../../providers/mission_provider.dart';
import '../../providers/program_provider.dart';
import '../../widgets/common.dart';
import '../wellness/daily_wellness_screen.dart';
import '../home/daily_missions_screen.dart';
import '../run/run_select_screen.dart';
import '../training/training_schedule_screen.dart';
import '../training/training_registration_screen.dart';


class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(userProvider);
    final wellness = ref.watch(wellnessProvider);
    final missions = ref.watch(missionProvider);
    final program = ref.watch(programProvider);
    final todayQuest = program.todayQuest;
    final scheduleActionLabel = !program.isRegistered
        ? 'ลงทะเบียนตารางซ้อม'
        : !program.isScheduleSaved
            ? 'จัดตารางซ้อมของฉัน'
            : 'แผนการซ้อมของฉัน';

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
          if (wellness.completedToday && program.isRegistered && program.isScheduleSaved)
            GradientButton(
              label: '▶ เริ่ม Session การวิ่ง',
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const RunTypeSelectScreen()),
              ),
            ),


          /* เผื่อเสริมหน้า test
          GradientButton(
              label: 'ดุหน้า test',
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => TermsConsentScreen(
                    email: 'demo@pacegasus.app',
                    displayName: user.username,
                  ),
                ),
              ),
          ),
          const SizedBox(height: 16),
*/

          GestureDetector(
            onTap: program.isLoading
                ? null
                : () {
                    if (!wellness.completedToday) {
                      showAppToast(context, 'กรุณาทำ Daily Wellness Check-in ก่อน');
                      return;
                    }
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => program.isRegistered
                            ? const TrainingScheduleScreen()
                            : const TrainingRegistrationScreen(),
                      ),
                    );
                  },
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
                        Text(scheduleActionLabel, style: AppText.heading(size: 14.5)),
                        const SizedBox(height: 2),
                        Text(user.goalLabel, style: AppText.body(size: 12, color: AppColors.textSecondary)),
                      ],
                    ),
                  ),
                  Icon(
                    Icons.chevron_right_rounded,
                    color: AppColors.textSecondary,
                  ),
                ],
              ),
            ),
          ),

          const SectionLabel(title: 'แผนวันนี้'),
          GestureDetector(
            onTap: () {
              if (!wellness.completedToday) {
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const DailyWellnessScreen()),
                );
              } else if (!program.isRegistered) {
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const TrainingRegistrationScreen()),
                );
              }
            },
            child: AppCard(
              child: Column(
                children: [
                Text(wellness.completedToday ? '🏃' : '🔒',
                    style: const TextStyle(fontSize: 30)),
                const SizedBox(height: 10),
                if (!wellness.completedToday) Text(
                  'ทำ Daily Wellness Check-in เพื่อปลดล็อค',
                  textAlign: TextAlign.center,
                  style: AppText.body(
                    size: 12.5,
                    weight: FontWeight.w600,
                    color: wellness.completedToday ? AppColors.textPrimary : AppColors.gold1,
                  ),
                ),
                if (wellness.completedToday && !program.isRegistered) ...[
                  const SizedBox(height: 6),
                  Text(
                    'ลงทะเบียนตารางซ้อม',
                    textAlign: TextAlign.center,
                    style: AppText.body(
                      size: 13,
                      weight: FontWeight.w600,
                      color: AppColors.purple2,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'เลือกแผนที่ต้องการก่อนเริ่มตารางซ้อม',
                    textAlign: TextAlign.center,
                    style: AppText.body(size: 12, color: AppColors.textSecondary),
                  ),
                ] else if (!program.isScheduleSaved) ...[
                  const SizedBox(height: 6),
                  Text(
                    'จัดตารางฝึกและบันทึกให้เรียบร้อยก่อน แผนวันนี้จึงจะแสดง',
                    textAlign: TextAlign.center,
                    style: AppText.body(size: 12, color: AppColors.textSecondary),
                  ),
                ] else if (todayQuest != null) ...[
                  const SizedBox(height: 6),
                  Text(
                    _todayQuestLabel(todayQuest),
                    textAlign: TextAlign.center,
                    style: AppText.body(
                      size: 12.5,
                      weight: FontWeight.w600,
                      color: AppColors.green2,
                    ),
                  ),
                ] else if (program.isLoading) ...[
                  const SizedBox(height: 6),
                  Text(
                    'กำลังโหลดเควสของวันนี้...',
                    style: AppText.body(size: 12, color: AppColors.textSecondary),
                  ),
                ] else ...[
                  const SizedBox(height: 6),
                  Text(
                    'วันนี้ไม่มีเควสในตารางฝึก',
                    style: AppText.body(size: 12, color: AppColors.textSecondary),
                  ),
                ],
                ],
              ),
            ),
          ),

          const SectionLabel(title: 'แผนสัปดาห์นี้'),
          if (program.isScheduleSaved && program.quests.isNotEmpty)
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: program.quests
                  .map(
                    (quest) => Container(
                      width: 104,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppColors.card,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: AppColors.border),
                      ),
                      child: Text(
                        _todayQuestLabel(quest),
                        style: AppText.body(size: 11.5),
                      ),
                    ),
                  )
                  .toList(),
            )
          else
            Text(
              !wellness.completedToday && !program.isScheduleSaved
                  ? 'ทำ Daily Wellness Check-in เพื่อดูเควสสัปดาห์นี้'
                  : !program.isRegistered
                      ? 'ลงทะเบียนตารางซ้อมเพื่อเริ่มแผนสัปดาห์นี้'
                      : !program.isScheduleSaved
                          ? 'จัดตารางฝึกและบันทึกให้เรียบร้อยก่อน'
                      :
                    'ยังไม่มีเควสสำหรับสัปดาห์นี้',
              style: AppText.body(size: 12, color: AppColors.textSecondary),
            ),
        ],
      ),
    );
  }
  String _todayQuestLabel(Map<String, dynamic> quest) {
    final type = (quest['session_type'] ?? 'run').toString();
    final value = quest['planned_value'];
    final unit = quest['unit'];
    final title = switch (type) {
      'easy' => 'Easy Run',
      'tempo' => 'Tempo Run',
      'vo2max' => 'VO2 Max',
      'long_run' => 'Long Run',
      _ => type,
    };
    final target = value == null ? '' : ' ${value}${unit == null ? '' : ' $unit'}';
    return '$title$target';
  }
}
