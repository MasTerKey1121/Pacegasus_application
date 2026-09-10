import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app_theme.dart';
import '../../models/training_models.dart';
import '../../providers/program_provider.dart';
import '../../providers/training_plan_provider.dart';
import '../../widgets/common.dart';
import '../home/main_shell.dart';

/// A week-by-week builder where the user chooses the training day for each
/// workout in the registered plan.
class TrainingScheduleScreen extends ConsumerStatefulWidget {
  const TrainingScheduleScreen({super.key});

  @override
  ConsumerState<TrainingScheduleScreen> createState() =>
      _TrainingScheduleScreenState();
}

class _TrainingScheduleScreenState
    extends ConsumerState<TrainingScheduleScreen> {
  String? _configuredTemplateLevel;

  @override
  void initState() {
    super.initState();
    Future.microtask(() => ref.read(programProvider).loadTemplates());
  }

  @override
  Widget build(BuildContext context) {
    final program = ref.watch(programProvider);
    final template = _selectedTemplate(program);
    _configurePlan(template);
    final plan = ref.watch(trainingPlanProvider);

    return Scaffold(
      body: AppBackground(
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    RoundIconButton(
                      icon: Icons.arrow_back,
                      onTap: () => Navigator.of(context).pop(),
                    ),
                    const SizedBox(width: 14),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('ลงตารางซ้อม', style: AppText.heading(size: 19)),
                        Text(
                          _planName(template?['goal_label']?.toString()),
                          style: AppText.body(
                            size: 11.5,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                if (program.isLoading)
                  const Expanded(
                      child: Center(child: CircularProgressIndicator()))
                else if (!program.isRegistered)
                  Expanded(
                    child: Center(
                      child: Text(
                        'กรุณาลงทะเบียนตารางซ้อมก่อน',
                        style: AppText.body(color: AppColors.textSecondary),
                      ),
                    ),
                  )
                else
                  Expanded(
                    child: _ScheduleBuilder(
                      template: template,
                      plan: plan,
                      startDate: program.programStartDate,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Map<String, dynamic>? _selectedTemplate(ProgramNotifier program) {
    for (final candidate in program.templates) {
      if (candidate['level'] == program.selectedTemplateLevel) return candidate;
    }
    return program.registrationTemplate;
  }

  void _configurePlan(Map<String, dynamic>? template) {
    final level = template?['level']?.toString();
    if (template == null || level == _configuredTemplateLevel) return;
    final min = _weekValue(template['duration_weeks_min']);
    final max = _weekValue(template['duration_weeks_max']);
    if (min == null || max == null || max < min) return;
    _configuredTemplateLevel = level;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      final plan = ref.read(trainingPlanProvider);
      plan.configurePlanDuration(
        minWeeks: min,
        maxWeeks: max,
        hasPhases: _mapList(template['programPhases']).isNotEmpty,
      );
      await _syncSavedSchedule(plan);
    });
  }

  /// Pulls every quest already saved for this program and rebuilds the local
  /// week grid + saved-week markers from it, so the builder resumes on the
  /// correct next week instead of guessing from in-memory state alone.
  Future<void> _syncSavedSchedule(TrainingPlanNotifier plan) async {
    final startDate = ref.read(programProvider).programStartDate;
    if (startDate == null) return;
    final quests = await ref.read(programProvider).loadQuestsRange(
          from: startDate,
          to: startDate.add(Duration(days: plan.planWeeks * 7 - 1)),
        );
    if (!mounted) return;
    plan.syncFromServer(startDate: startDate, quests: quests);
  }
}

/// Changing the plan length rebuilds the local week grid from scratch, so it
/// must be re-synced against the backend or already-saved weeks would look
/// unsaved (and re-saving them would collide with the weekly cap).
Future<void> _changePlanWeeks(WidgetRef ref, int weeks) async {
  ref.read(trainingPlanProvider).setPlanWeeks(weeks);
  final startDate = ref.read(programProvider).programStartDate;
  if (startDate == null) return;
  final quests = await ref.read(programProvider).loadQuestsRange(
        from: startDate,
        to: startDate.add(Duration(days: weeks * 7 - 1)),
      );
  ref
      .read(trainingPlanProvider)
      .syncFromServer(startDate: startDate, quests: quests);
}

class _ScheduleBuilder extends ConsumerWidget {
  const _ScheduleBuilder({
    required this.template,
    required this.plan,
    required this.startDate,
  });

  final Map<String, dynamic>? template;
  final TrainingPlanNotifier plan;
  final DateTime? startDate;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final phase = plan.getPhase(plan.currentWeek);
    final caps = plan.getCaps(plan.currentWeek);
    final workouts = caps.asMap.entries
        .where((entry) => plan.remainingFor(entry.key) > 0)
        .map((entry) => entry.key)
        .toList();
    final isCurrentWeekComplete = plan.isWeekComplete(plan.currentWeek);
    final isCurrentWeekSaved = plan.isWeekSaved(plan.currentWeek);
    final isCurrentWeekEditable =
        startDate != null && plan.isWeekEditable(plan.currentWeek, startDate!);
    final hasPhases = _mapList(template?['programPhases']).isNotEmpty;
    final progress =
        plan.planWeeks == 0 ? 0.0 : plan.overallDoneCount / plan.planWeeks;
    final duration = _durationLabel(
      _weekValue(template?['duration_weeks_min']),
      _weekValue(template?['duration_weeks_max']),
    );

    return SingleChildScrollView(
      padding: const EdgeInsets.only(bottom: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AppCard(
            padding: const EdgeInsets.all(15),
            borderColor: AppColors.purple2.withOpacity(.35),
            backgroundGradient: LinearGradient(
              colors: [
                AppColors.purple1.withOpacity(.20),
                AppColors.purple2.withOpacity(.05),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    _ExperienceBadge(level: template?['level']?.toString()),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        '${_experienceLabel(template?['level']?.toString())} $duration',
                        style: AppText.heading(size: 16),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  _planName(template?['goal_label']?.toString()),
                  style: AppText.body(size: 12, color: AppColors.textSecondary),
                ),
              ],
            ),
          ),
          if (!plan.hasSavedWeeks) ...[
            const SectionLabel(title: 'เลือกระยะเวลาฝึกของคุณ'),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: plan.availablePlanLengths
                  .map((weeks) => SelectChip(
                        label: '$weeks สัปดาห์',
                        active: plan.planWeeks == weeks,
                        onTap: () => _changePlanWeeks(ref, weeks),
                      ))
                  .toList(),
            ),
          ],
          if (hasPhases) ...[
            const SectionLabel(title: 'แผนการฝึกของคุณ'),
            Text(
              'เลือก Phase เพื่อข้ามไปดูและจัดตารางสัปดาห์ของ Phase นั้น',
              style: AppText.body(size: 12, color: AppColors.textSecondary),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: PlanPhase.values
                  .map((item) => _PhaseChip(
                        phase: item,
                        active: item == phase,
                        onTap: () => ref
                            .read(trainingPlanProvider)
                            .goToWeek(plan.phaseStartWeeks[item]!),
                      ))
                  .toList(),
            ),
          ],
          Padding(
            padding: const EdgeInsets.only(top: 26, bottom: 10),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('จัดตารางรายสัปดาห์', style: AppText.heading(size: 15)),
                const SizedBox(width: 2),
                IconButton(
                  tooltip: 'เพิ่มเติม',
                  onPressed: () => _showSchedulingRules(context),
                  icon: const Icon(Icons.info_outline_rounded, size: 20),
                  color: AppColors.purple2,
                ),
              ],
            ),
          ),
          Text(
            hasPhases
                ? 'สัปดาห์ที่ ${plan.currentWeek + 1} · ${phase.label}'
                : 'สัปดาห์ที่ ${plan.currentWeek + 1}',
            style: AppText.heading(size: 14),
          ),
          const SizedBox(height: 12),
          if (isCurrentWeekEditable && workouts.isNotEmpty)
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: workouts
                  .map((type) => _WorkoutChoice(
                        type: type,
                        count: plan.remainingFor(type),
                        selected: plan.selectedType == type,
                        onTap: () =>
                            ref.read(trainingPlanProvider).selectType(type),
                      ))
                  .toList(),
            ),
          const SizedBox(height: 16),
          Text(
            !isCurrentWeekEditable
                ? isCurrentWeekSaved
                    ? 'มีรายการที่เริ่มหรือทำเสร็จแล้ว จึงแก้ไขสัปดาห์นี้ไม่ได้'
                    : 'สัปดาห์ที่ผ่านมาแก้ไขไม่ได้'
                : isCurrentWeekSaved
                    ? 'แก้ไขได้เฉพาะรายการที่ยังไม่เริ่มทำ แล้วกดบันทึกการแก้ไข'
                    : plan.selectedType == null
                        ? 'เลือกการซ้อม แล้วแตะวันที่ต้องการลงตาราง'
                        : 'กำลังเลือก ${sessionMeta[plan.selectedType]!.label} แล้วแตะวันที่ว่าง',
            style: AppText.body(size: 12, color: AppColors.textSecondary),
          ),
          const SizedBox(height: 10),
          _WeekGrid(
            schedule: plan.currentWeekData,
            blockedDays: List<bool>.generate(
              7,
              plan.isBlockedForSelectedType,
            ),
            enabled: isCurrentWeekEditable,
            onTap: (day) {
              final error = ref.read(trainingPlanProvider).handleDayTap(day);
              if (error != null) showAppToast(context, error);
            },
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              NavArrowButton(
                icon: Icons.chevron_left_rounded,
                onTap: plan.currentWeek == 0
                    ? null
                    : () => ref.read(trainingPlanProvider).prevWeek(),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: GradientButton(
                  height: 46,
                  label: plan.currentWeek == plan.planWeeks - 1
                      ? 'สัปดาห์สุดท้าย'
                      : 'ไปสัปดาห์ที่ ${plan.currentWeek + 2}',
                  onTap: isCurrentWeekComplete &&
                          plan.currentWeek < plan.planWeeks - 1
                      ? () => ref.read(trainingPlanProvider).nextWeek()
                      : null,
                ),
              ),
              const SizedBox(width: 10),
              NavArrowButton(
                icon: Icons.chevron_right_rounded,
                onTap: plan.currentWeek == plan.planWeeks - 1
                    ? null
                    : () => ref.read(trainingPlanProvider).nextWeek(),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Text('ความคืบหน้าตารางฝึก', style: AppText.body(size: 12)),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(99),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 7,
              color: AppColors.purple2,
              backgroundColor: Colors.white.withOpacity(.08),
            ),
          ),
          const SizedBox(height: 5),
          Text(
            'จัดครบแล้ว ${plan.overallDoneCount} / ${plan.planWeeks} สัปดาห์',
            style: AppText.body(size: 11.5, color: AppColors.textSecondary),
          ),
          const SizedBox(height: 20),
          GradientButton(
            label: !isCurrentWeekEditable
                ? 'สัปดาห์นี้แก้ไขไม่ได้'
                : isCurrentWeekSaved
                    ? 'บันทึกการแก้ไขสัปดาห์นี้'
                    : 'บันทึกตารางสัปดาห์',
            loading: ref.watch(programProvider).isSavingSchedule,
            onTap: isCurrentWeekEditable && isCurrentWeekComplete
                ? () async {
                    final program = ref.read(programProvider);
                    final ok = isCurrentWeekSaved
                        ? await program.replaceManualScheduleWeek(
                            weekIndex: plan.currentWeek,
                            week: plan.currentWeekData,
                          )
                        : await program.saveManualScheduleWeek(
                            weekIndex: plan.currentWeek,
                            week: plan.currentWeekData,
                          );
                    if (!context.mounted) return;
                    if (ok) {
                      ref
                          .read(trainingPlanProvider)
                          .markWeekSaved(plan.currentWeek);
                      // The write has already succeeded. Leave this screen
                      // immediately; MainShell restores the fresh program data
                      // when Home is created.
                      Navigator.of(context).pushAndRemoveUntil(
                        MaterialPageRoute<void>(
                            builder: (_) => const MainShell()),
                        (route) => false,
                      );
                    } else {
                      showAppToast(
                        context,
                        ref.read(programProvider).errorMessage ??
                            'บันทึกตารางฝึกไม่สำเร็จ',
                      );
                    }
                  }
                : null,
          ),
        ],
      ),
    );
  }
}

