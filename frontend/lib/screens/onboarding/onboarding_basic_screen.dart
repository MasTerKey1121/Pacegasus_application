import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../app_theme.dart';
import '../../providers/onboarding_provider.dart';
import '../../widgets/common.dart';
import 'onboarding_injury_screen.dart';

class OnboardingBasicScreen extends ConsumerWidget {
  const OnboardingBasicScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ob = ref.watch(onboardingProvider);

    return Scaffold(
      body: AppBackground(
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
            child: Column(
              children: [
                const OnboardingProgress(steps: 4, active: 1),
                const SizedBox(height: 26),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text('ข้อมูลพื้นฐาน', style: AppText.heading(size: 22)),
                ),
                const SizedBox(height: 4),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text('กรอกข้อมูลพื้นฐานของคุณ',
                      style: AppText.body(size: 13, color: AppColors.textSecondary)),
                ),
                Expanded(
                  child: SingleChildScrollView(
                    child: Padding(
                      padding: const EdgeInsets.only(top: 26),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('วันเกิด', style: AppText.body(size: 12.5, color: AppColors.textSecondary)),
                          const SizedBox(height: 8),
                          Row(children: [
                            Expanded(
                                child: _DateBox(
                                    hint: 'DD',
                                    onChanged: (v) => ref.read(onboardingProvider).update((d) => d.day = v))),
                            const SizedBox(width: 10),
                            Expanded(
                                child: _DateBox(
                                    hint: 'MM',
                                    onChanged: (v) => ref.read(onboardingProvider).update((d) => d.month = v))),
                            const SizedBox(width: 10),
                            Expanded(
                                flex: 2,
                                child: _DateBox(
                                    hint: 'YYYY',
                                    onChanged: (v) => ref.read(onboardingProvider).update((d) => d.year = v))),
                          ]),
                          const SizedBox(height: 22),
                          Text('เพศกำเนิด', style: AppText.body(size: 12.5, color: AppColors.textSecondary)),
                          const SizedBox(height: 8),
                          Row(children: [
                            Expanded(
                              child: _GenderBox(
                                label: 'ชาย',
                                selected: ob.data.gender == 'ชาย',
                                onTap: () => ref.read(onboardingProvider).update((d) => d.gender = 'ชาย'),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: _GenderBox(
                                label: 'หญิง',
                                selected: ob.data.gender == 'หญิง',
                                onTap: () => ref.read(onboardingProvider).update((d) => d.gender = 'หญิง'),
                              ),
                            ),
                          ]),
                          const SizedBox(height: 22),
                          Row(children: [
                            Expanded(
                              child: AppTextField(
                                label: 'น้ำหนัก (kg)',
                                hint: '00',
                                keyboardType: TextInputType.number,
                                onChanged: (v) => ref.read(onboardingProvider).update((d) => d.weightKg = v),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: AppTextField(
                                label: 'ส่วนสูง (cm)',
                                hint: '000',
                                keyboardType: TextInputType.number,
                                onChanged: (v) => ref.read(onboardingProvider).update((d) => d.heightCm = v),
                              ),
                            ),
                          ]),
                        ],
                      ),
                    ),
                  ),
                ),
                GradientButton(
                  label: 'ต่อไป',
                  onTap: () => Navigator.of(context)
                      .push(MaterialPageRoute(builder: (_) => const OnboardingInjuryScreen())),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _DateBox extends StatelessWidget {
  final String hint;
  final ValueChanged<String> onChanged;
  const _DateBox({required this.hint, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(.03),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: TextField(
        keyboardType: TextInputType.number,
        onChanged: onChanged,
        textAlign: TextAlign.center,
        style: AppText.body(size: 14.5),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: AppText.body(size: 14, color: AppColors.textTertiary),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(vertical: 16),
        ),
      ),
    );
  }
}

class _GenderBox extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _GenderBox({required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 52,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          gradient: selected ? AppColors.purpleGradient : null,
          color: selected ? null : Colors.white.withOpacity(.03),
          border: Border.all(color: selected ? Colors.transparent : AppColors.border),
        ),
        child: Text(label,
            style: AppText.heading(size: 14.5, color: selected ? Colors.white : AppColors.textSecondary)),
      ),
    );
  }
}
