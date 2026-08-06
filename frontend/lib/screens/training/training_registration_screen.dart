import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app_theme.dart';
import '../../providers/program_provider.dart';
import '../../widgets/common.dart';

/// The lightweight registration view shown before a training program exists.
/// Its layout deliberately mirrors the plan summary in the supplied mockup.
class TrainingRegistrationScreen extends ConsumerStatefulWidget {
  const TrainingRegistrationScreen({super.key});

  @override
  ConsumerState<TrainingRegistrationScreen> createState() =>
      _TrainingRegistrationScreenState();
}

class _TrainingRegistrationScreenState
    extends ConsumerState<TrainingRegistrationScreen> {
  int _weeks = 10;

  @override
  Widget build(BuildContext context) {
    final program = ref.watch(programProvider);
    final isCheckingPlan = program.isLoading && !program.isRegistered;
    final phase = _weeks == 8 ? 'Base 2 • Build 2 • Peak 2' : 'Base 3 • Build 3 • Peak 2';

    return Scaffold(
      body: AppBackground(
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  RoundIconButton(
                    icon: Icons.arrow_back,
                    onTap: program.isRegistering ? null : () => Navigator.of(context).pop(),
                  ),
                  const SizedBox(width: 14),
                  Text('ลงทะเบียนตารางซ้อม', style: AppText.heading(size: 19)),
                ]),
                const SizedBox(height: 20),
                AppCard(
                  borderColor: AppColors.purple2.withOpacity(.35),
                  backgroundGradient: LinearGradient(
                    colors: [
                      AppColors.purple1.withOpacity(.16),
                      AppColors.purple2.withOpacity(.03),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Wrap(spacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
                        _LevelBadge(),
                        Text('เป้าหมาย 10K · Sub 1:40 · 8–10 สัปดาห์',
                            style: AppText.heading(size: 14.5)),
                      ]),
                      const SizedBox(height: 10),
                      Text(
                        'แผนนี้พาคุณไล่ระดับความหนักเป็นขั้นบันได แล้วค่อยผ่อนก่อนวันแข่งจริง',
                        style: AppText.body(size: 12.5, color: AppColors.textSecondary),
                      ),
                      const SizedBox(height: 12),
                      Wrap(spacing: 5, runSpacing: 6, children: const [
                        _PhasePill('1 Base'), _Arrow(), _PhasePill('2 Build'),
                        _Arrow(), _PhasePill('3 Peak'), _Arrow(),
                        _PhasePill('4.1 Taper'), _Arrow(), _PhasePill('4.2 Race'),
                      ]),
                    ],
                  ),
                ),
                const SectionLabel(title: 'แผนการฝึกของคุณ'),
                AppCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('ระยะเวลาแผนฝึก', style: AppText.body(
                        size: 11.5, weight: FontWeight.w600, color: AppColors.textSecondary)),
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 8,
                        children: [8, 9, 10].map((weeks) => SelectChip(
                          label: '$weeks สัปดาห์', active: _weeks == weeks,
                          onTap: program.isRegistering ? () {} : () => setState(() => _weeks = weeks),
                        )).toList(),
                      ),
                      const SizedBox(height: 12),
                      Text('$phase → Taper → Race',
                          style: AppText.body(size: 12, color: AppColors.textSecondary)),
                      const SizedBox(height: 20),
                      Text('องค์ประกอบการซ้อม — Base', style: AppText.body(
                        size: 11.5, weight: FontWeight.w600, color: AppColors.textSecondary)),
                      const SizedBox(height: 10),
                      const _WorkoutRow(icon: '🏃', title: 'Easy Run', detail: '30–40 นาที · Zone 2', count: '2 วัน', color: AppColors.green1),
                      const SizedBox(height: 10),
                      const _WorkoutRow(icon: '⚡', title: 'VO2Max (Interval)', detail: '400 m × 4 เที่ยว · พักวิ่งฟื้น', count: '1 วัน', color: AppColors.gold1),
                      const SizedBox(height: 10),
                      const _WorkoutRow(icon: '🌄', title: 'Long Run', detail: '6–8 กม. · เป้าหมาย Sub 1:40', count: '1 วัน', color: AppColors.purple2),
                    ],
                  ),
                ),
                const Spacer(),
                if (program.errorMessage != null) ...[
                  Text(program.errorMessage!, style: AppText.body(size: 12, color: AppColors.red1)),
                  const SizedBox(height: 10),
                ],
                GradientButton(
                  label: program.isRegistering ? 'กำลังลงทะเบียน...' : 'บันทึกและลงทะเบียนตารางซ้อม',
                  gradient: AppColors.greenGradient,
                  loading: program.isRegistering || isCheckingPlan,
                  onTap: program.isRegistering || isCheckingPlan ? null : () async {
                    final ok = await ref.read(programProvider).registerPlan();
                    if (!context.mounted) return;
                    if (ok) {
                      Navigator.of(context).pop();
                    } else {
                      showAppToast(context, program.errorMessage ?? 'ลงทะเบียนไม่สำเร็จ กรุณาลองใหม่');
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

class _LevelBadge extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
    decoration: BoxDecoration(gradient: AppColors.purpleGradient, borderRadius: BorderRadius.circular(999)),
    child: Text('Intermediate', style: AppText.heading(size: 11.5, color: Colors.white)),
  );
}

class _PhasePill extends StatelessWidget {
  final String label;
  const _PhasePill(this.label);
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
    decoration: BoxDecoration(color: Colors.white.withOpacity(.08), borderRadius: BorderRadius.circular(999)),
    child: Text(label, style: AppText.heading(size: 10.5)),
  );
}

class _Arrow extends StatelessWidget {
  const _Arrow();
  @override
  Widget build(BuildContext context) => Text('→', style: AppText.body(size: 11, color: AppColors.textTertiary));
}

class _WorkoutRow extends StatelessWidget {
  final String icon, title, detail, count;
  final Color color;
  const _WorkoutRow({required this.icon, required this.title, required this.detail, required this.count, required this.color});
  @override
  Widget build(BuildContext context) => Row(children: [
    Container(width: 42, height: 42, alignment: Alignment.center,
      decoration: BoxDecoration(color: color.withOpacity(.14), border: Border.all(color: color.withOpacity(.6)), borderRadius: BorderRadius.circular(12)),
      child: Text(icon, style: const TextStyle(fontSize: 18))),
    const SizedBox(width: 12),
    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(title, style: AppText.heading(size: 14)),
      Text(detail, style: AppText.body(size: 11.5, color: AppColors.textSecondary)),
    ])),
    Container(padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
      decoration: BoxDecoration(color: Colors.white.withOpacity(.07), borderRadius: BorderRadius.circular(999)),
      child: Text(count, style: AppText.heading(size: 11.5))),
  ]);
}
