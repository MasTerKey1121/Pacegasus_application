import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../app_theme.dart';
import '../../providers/onboarding_provider.dart';
import '../../services/onboarding_api.dart';
import '../../widgets/common.dart';
import 'onboarding_goal_screen.dart';
import '../../models/onboarding_data.dart';

const _conditionOptions = ['โรคหัวใจ', 'ความดันสูง', 'เบาหวาน', 'โรคหืดหอบ', 'ข้ออักเสบ'];
const _injuryOptions = ['เข่าซ้าย', 'เข่าขวา', 'ปวดหลัง', 'เอ็นร้อยหวาย', 'ข้อเท้าซ้าย', 'ข้อเท้าขวา'];

class OnboardingInjuryScreen extends ConsumerWidget {
  const OnboardingInjuryScreen({super.key});

  Map<String, dynamic> _buildBody(OnboardingData d) {
    final hasHistory = d.pastInjuries.isNotEmpty || d.currentInjuries.isNotEmpty;
    return {
      'hasInjuryHistory': hasHistory,
      'injuries': [
        ...d.pastInjuries.map((b) => {'bodyPart': b, 'isCurrent': false}),
        ...d.currentInjuries.map((b) => {'bodyPart': b, 'isCurrent': true}),
      ],
      // หมายเหตุ: d.conditions (โรคประจำตัว) API ไม่มีรองรับ เลยไม่ส่ง
    };
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifier = ref.read(onboardingProvider);
    final ob = ref.watch(onboardingProvider);
    final data = ob.data;

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
                  Expanded(child: OnboardingProgress(steps: 4, active: 2)),
                ]),
                const SizedBox(height: 22),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text('สุขภาพและอาการบาดเจ็บ', style: AppText.heading(size: 20)),
                ),
                Expanded(
                  child: SingleChildScrollView(
                    child: Padding(
                      padding: const EdgeInsets.only(top: 22),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('โรคประจำตัว (เลือกได้มากกว่า 1 ข้อ)',
                              style: AppText.body(size: 12.5, color: AppColors.textSecondary)),
                          const SizedBox(height: 12),
                          _MultiWrap(
                            options: _conditionOptions,
                            selected: data.conditions,
                            onToggle: (v) => notifier.update((d) {
                              d.conditions.contains(v) ? d.conditions.remove(v) : d.conditions.add(v);
                            }),
                            onClear: () => notifier.update((d) => d.conditions.clear()),
                          ),
                          const SizedBox(height: 30),
                          Text('อาการบาดเจ็บที่เคยเป็น (หากมีเลือกได้มากกว่า 1)',
                              style: AppText.body(size: 12.5, color: AppColors.textSecondary)),
                          const SizedBox(height: 12),
                          _MultiWrap(
                            options: _injuryOptions,
                            selected: data.pastInjuries,
                            onToggle: (v) => notifier.update((d) {
                              d.pastInjuries.contains(v) ? d.pastInjuries.remove(v) : d.pastInjuries.add(v);
                            }),
                            onClear: () => notifier.update((d) => d.pastInjuries.clear()),
                          ),
                          const SizedBox(height: 30),
                          Text('อาการบาดเจ็บในปัจจุบัน (หากมีเลือกได้มากกว่า 1)',
                              style: AppText.body(size: 12.5, color: AppColors.textSecondary)),
                          const SizedBox(height: 12),
                          _MultiWrap(
                            options: _injuryOptions,
                            selected: data.currentInjuries,
                            onToggle: (v) => notifier.update((d) {
                              d.currentInjuries.contains(v) ? d.currentInjuries.remove(v) : d.currentInjuries.add(v);
                            }),
                            onClear: () => notifier.update((d) => d.currentInjuries.clear()),
                          ),
                          if (ob.errorMessage != null) ...[
                            const SizedBox(height: 16),
                            Text(ob.errorMessage!, style: AppText.body(size: 12.5, color: AppColors.red1)),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
                Row(children: [
                  Expanded(child: OutlineButton(label: 'ย้อนกลับ', onTap: () => Navigator.of(context).pop())),
                  const SizedBox(width: 12),
                  Expanded(
                    child: GradientButton(
                      label: ob.isSubmitting ? 'กำลังบันทึก...' : 'ถัดไป',
                      onTap: ob.isSubmitting
                          ? null
                          : () async {
                              final ok = await notifier.submitStep(
                                () => ref.read(onboardingApiProvider).step2(_buildBody(data)),
                              );
                              if (ok && context.mounted) {
                                Navigator.of(context)
                                    .push(MaterialPageRoute(builder: (_) => const OnboardingGoalScreen()));
                              }
                            },
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

class _MultiWrap extends StatelessWidget {
  final List<String> options;
  final Set<String> selected;
  final ValueChanged<String> onToggle;
  final VoidCallback onClear;
  const _MultiWrap({
    required this.options,
    required this.selected,
    required this.onToggle,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        ...options.map((o) => MultiChip(label: o, selected: selected.contains(o), onTap: () => onToggle(o))),
        MultiChip(label: 'ไม่มี', selected: selected.isEmpty, onTap: onClear),
      ],
    );
  }
}