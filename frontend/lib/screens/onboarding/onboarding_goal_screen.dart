import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../app_theme.dart';
import '../../providers/onboarding_provider.dart';
import '../../widgets/common.dart';
import 'onboarding_history_screen.dart';

const _goalOptions = [
  'วิ่งลดน้ำหนักทั่วไป',
  'วิ่ง 5K',
  'วิ่ง 10K',
  'Half Marathon',
  'Full Marathon',
  'ลดน้ำหนัก',
  'เพิ่มกล้ามเนื้อ',
  'ฝึกความอึด',
];

class OnboardingGoalScreen extends ConsumerWidget {
  const OnboardingGoalScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifier = ref.read(onboardingProvider);
    final ob = ref.watch(onboardingProvider);

    return Scaffold(
      body: AppBackground(
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
            child: Column(
              children: [
                Row(children: [
                  RoundIconButton(icon: Icons.arrow_back, onTap: () => Navigator.of(context).pop()),
                  const SizedBox(width: 12),
                  Expanded(child: OnboardingProgress(steps: 4, active: 3)),
                ]),
                const SizedBox(height: 22),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text('เป้าหมายการวิ่ง', style: AppText.heading(size: 20)),
                ),
                const SizedBox(height: 4),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text('คุณอยากเริ่มจากอะไรก่อนดี?',
                      style: AppText.body(size: 13, color: AppColors.textSecondary)),
                ),
                Expanded(
                  child: SingleChildScrollView(
                    child: Padding(
                      padding: const EdgeInsets.only(top: 22),
                      child: Wrap(
                        spacing: 10,
                        runSpacing: 10,
                        children: _goalOptions
                            .map((g) => MultiChip(
                                  label: g,
                                  selected: ob.data.goal == g,
                                  onTap: () => notifier.update((d) => d.goal = g),
                                ))
                            .toList(),
                      ),
                    ),
                  ),
                ),
                Row(children: [
                  Expanded(child: OutlineButton(label: 'ย้อนกลับ', onTap: () => Navigator.of(context).pop())),
                  const SizedBox(width: 12),
                  Expanded(
                    child: GradientButton(
                      label: 'ถัดไป',
                      onTap: () => Navigator.of(context)
                          .push(MaterialPageRoute(builder: (_) => const OnboardingHistoryScreen())),
                    ),
                  ),
                ]),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
