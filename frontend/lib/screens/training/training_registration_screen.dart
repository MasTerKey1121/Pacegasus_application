import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app_theme.dart';
import '../../providers/program_provider.dart';
import '../../widgets/common.dart';
import 'training_schedule_screen.dart';

/// Lets a user preview a plan before registering it.
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
    Map<String, dynamic>? template;
    for (final candidate in program.templates) {
      if (candidate['level'] == program.selectedTemplateLevel) {
        template = candidate;
        break;
      }
    }
    template ??= program.registrationTemplate;
    final selectedLevel = template?['level']?.toString();
    final isEligible = _canSelectTemplate(template, program.onboardingLevel);
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
                      : !isEligible
                          ? 'ระดับการวิ่งของคุณยังไม่ถึงสำหรับแผนนี้'
                          : 'บันทึกและลงทะเบียนตารางซ้อม',
                  gradient: isEligible ? AppColors.greenGradient : AppColors.goldGradient,
                  loading: program.isRegistering || isLoading,
                  onTap: program.isRegistering ||
                          isLoading ||
                          selectedLevel == null ||
                          !isEligible
                      ? null
                      : () async {
                          final ok = await ref
                              .read(programProvider)
                              .registerPlan(level: selectedLevel);
                          if (!context.mounted) return;
                          if (ok) {
                            Navigator.of(context).pushReplacement(
                              MaterialPageRoute(
                                builder: (_) => const TrainingScheduleScreen(),
                              ),
                            );
                          } else {
                            showAppToast(
                              context,
                              program.errorMessage ??
                                  'ลงทะเบียนไม่สำเร็จ กรุณาลองใหม่',
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
    required this.loading,
    required this.onRetry,
    required this.onTemplateSelected,
  });

  final List<Map<String, dynamic>> templates;
  final Map<String, dynamic>? recommendedTemplate;
  final bool loading;
  final VoidCallback onRetry;
  final ValueChanged<Map<String, dynamic>> onTemplateSelected;

  @override
  State<_TemplateContent> createState() => _TemplateContentState();
}

class _TemplateContentState extends State<_TemplateContent> {
  Map<String, dynamic>? _selectedTemplate;
  String? _selectedPhaseId;

  @override
  void didUpdateWidget(covariant _TemplateContent oldWidget) {
    super.didUpdateWidget(oldWidget);
    final levels = widget.templates.map((item) => item['level']?.toString()).toSet();
    if (_selectedTemplate == null || !levels.contains(_selectedTemplate!['level'])) {
      _selectedTemplate = widget.recommendedTemplate ??
          (widget.templates.isEmpty ? null : widget.templates.first);
    }
    _ensureSelectedPhase();
  }

  @override
  Widget build(BuildContext context) {
    _selectedTemplate ??= widget.recommendedTemplate ??
        (widget.templates.isEmpty ? null : widget.templates.first);
    _ensureSelectedPhase();
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
    final selectedPhase = phases.cast<Map<String, dynamic>?>().firstWhere(
          (phase) => phase?['id']?.toString() == _selectedPhaseId,
          orElse: () => null,
        );
    final sessionSpecs = _sessionSpecsForPhase(
      template['sessionTypeSpecs'],
      _selectedPhaseId,
    );
    final duration = _durationLabel(
      _weekValue(template['duration_weeks_min']),
      _weekValue(template['duration_weeks_max']),
    );

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
                        _selectedPhaseId = null;
                        _ensureSelectedPhase();
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
                Text(
                  '${_planName(template['goal_label']?.toString())} · $duration',
                  style: AppText.heading(size: 14.5),
                ),
                const SizedBox(height: 10),
                Text(
                  template['description']?.toString() ?? '',
                  style: AppText.body(size: 12.5, color: AppColors.textSecondary),
                ),
                if (phases.isNotEmpty) ...[
                  const SizedBox(height: 14),
                  Text('เลือก Phase', style: AppText.heading(size: 12.5)),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: phases
                        .map((phase) => SelectChip(
                              label: _phaseLabel(phase['phase_code']?.toString()),
                              active: phase['id']?.toString() == _selectedPhaseId,
                              onTap: () => setState(
                                () => _selectedPhaseId = phase['id']?.toString(),
                              ),
                            ))
                        .toList(),
                  ),
                ],
              ],
            ),
          ),
          const SectionLabel(title: 'องค์ประกอบการซ้อม'),
          if (selectedPhase != null) ...[
            Text(
              'รายละเอียดการซ้อมใน Phase ${_phaseLabel(selectedPhase['phase_code']?.toString())}',
              style: AppText.body(size: 12.5, color: AppColors.textSecondary),
            ),
            const SizedBox(height: 8),
          ],
          if (sessionSpecs.isEmpty)
            Text(
              'ไม่พบรายละเอียดรูปแบบการฝึกใน Phase นี้',
              style: AppText.body(size: 12, color: AppColors.textSecondary),
            )
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

  void _ensureSelectedPhase() {
    final phases = _mapList(_selectedTemplate?['programPhases']);
    if (phases.isEmpty) {
      _selectedPhaseId = null;
      return;
    }
    if (!phases.any((phase) => phase['id']?.toString() == _selectedPhaseId)) {
      _selectedPhaseId = phases.first['id']?.toString();
    }
  }
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

List<Map<String, dynamic>> _mapList(dynamic value) =>
    (value as List<dynamic>? ?? const [])
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList(growable: false);

int? _weekValue(dynamic value) => switch (value) {
      int weeks when weeks > 0 => weeks,
      num weeks when weeks > 0 => weeks.toInt(),
      _ => int.tryParse(value?.toString() ?? ''),
    };

List<Map<String, dynamic>> _sessionSpecsForPhase(dynamic value, String? phaseId) {
  final seen = <String>{};
  return _mapList(value)
      .where((spec) => spec['phase_id']?.toString() == phaseId)
      .where((spec) => seen.add(spec['session_type']?.toString() ?? ''))
      .toList(growable: false);
}

String _planName(String? goal) => switch (goal) {
      'sub_50' => '5K Sub 50',
      '10k_sub_1.40' => '10K Sub 1.40',
      '21k_sub_3.30' => 'Half Marathon Sub 3.30',
      _ => (goal ?? 'Training plan').replaceAll('_', ' ').toUpperCase(),
    };

String _templateGoalLabel(String? goal) => switch (goal) {
      'sub_50' => '5K',
      '10k_sub_1.40' => '10K',
      '21k_sub_3.30' => 'Half Marathon',
      _ => _planName(goal),
    };

String _durationLabel(int? minWeeks, int? maxWeeks) {
  if (minWeeks == null) return 'ไม่ระบุระยะเวลา';
  if (maxWeeks == null || maxWeeks == minWeeks) return '$minWeeks สัปดาห์';
  return '$minWeeks-$maxWeeks สัปดาห์';
}

String _phaseLabel(String? phase) => (phase ?? '').replaceAll('_', ' ').toUpperCase();

bool _canSelectTemplate(Map<String, dynamic>? template, String? userLevel) {
  if (template == null) return false;
  const ranks = {
    'beginner': 0,
    'intermediate': 1,
    'lower_intermediate': 1,
    'advanced': 2,
    'upper_intermediate': 2,
    'elite': 3,
  };
  final requiredRank = ranks[template['require_exp_level']?.toString()] ?? 0;
  final userRank = ranks[userLevel] ?? 0;
  return userRank >= requiredRank;
}

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