void _showSchedulingRules(BuildContext context) {
  showDialog<void>(
    context: context,
    builder: (dialogContext) => Dialog(
      backgroundColor: AppColors.bg2,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24),
      child: AppCard(
        padding: const EdgeInsets.all(20),
        borderColor: AppColors.purple2.withOpacity(.4),
        backgroundGradient: const LinearGradient(
          colors: [AppColors.bg2, Color(0xFF211941)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.info_outline_rounded,
                    color: AppColors.purple2),
                const SizedBox(width: 8),
                Text('เพิ่มเติม', style: AppText.heading(size: 17)),
                const Spacer(),
                IconButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  icon: const Icon(Icons.close_rounded),
                  color: AppColors.textSecondary,
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'วิธีจัดตาราง\n'
              '1. เลือกรายการซ้อม แล้วแตะวันที่ว่างเพื่อวางรายการนั้น\n'
              '2. Interval, Tempo และ Long Run เป็นการซ้อมหนัก จึงห้ามวางติดกัน วันที่ที่ใช้ไม่ได้จะแสดงสีเทาเมื่อเลือกรายการซ้อมหนัก\n'
              '3. แตะรายการที่วางแล้วอีกครั้งเพื่อลบและจัดใหม่\n'
              '4. จัดให้ครบทุกประเภทก่อนกดไปสัปดาห์ถัดไป หรือบันทึกแผนทั้งหมด',
              style: AppText.body(size: 13, color: AppColors.textSecondary),
            ),
          ],
        ),
      ),
    ),
  );
}

