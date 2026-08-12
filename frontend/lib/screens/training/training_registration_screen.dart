import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app_theme.dart';
import '../../providers/onboarding_provider.dart';
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
    final distanceGoal = ref.watch(onboardingProvider).data.distanceGoal;
    Map<String, dynamic>? template;
    for (final candidate in program.templates) {
      if (candidate['level'] == program.selectedTemplateLevel) {
        template = candidate;
        break;
      }
    }
    template ??= program.registrationTemplate;
    final selectedLevel = template?['level']?.toString();
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
                    templates: program.templates,
                    recommendedTemplate: program.registrationTemplate,
                    distanceGoal: distanceGoal,
                    loading: program.isLoadingTemplates,
                    onRetry: () => ref.read(programProvider).loadTemplates(),
                    onTemplateSelected: (selected) => ref
                        .read(programProvider)
                        .selectTemplate(selected['level']?.toString() ?? ''),
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
                  onTap: program.isRegistering || isLoading || selectedLevel == null
                      ? null
                      : () async {
                          // API 5.1 creates and persists the user's program.
                          final ok = await ref
                              .read(programProvider)
                              .registerPlan(level: selectedLevel);
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

class _TemplateContent extends StatefulWidget {
  const _TemplateContent({
    required this.templates,
    required this.recommendedTemplate,
    required this.distanceGoal,
    required this.loading,
    required this.onRetry,
    required this.onTemplateSelected,
  });

  final List<Map<String, dynamic>> templates;
  final Map<String, dynamic>? recommendedTemplate;
  final String? distanceGoal;
  final bool loading;
  final VoidCallback onRetry;
  final ValueChanged<Map<String, dynamic>> onTemplateSelected;

  @override
  State<_TemplateContent> createState() => _TemplateContentState();
}

class _TemplateContentState extends State<_TemplateContent> {
  int? _selectedWeeks;
  Map<String, dynamic>? _selectedTemplate;

  @override
  void didUpdateWidget(covariant _TemplateContent oldWidget) {
    super.didUpdateWidget(oldWidget);
    final availableLevels = widget.templates
        .map((template) => template['level']?.toString())
        .toSet();
    if (_selectedTemplate == null ||
        !availableLevels.contains(_selectedTemplate!['level']?.toString())) {
      _selectedTemplate = widget.recommendedTemplate ??
          (widget.templates.isEmpty ? null : widget.templates.first);
    }
    final minWeeks = _weekValue(_selectedTemplate?['duration_weeks_min']);
    final maxWeeks =
        _weekValue(_selectedTemplate?['duration_weeks_max']) ?? minWeeks;
    if (minWeeks != null &&
        (_selectedWeeks == null ||
            _selectedWeeks! < minWeeks ||
            _selectedWeeks! > (maxWeeks ?? minWeeks))) {
      _selectedWeeks = minWeeks;
    }
  }

  @override
  Widget build(BuildContext context) {
    _selectedTemplate ??= widget.recommendedTemplate ??
        (widget.templates.isEmpty ? null : widget.templates.first);
    final template = _selectedTemplate;
    if (widget.loading && widget.templates.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (template == null) {
      return Center(
        child: TextButton.icon(
          onPressed: widget.onRetry,
          icon: const Icon(Icons.refresh),
          label: const Text('โหลดแผนฝึกอีกครั้ง'),
        ),
      );
    }

    final phases = _mapList(template['programPhases']);
    final sessionSpecs = _uniqueSessionSpecs(template['sessionTypeSpecs']);
    final minWeeks = _weekValue(template['duration_weeks_min']);
    final maxWeeks = _weekValue(template['duration_weeks_max']) ?? minWeeks;
    final weekOptions = minWeeks == null || maxWeeks == null
        ? const <int>[]
        : List<int>.generate(
            maxWeeks - minWeeks + 1,
            (index) => minWeeks + index,
          );
    final selectedWeeks = _selectedWeeks ?? minWeeks;
    final goalLabel =
        widget.distanceGoal ?? _goalLabel(template['goal_label']?.toString());

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SectionLabel(title: 'เลือกตารางซ้อม'),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: widget.templates
                .map((candidate) => SelectChip(
                      label: _templateGoalLabel(candidate['goal_label']?.toString()),
                      active: candidate['level'] == template['level'],
                      onTap: () => setState(() {
                        _selectedTemplate = candidate;
                        _selectedWeeks = _weekValue(candidate['duration_weeks_min']);
                        widget.onTemplateSelected(candidate);
                      }),
                    ))
                .toList(),
          ),
          const SizedBox(height: 16),
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
                    _LevelBadge(label: _levelLabel(template['level']?.toString())),
                    Text(
                      '$goalLabel · ${selectedWeeks ?? '-'} สัปดาห์',
                      style: AppText.heading(size: 14.5),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  template['description']?.toString() ?? '',
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
          /*const SectionLabel(title: 'ระยะและระยะเวลา'),
          Text(
            widget.distanceGoal == null
                ? 'ไม่พบเป้าหมายระยะจาก Onboarding'
                : 'เป้าหมายระยะจาก Onboarding',
            style: AppText.body(size: 12.5, color: AppColors.textSecondary),
          ),*/
          const SizedBox(height: 8),
          SelectChip(
            label: goalLabel,
            active: true,
            onTap: () {},
          ),
          const SizedBox(height: 18),
          Text(
            'เลือกระยะเวลา (ตัวอย่าง)',
            style: AppText.body(size: 12.5, color: AppColors.textSecondary),
          ),
          const SizedBox(height: 8),
          if (weekOptions.isEmpty)
            Text('ไม่พบช่วงสัปดาห์ของแผน',
                style: AppText.body(size: 12, color: AppColors.textSecondary))
          else
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: weekOptions
                  .map((weeks) => SelectChip(
                        label: '$weeks สัปดาห์',
                        active: selectedWeeks == weeks,
                        // API 5.1 does not accept a week duration. This is a
                        // local, mock selection for the registration UI only.
                        onTap: () => setState(() => _selectedWeeks = weeks),
                      ))
                  .toList(),
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

int? _weekValue(dynamic value) => switch (value) {
      int weeks when weeks > 0 => weeks,
      num weeks when weeks > 0 => weeks.toInt(),
      _ => int.tryParse(value?.toString() ?? ''),
    };

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

String _templateGoalLabel(String? goal) => switch (goal) {
      'sub_50' => '5K',
      '10k_sub_1.40' => '10K',
      '21k_sub_3.30' => 'Half Marathon',
      _ => _goalLabel(goal),
    };

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
