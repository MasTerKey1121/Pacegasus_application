import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../app_theme.dart';
import '../../providers/wellness_provider.dart';
import '../../providers/user_provider.dart';
import '../../providers/mission_provider.dart';
import '../../widgets/common.dart';

class DailyWellnessScreen extends ConsumerWidget {
  const DailyWellnessScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(wellnessProvider);
    final notifier = ref.read(wellnessProvider);
    final entry = state.entry;
    final today = DateTime.now();

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
                  Text('Daily Wellness Check-in', style: AppText.heading(size: 17)),
                ]),
                const SizedBox(height: 18),
                AppCard(
                  borderColor: AppColors.gold1.withValues(alpha: 0.35),
                  backgroundGradient: LinearGradient(
                    colors: [AppColors.gold1.withValues(alpha: 0.12), AppColors.gold1.withValues(alpha: 0.02)],
                  ),
                  child: Row(
                    children: [
                      Text('ทำครบรับ +10 🌙', style: AppText.heading(size: 13.5, color: AppColors.gold1)),
                      const Spacer(),
                      Text('${today.day}/${today.month}/${today.year}',
                          style: AppText.body(size: 12, color: AppColors.textSecondary)),
                    ],
                  ),
                ),
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.only(top: 20),
                    child: Column(
                      children: [
                        LabeledSlider(
                          label: 'คุณภาพการนอน',
                          value: (entry.sleepQuality ?? 1).toDouble(),
                          min: 1,
                          max: 5,
                          divisions: 5,
                          minCaption: 'แย่มาก',
                          maxCaption: 'ดีมาก',
                          displayText: entry.sleepQuality == null ? '—' : null,
                          onChanged: (v) => notifier.update((e) => e.sleepQuality = v.round()),
                        ),
                        const SizedBox(height: 18),
                        LabeledSlider(
                          label: 'จำนวนชั่วโมงนอน',
                          value: entry.sleepHours ?? 1,
                          min: 1,
                          max: 12,
                          minCaption: '1',
                          maxCaption: '12 ชม.',
                          valueFormatter: (v) => '${v.round()}h',
                          displayText: entry.sleepHours == null ? '—' : null,
                          onChanged: (v) => notifier.update((e) => e.sleepHours = v),
                        ),
                        const SizedBox(height: 18),
                        LabeledSlider(
                          label: 'ความเมื่อยล้ากล้ามเนื้อ',
                          value: (entry.muscleSoreness ?? 1).toDouble(),
                          min: 1,
                          max: 5,
                          divisions: 5,
                          minCaption: 'ไม่มี',
                          maxCaption: 'เมื่อยมาก',
                          displayText: entry.muscleSoreness == null ? '—' : null,
                          onChanged: (v) => notifier.update((e) => e.muscleSoreness = v.round()),
                        ),
                        const SizedBox(height: 18),
                        LabeledSlider(
                          label: 'ระดับพลังกล้ามเนื้อ',
                          value: (entry.energyLevel ?? 1).toDouble(),
                          min: 1,
                          max: 5,
                          divisions: 5,
                          minCaption: 'อ่อนแรง',
                          maxCaption: 'เต็มพลัง',
                          displayText: entry.energyLevel == null ? '—' : null,
                          onChanged: (v) => notifier.update((e) => e.energyLevel = v.round()),
                        ),
                        const SizedBox(height: 18),
                        LabeledSlider(
                          label: 'ระดับความเครียด',
                          value: (entry.stressLevel ?? 1).toDouble(),
                          min: 1,
                          max: 5 ,
                          divisions: 5,
                          minCaption: 'ผ่อนคลาย',
                          maxCaption: 'เครียดมาก',
                          displayText: entry.stressLevel == null ? '—' : null,
                          onChanged: (v) => notifier.update((e) => e.stressLevel = v.round()),
                        ),
                        const SizedBox(height: 18),
                        LabeledSlider(
                          label: 'แรงจูงใจในการออกกำลังกาย',
                          value: (entry.motivation ?? 1).toDouble(),
                          min: 1,
                          max: 5,
                          divisions: 4,
                          minCaption: 'ไม่อยากทำเลย',
                          maxCaption: 'พร้อมมาก',
                          displayText: entry.motivation == null ? '—' : null,
                          onChanged: (v) => notifier.update((e) => e.motivation = v.round()),
                        ),
                      ],
                    ),
                  ),
                ),
                GradientButton(
                  label: state.isSaving ? 'กำลังบันทึก...' : 'บันทึก',
                  onTap: state.isSaving || !entry.isComplete
                      ? null
                      : () async {
                          final ok = await notifier.submit();
                          if (!context.mounted) return;

                          if (ok) {
                            ref.read(missionProvider).setDone('wellness', true);
                            ref.read(userProvider).addReward(coin: 10);
                            Navigator.of(context).pop();
                          } else {
                            showAppToast(context, state.errorMessage ?? 'บันทึกไม่สำเร็จ กรุณาลองใหม่');
                          }
                        },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