class _PhaseChip extends StatelessWidget {
  const _PhaseChip(
      {required this.phase, required this.active, required this.onTap});

  final PlanPhase phase;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => SelectChip(
        label: '${phase.shortNumber} ${phase.label}',
        active: active,
        onTap: onTap,
      );
}

class _ExperienceBadge extends StatelessWidget {
  const _ExperienceBadge({required this.level});

  final String? level;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 11),
        decoration: BoxDecoration(
          gradient: AppColors.purpleGradient,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(
          _experienceBadgeLabel(level),
          style: AppText.heading(size: 13, color: Colors.white),
        ),
      );
}

class _WorkoutChoice extends StatelessWidget {
  const _WorkoutChoice({
    required this.type,
    required this.count,
    required this.selected,
    required this.onTap,
  });

  final SessionType type;
  final int count;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final meta = sessionMeta[type]!;
    return GestureDetector(
      onTap: onTap,
      onLongPress: () => _showWorkoutInfo(context, meta.label),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        width: 96,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 11),
        decoration: BoxDecoration(
          color: selected ? AppColors.purple1.withOpacity(.20) : AppColors.card,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected ? AppColors.purple2 : AppColors.border,
          ),
        ),
        child: Column(
          children: [
            Text(meta.icon, style: const TextStyle(fontSize: 18)),
            const SizedBox(height: 4),
            Text(meta.label,
                textAlign: TextAlign.center, style: AppText.heading(size: 10)),
            Text('เหลือ $count',
                style: AppText.body(size: 9.5, color: AppColors.textSecondary)),
          ],
        ),
      ),
    );
  }
}

