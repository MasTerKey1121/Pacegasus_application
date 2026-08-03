import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../app_theme.dart';
import '../../providers/onboarding_provider.dart';
import '../../widgets/common.dart';
import 'onboarding_injury_screen.dart';
import '../../services/onboarding_api.dart';
import '../../models/onboarding_data.dart';

bool isValidDateInput({required int? day, required int? month, required int? year}) {
  if (day == null || month == null || year == null) return false;
  if (day < 1 || month < 1 || month > 12 || year < 1900) return false;

  final firstDayOfMonth = DateTime(year, month, 1);
  final lastDayOfMonth = DateTime(year, month + 1, 0);
  return day <= lastDayOfMonth.day && day >= firstDayOfMonth.day;
}

class OnboardingBasicScreen extends ConsumerWidget {
  const OnboardingBasicScreen({super.key});

  bool _canProceed(OnboardingData d) {
    final day = int.tryParse(d.day);
    final month = int.tryParse(d.month);
    final year = int.tryParse(d.year);
    final weight = double.tryParse(d.weightKg);
    final height = double.tryParse(d.heightCm);
    final days = int.tryParse(d.runningDaysPerWeek);

    final currentYear = DateTime.now().year;

    return day != null &&
        month != null &&
        year != null &&
        isValidDateInput(day: day, month: month, year: year) &&
        year >= currentYear - 120 &&
        year <= currentYear &&
        weight != null &&
        weight > 0 &&
        height != null &&
        height > 0 &&
        days != null &&
        days >= 1 &&
        days <= 7;
  }

  Map<String, dynamic> _buildBody(OnboardingData d) {
    return {
      'dateOfBirth':
          '${d.year}-${d.month.padLeft(2, '0')}-${d.day.padLeft(2, '0')}',
      'gender': d.gender == 'ชาย' ? 'male' : 'female',
      'heightCm': double.parse(d.heightCm),
      'weightKg': double.parse(d.weightKg),
      'runningDaysPerWeek': int.parse(d.runningDaysPerWeek),
    };
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifier = ref.read(onboardingProvider);
    final ob = ref.watch(onboardingProvider);
    final data = ob.data;
    final canProceed = _canProceed(data) && !ob.isSubmitting;

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
                  child:
                      Text('ข้อมูลพื้นฐาน', style: AppText.heading(size: 22)),
                ),
                const SizedBox(height: 4),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text('กรอกข้อมูลพื้นฐานของคุณ',
                      style: AppText.body(
                          size: 13, color: AppColors.textSecondary)),
                ),
                Expanded(
                  child: SingleChildScrollView(
                    child: Padding(
                      padding: const EdgeInsets.only(top: 26),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('วันเกิด',
                              style: AppText.body(
                                  size: 12.5, color: AppColors.textSecondary)),
                          const SizedBox(height: 8),
                          Row(children: [
                            Expanded(
                                child: _DateBox(
                                    hint: 'DD',
                                    inputFormatters: [
                                      FilteringTextInputFormatter.digitsOnly,
                                      LengthLimitingTextInputFormatter(2),
                                    ],
                                    onChanged: (v) =>
                                        notifier.update((d) => d.day = v))),
                            const SizedBox(width: 10),
                            Expanded(
                                child: _DateBox(
                                    hint: 'MM',
                                    inputFormatters: [
                                      FilteringTextInputFormatter.digitsOnly,
                                      LengthLimitingTextInputFormatter(2),
                                    ],
                                    onChanged: (v) =>
                                        notifier.update((d) => d.month = v))),
                            const SizedBox(width: 10),
                            Expanded(
                                flex: 2,
                                child: _DateBox(
                                    hint: 'YYYY',
                                    inputFormatters: [
                                      FilteringTextInputFormatter.digitsOnly,
                                      LengthLimitingTextInputFormatter(4),
                                    ],
                                    onChanged: (v) =>
                                        notifier.update((d) => d.year = v))),
                          ]),
                          const SizedBox(height: 22),
                          Text('เพศกำเนิด',
                              style: AppText.body(
                                  size: 12.5, color: AppColors.textSecondary)),
                          const SizedBox(height: 8),
                          Row(children: [
                            Expanded(
                              child: _GenderBox(
                                label: 'ชาย',
                                selected: data.gender == 'ชาย',
                                onTap: () =>
                                    notifier.update((d) => d.gender = 'ชาย'),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: _GenderBox(
                                label: 'หญิง',
                                selected: data.gender == 'หญิง',
                                onTap: () =>
                                    notifier.update((d) => d.gender = 'หญิง'),
                              ),
                            ),
                          ]),
                          const SizedBox(height: 22),
                          Row(children: [
                            Expanded(
                              child: AppTextField(
                                label: 'น้ำหนัก (kg)',
                                hint: '00',
                                keyboardType:
                                    const TextInputType.numberWithOptions(
                                        decimal: true),
                                inputFormatters: [
                                  FilteringTextInputFormatter.allow(
                                      RegExp(r'^\d*\.?\d{0,1}')),
                                ],
                                onChanged: (v) =>
                                    notifier.update((d) => d.weightKg = v),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: AppTextField(
                                label: 'ส่วนสูง (cm)',
                                hint: '000',
                                keyboardType: TextInputType.number,
                                inputFormatters: [
                                  FilteringTextInputFormatter.digitsOnly,
                                ],
                                onChanged: (v) =>
                                    notifier.update((d) => d.heightCm = v),
                              ),
                            ),
                          ]),
                          const SizedBox(height: 22),
                          Row(children: [
                            Expanded(
                              child: AppTextField(
                                label: 'จำนวนวันที่วิ่ง/สัปดาห์',
                                hint: '1-7',
                                keyboardType: TextInputType.number,
                                inputFormatters: [
                                  FilteringTextInputFormatter.digitsOnly,
                                  LengthLimitingTextInputFormatter(1),
                                ],
                                onChanged: (v) => notifier
                                    .update((d) => d.runningDaysPerWeek = v),
                              ),
                            ),
                          ]),
                          if (ob.errorMessage != null) ...[
                            const SizedBox(height: 14),
                            Text(ob.errorMessage!,
                                style: AppText.body(
                                    size: 12.5, color: AppColors.red1)),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
                GradientButton(
                  label: ob.isSubmitting ? 'กำลังบันทึก...' : 'ต่อไป',
                  onTap: canProceed
                      ? () async {
                          final ok = await notifier.submitStep(
                            () => ref
                                .read(onboardingApiProvider)
                                .step1(_buildBody(data)),
                          );
                          if (ok && context.mounted) {
                            Navigator.of(context).push(MaterialPageRoute(
                                builder: (_) =>
                                    const OnboardingInjuryScreen()));
                          }
                        }
                      : null,
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
  final List<TextInputFormatter>? inputFormatters;

  const _DateBox({
    required this.hint,
    required this.onChanged,
    this.inputFormatters,
  });

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
        inputFormatters: inputFormatters,
        onChanged: onChanged,
        textAlign: TextAlign.center,
        style: AppText.body(size: 14.5),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: AppText.body(
            size: 14,
            color: AppColors.textTertiary,
          ),
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
  const _GenderBox(
      {required this.label, required this.selected, required this.onTap});

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
          border: Border.all(
              color: selected ? Colors.transparent : AppColors.border),
        ),
        child: Text(label,
            style: AppText.heading(
                size: 14.5,
                color: selected ? Colors.white : AppColors.textSecondary)),
      ),
    );
  }
}
