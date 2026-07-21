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
    final notifier = ref.read(wellnessProvider);
    final entry = ref.watch(wellnessProvider).entry;
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
                  borderColor: AppColors.gold1.withOpacity(.35),
                  backgroundGradient: LinearGradient(
                    colors: [AppColors.gold1.withOpacity(.12), AppColors.gold1.withOpacity(.02)],
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
                          value: entry.sleepQuality.toDouble(),
                          min: 0,
                          max: 10,
                          divisions: 10,
                          minCaption: 'แย่มาก',
                          maxCaption: 'ดีมาก',
                          onChanged: (v) => notifier.update((e) => e.sleepQuality = v.round()),
                        ),
                        const SizedBox(height: 18),
                        LabeledSlider(
                          label: 'จำนวนชั่วโมงนอน',
                          value: entry.sleepHours,
                          min: 0,
                          max: 12,
                          minCaption: '0',
                          maxCaption: '12 ชม.',
                          valueFormatter: (v) => '${v.round()}h',
                          onChanged: (v) => notifier.update((e) => e.sleepHours = v),
                        ),
                        const SizedBox(height: 18),
                        LabeledSlider(
                          label: 'ความเมื่อยล้ากล้ามเนื้อ',
                          value: entry.muscleFatigue.toDouble(),
                          min: 0,
                          max: 10,
                          divisions: 10,
                          minCaption: 'ไม่มี',
                          maxCaption: 'เมื่อยมาก',
                          onChanged: (v) => notifier.update((e) => e.muscleFatigue = v.round()),
                        ),
                        const SizedBox(height: 18),
                        LabeledSlider(
                          label: 'ระดับพลังกล้ามเนื้อ',
                          value: entry.musclePower.toDouble(),
                          min: 0,
                          max: 10,
                          divisions: 10,
                          minCaption: 'อ่อนแรง',
                          maxCaption: 'เต็มพลัง',
                          onChanged: (v) => notifier.update((e) => e.musclePower = v.round()),
                        ),
                        const SizedBox(height: 18),
                        LabeledSlider(
                          label: 'ระดับความเครียด',
                          value: entry.stressLevel.toDouble(),
                          min: 0,
                          max: 10,
                          divisions: 10,
                          minCaption: 'ผ่อนคลาย',
                          maxCaption: 'เครียดมาก',
                          onChanged: (v) => notifier.update((e) => e.stressLevel = v.round()),
                        ),
                      ],
                    ),
                  ),
                ),
                GradientButton(
                  label: 'บันทึก',
                  onTap: () {
                    notifier.markComplete();
                    ref.read(missionProvider).setDone('wellness', true);
                    ref.read(userProvider).addReward(coin: 10);
                    Navigator.of(context).pop();
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