void _showWorkoutInfo(BuildContext context, String title) {
  showDialog<void>(
    context: context,
    builder: (dialogContext) => Dialog(
      backgroundColor: AppColors.bg2,
      insetPadding: const EdgeInsets.symmetric(horizontal: 46),
      child: AppCard(
        padding: const EdgeInsets.all(20),
        backgroundGradient: const LinearGradient(
          colors: [AppColors.bg2, Color(0xFF211941)],
        ),
        child: Row(
          children: [
            const Icon(Icons.fitness_center_rounded, color: AppColors.purple2),
            const SizedBox(width: 10),
            Expanded(child: Text(title, style: AppText.heading(size: 16))),
            IconButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              icon: const Icon(Icons.close_rounded),
              color: AppColors.textSecondary,
            ),
          ],
        ),
      ),
    ),
  );
}

class _WeekGrid extends StatelessWidget {
  const _WeekGrid({
    required this.schedule,
    required this.blockedDays,
    required this.enabled,
    required this.onTap,
  });

  final List<SessionType?> schedule;
  final List<bool> blockedDays;
  final bool enabled;
  final ValueChanged<int> onTap;
  static const _days = ['จ', 'อ', 'พ', 'พฤ', 'ศ', 'ส', 'อา'];

  @override
  Widget build(BuildContext context) => Row(
        children: List.generate(7, (index) {
          final type = schedule[index];
          final meta = type == null ? null : sessionMeta[type];
          final disabled = !enabled;
          final blocked = type == null && blockedDays[index];
          return Expanded(
            child: Padding(
              padding: EdgeInsets.only(right: index == 6 ? 0 : 5),
              child: Column(
                children: [
                  Text(_days[index],
                      style: AppText.body(
                          size: 10, color: AppColors.textTertiary)),
                  const SizedBox(height: 5),
                  GestureDetector(
                    onTap: disabled || blocked ? null : () => onTap(index),
                    child: Container(
                      height: 54,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: disabled || blocked
                            ? Colors.white.withOpacity(.08)
                            : type == null
                                ? Colors.white.withOpacity(.025)
                                : AppColors.purple1.withOpacity(.18),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: disabled || blocked
                              ? Colors.white.withOpacity(.05)
                              : type == null
                                  ? AppColors.border
                                  : AppColors.purple2.withOpacity(.55),
                        ),
                      ),
                      child: type == SessionType.restForced
                          ? const Icon(Icons.lock_outline,
                              size: 14, color: AppColors.textTertiary)
                          : blocked
                              ? const Icon(Icons.block_rounded,
                                  size: 14, color: AppColors.textTertiary)
                              : type == null
                                  ? const Icon(Icons.add,
                                      size: 14, color: AppColors.textTertiary)
                                  : Column(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      children: [
                                        Text(meta!.icon,
                                            style:
                                                const TextStyle(fontSize: 15)),
                                        Text(meta.label.split(' ').first,
                                            style: AppText.body(size: 8.5)),
                                      ],
                                    ),
                    ),
                  ),
                ],
              ),
            ),
          );
        }),
      );
}

