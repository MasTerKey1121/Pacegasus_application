import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app_theme.dart';
import '../../providers/program_provider.dart';
import '../../widgets/common.dart';

/// Shows the API 5.0 program template before the user creates a program with
/// API 5.1.
class TrainingRegistrationScreen extends ConsumerStatefulWidget {
  const TrainingRegistrationScreen({super.key});

  @override
  ConsumerState<TrainingRegistrationScreen> createState() =>
      _TrainingRegistrationScreenState();
}

class _TrainingRegistrationScreenState
    extends ConsumerState<TrainingRegistrationScreen> {
  @override
  void initState() {
    super.initState();
    Future.microtask(() => ref.read(programProvider).loadTemplates());
  }

  @override
  Widget build(BuildContext context) {
    final program = ref.watch(programProvider);
    final template = program.registrationTemplate;
    final isLoading = program.isLoadingTemplates ||
        (program.isLoading && !program.isRegistered);

    return Scaffold(
      body: AppBackground(
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
            child: Column(
              children: [
                Row(
                  children: [
                    RoundIconButton(
                      icon: Icons.arrow_back,
                      onTap: program.isRegistering
                          ? null
                          : () => Navigator.of(context).pop(),
                    ),
                    const SizedBox(width: 14),
                    Text('ลงทะเบียนตารางซ้อม', style: AppText.heading(size: 19)),
                  ],
                ),
                const SizedBox(height: 20),
                Expanded(
                  child: _TemplateContent(
                    template: template,
                    loading: program.isLoadingTemplates,
                    onRetry: () => ref.read(programProvider).loadTemplates(),
                  ),
                ),
                if (program.errorMessage != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    program.errorMessage!,
                    style: AppText.body(size: 12, color: AppColors.red1),
                    textAlign: TextAlign.center,
                  ),
                ],
                const SizedBox(height: 12),
                GradientButton(
                  label: program.isRegistering
                      ? 'กำลังลงทะเบียน...'
                      : 'บันทึกและลงทะเบียนตารางซ้อม',
                  gradient: AppColors.greenGradient,
                  loading: program.isRegistering || isLoading,
                  onTap: program.isRegistering || isLoading || template == null
                      ? null
                      : () async {
                          // API 5.1 creates and persists the user's program.
                          final ok = await ref
                              .read(programProvider)
                              .registerPlan();
                          if (!context.mounted) return;
                          if (ok) {
                            Navigator.of(context).pop();
                          } else {
                            showAppToast(
                              context,
                              program.errorMessage ?? 'ลงทะเบียนไม่สำเร็จ กรุณาลองใหม่',
                            );
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

class _TemplateContent extends StatelessWidget {
  const _TemplateContent({
    required this.template,
    required this.loading,
    required this.onRetry,
  });

  final Map<String, dynamic>? template;
  final bool loading;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    if (loading && template == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (template == null) {
      return Center(
        child: TextButton.icon(
          onPressed: onRetry,
          icon: const Icon(Icons.refresh),
          label: const Text('โหลดแผนฝึกอีกครั้ง'),
        ),
      );
    }

    final phases = _mapList(template!['programPhases']);
    final sessionSpecs = _uniqueSessionSpecs(template!['sessionTypeSpecs']);
    final minWeeks = template!['duration_weeks_min']?.toString() ?? '-';
    final maxWeeks = template!['duration_weeks_max']?.toString() ?? minWeeks;

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
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
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    _LevelBadge(label: _levelLabel(template!['level']?.toString())),
                    Text(
                      '${_goalLabel(template!['goal_label']?.toString())} · $minWeeks–$maxWeeks สัปดาห์',
                      style: AppText.heading(size: 14.5),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  template!['description']?.toString() ?? '',
                  style: AppText.body(size: 12.5, color: AppColors.textSecondary),
                ),
                if (phases.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: phases
                        .map((phase) => _PhasePill(_phaseLabel(
                              phase['phase_code']?.toString(),
                            )))
                        .toList(),
                  ),
                ],
              ],
            ),
          ),
          const SectionLabel(title: 'องค์ประกอบการซ้อม'),
          if (sessionSpecs.isEmpty)
            Text('ไม่พบรายละเอียดรูปแบบการฝึก',
                style: AppText.body(size: 12, color: AppColors.textSecondary))
          else
            ...sessionSpecs.map((spec) => Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: _WorkoutRow(
                    icon: _sessionIcon(spec['session_type']?.toString()),
                    title: _sessionLabel(spec['session_type']?.toString()),
                    detail: _specDetail(spec),
                    count: '${spec['weekly_cap'] ?? 0} วัน/สัปดาห์',
                    color: _sessionColor(spec['session_type']?.toString()),
                  ),
                )),
        ],
      ),
    );
  }
}

