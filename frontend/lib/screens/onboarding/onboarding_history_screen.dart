import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../app_theme.dart';
import '../../providers/onboarding_provider.dart';
import '../../widgets/common.dart';
import '../home/main_shell.dart';

const _experienceOptions = ['ไม่เคย', 'เคย 1-2 ครั้ง', 'เคยหลายครั้ง'];
const _durationOptions = ['น้อยกว่า 1 เดือน', '6-12 เดือน', '1-3 ปี', 'มากกว่า 3 ปี'];
const _distanceOptions = ['น้อยกว่า 5 km', '5-10 km', '10-21 km', '21-42 km', 'มากกว่า 42 km'];

class OnboardingHistoryScreen extends ConsumerWidget {
  const OnboardingHistoryScreen({super.key});

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
                  Expanded(child: OnboardingProgress(steps: 4, active: 4)),
                ]),
                const SizedBox(height: 22),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text('ประวัติการวิ่ง', style: AppText.heading(size: 20)),
                ),
                const SizedBox(height: 4),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text('ช่วยให้เราประเมินระดับของคุณได้แม่นยำ',
                      style: AppText.body(size: 13, color: AppColors.textSecondary)),
                ),
                Expanded(
                  child: SingleChildScrollView(
                    child: Padding(
                      padding: const EdgeInsets.only(top: 22),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('เคยซ้อมหรือแข่งมาก่อนไหม?',
                              style: AppText.body(size: 12.5, color: AppColors.textSecondary)),
                          const SizedBox(height: 10),
                          Wrap(
                            spacing: 10,
                            runSpacing: 10,
                            children: _experienceOptions
                                .map((o) => MultiChip(
                                      label: o,
                                      selected: ob.data.pastExperience == o,
                                      onTap: () => notifier.update((d) => d.pastExperience = o),
                                    ))
                                .toList(),
                          ),
                          const SizedBox(height: 24),
                          Text('เริ่มซ้อมมานานไหม?',
                              style: AppText.body(size: 12.5, color: AppColors.textSecondary)),
                          const SizedBox(height: 10),
                          Wrap(
                            spacing: 10,
                            runSpacing: 10,
                            children: _durationOptions
                                .map((o) => MultiChip(
                                      label: o,
                                      selected: ob.data.trainingDuration == o,
                                      onTap: () => notifier.update((d) => d.trainingDuration = o),
                                    ))
                                .toList(),
                          ),
                          const SizedBox(height: 24),
                          Text('วิ่งไกลสุดในสัปดาห์?',
                              style: AppText.body(size: 12.5, color: AppColors.textSecondary)),
                          const SizedBox(height: 10),
                          Wrap(
                            spacing: 10,
                            runSpacing: 10,
                            children: _distanceOptions
                                .map((o) => MultiChip(
                                      label: o,
                                      selected: ob.data.longestDistance == o,
                                      onTap: () => notifier.update((d) => d.longestDistance = o),
                                    ))
                                .toList(),
                          ),
                          const SizedBox(height: 26),
                          AppCard(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('สรุปให้เห็นก่อน', style: AppText.heading(size: 14)),
                                const SizedBox(height: 12),
                                _SummaryRow('ประสบการณ์', ob.data.pastExperience),
                                _SummaryRow('เป้าหมาย', ob.data.goal),
                                _SummaryRow('วิ่งไกลสุด', ob.data.longestDistance),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                GradientButton(
                  label: 'เริ่มใช้งาน ✓',
                  gradient: AppColors.greenGradient,
                  onTap: () {
                    Navigator.of(context).pushAndRemoveUntil(
                      MaterialPageRoute(builder: (_) => const MainShell()),
                      (route) => false,
                    );
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

class _SummaryRow extends StatelessWidget {
  final String label;
  final String value;
  const _SummaryRow(this.label, this.value);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: AppText.body(size: 13, color: AppColors.textSecondary)),
          Text(value, style: AppText.body(size: 13, weight: FontWeight.w600)),
        ],
      ),
    );
  }
}