int? _weekValue(dynamic value) => switch (value) {
      int weeks when weeks > 0 => weeks,
      num weeks when weeks > 0 => weeks.toInt(),
      _ => int.tryParse(value?.toString() ?? ''),
    };

List<Map<String, dynamic>> _mapList(dynamic value) =>
    (value as List<dynamic>? ?? const [])
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList(growable: false);

String _experienceBadgeLabel(String? level) => switch (level) {
      'beginner' => 'Beginner',
      'lower_intermediate' => 'Intermediate',
      'upper_intermediate' => 'Advanced',
      _ => 'Training',
    };

String _experienceLabel(String? level) => switch (level) {
      'beginner' => 'ระดับเริ่มต้น',
      'lower_intermediate' => 'ระดับกลาง',
      'upper_intermediate' => 'ระดับสูง',
      _ => 'แผนการฝึก',
    };

String _durationLabel(int? minWeeks, int? maxWeeks) {
  if (minWeeks == null) return 'ไม่ระบุระยะเวลา';
  if (maxWeeks == null || minWeeks == maxWeeks) return '$minWeeks สัปดาห์';
  return '$minWeeks-$maxWeeks สัปดาห์';
}

String _planName(String? goal) => switch (goal) {
      'sub_50' => 'Sub 50 5K ',
      '10k_sub_1.40' => 'Sub 1.40 10K',
      '21k_sub_3.30' => 'Sub 3.30 Half Marathon',
      _ => 'แผนการฝึกของคุณ',
    };