class _LevelBadge extends StatelessWidget {
  const _LevelBadge({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
        decoration: BoxDecoration(
          gradient: AppColors.purpleGradient,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(label, style: AppText.heading(size: 11.5, color: Colors.white)),
      );
}

class _PhasePill extends StatelessWidget {
  const _PhasePill(this.label);

  final String label;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(.08),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(label, style: AppText.heading(size: 10.5)),
      );
}

class _WorkoutRow extends StatelessWidget {
  const _WorkoutRow({
    required this.icon,
    required this.title,
    required this.detail,
    required this.count,
    required this.color,
  });

  final String icon;
  final String title;
  final String detail;
  final String count;
  final Color color;

  @override
  Widget build(BuildContext context) => AppCard(
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: color.withOpacity(.14),
                border: Border.all(color: color.withOpacity(.6)),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(icon, style: const TextStyle(fontSize: 18)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: AppText.heading(size: 14)),
                  Text(detail,
                      style: AppText.body(size: 11.5, color: AppColors.textSecondary)),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Text(count, style: AppText.heading(size: 10.5)),
          ],
        ),
      );
}

List<Map<String, dynamic>> _mapList(dynamic value) => (value as List<dynamic>? ?? const [])
    .whereType<Map>()
    .map((item) => Map<String, dynamic>.from(item))
    .toList(growable: false);

List<Map<String, dynamic>> _uniqueSessionSpecs(dynamic value) {
  final seen = <String>{};
  return _mapList(value)
      .where((spec) => seen.add(spec['session_type']?.toString() ?? ''))
      .toList(growable: false);
}

String _levelLabel(String? level) => switch (level) {
      'beginner' => 'Beginner',
      'lower_intermediate' => 'Intermediate',
      'upper_intermediate' => 'Advanced',
      _ => level ?? 'Training plan',
    };

String _goalLabel(String? goal) => (goal ?? 'Training plan').replaceAll('_', ' ').toUpperCase();

String _phaseLabel(String? phase) => (phase ?? '').replaceAll('_', ' ').toUpperCase();

String _sessionLabel(String? type) => switch (type) {
      'easy' => 'Easy Run',
      'long_run' => 'Long Run',
      'tempo' => 'Tempo Run',
      'vo2max' => 'VO₂Max Interval',
      'threshold' => 'Threshold',
      _ => type ?? 'Training',
    };

String _sessionIcon(String? type) => switch (type) {
      'easy' => '🏃',
      'long_run' => '🌄',
      'tempo' => '⚡',
      'vo2max' => '🎯',
      'threshold' => '🔥',
      _ => '🏃',
    };

Color _sessionColor(String? type) => switch (type) {
      'easy' => AppColors.green1,
      'long_run' => AppColors.purple2,
      'tempo' || 'vo2max' || 'threshold' => AppColors.gold1,
      _ => AppColors.purple2,
    };

String _specDetail(Map<String, dynamic> spec) {
  final low = spec['value_low'];
  final high = spec['value_high'];
  final unit = spec['unit']?.toString() ?? '';
  final range = low == high || high == null ? '$low' : '$low–$high';
  return '$range $unit';
}
