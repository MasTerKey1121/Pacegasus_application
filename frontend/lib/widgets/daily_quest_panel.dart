import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../app_theme.dart';
import '../models/training_date.dart';
import '../providers/daily_quest_provider.dart';
import '../providers/run_provider.dart';
import '../providers/run_setup_provider.dart';
import '../providers/program_provider.dart';
import 'program_access_notice.dart';

/// Shared Home-style card. During a run only unfinished missions are shown.
class DailyQuestPanel extends ConsumerWidget {
  const DailyQuestPanel({super.key, this.duringRun = false, this.home = false});
  final bool duringRun, home;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(dailyQuestProvider);
    final program = ref.watch(programProvider);
    final accessBlocked = program.access != ProgramAccess.ready;
    final waiting = state.loading ||
        (!state.hasLoaded && state.quest == null && state.error == null);
    if (!accessBlocked &&
        !waiting &&
        state.error == null &&
        duringRun &&
        state.completed) {
      return const SizedBox.shrink();
    }
    final quest = state.quest;
    final run = ref.watch(runProvider);
    final setup = ref.watch(runSetupProvider);
    final unit = quest?['unit'] == 'km' ? 'กม.' : 'นาที';
    final estimate =
        quest?['unit'] == 'km' ? run.distanceKm : run.elapsedSeconds / 60;
    final estimatedEligible = duringRun &&
        run.isRunning &&
        setup.sessionType == quest?['session_type'] &&
        (quest?['running_session_id'] == null ||
            quest?['running_session_id'] == setup.sessionId);
    final type = quest?['session_type'];
    final name = switch (type) {
      'easy' => 'Easy Run',
      'tempo' => 'Tempo Run',
      'vo2max' => 'VO2 Max',
      'long_run' => 'Long Run',
      _ => type?.toString() ?? 'วิ่งอิสระ',
    };
    final date = trainingDate(quest?['scheduled_date']);
    return Container(
      key: const Key('daily-main-quest-card'),
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFF29223B),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppColors.borderHi),
      ),
      child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Main Quest วันนี้',
                style: AppText.body(size: 10, color: const Color(0xFFC5A2FF))),
            const SizedBox(height: 8),
            if (accessBlocked)
              const ProgramAccessNotice()
            else if (waiting) ...[
              Text('กำลังโหลดแผนวันนี้…', style: AppText.heading(size: 18)),
              const LinearProgressIndicator(),
            ] else if (state.error != null) ...[
              Text('โหลดสถานะภารกิจไม่สำเร็จ',
                  style: AppText.heading(size: 18)),
              TextButton(
                  onPressed: state.refresh, child: const Text('ลองใหม่')),
            ] else if (state.completed)
              Text('ทำภารกิจเสร็จสิ้น', style: AppText.heading(size: 18))
            else ...[
              Text(
                  quest == null
                      ? (state.loading ? 'กำลังโหลดแผนวันนี้…' : 'วิ่งอิสระ')
                      : '$name · ${state.target?.toStringAsFixed(2) ?? quest['planned_value']} ${quest['unit']}',
                  style: AppText.heading(size: 18)),
              if (date != null)
                Text('${date.day}/${date.month}',
                    style:
                        AppText.body(size: 12, color: const Color(0xFFC5A2FF))),
              if (state.loading) ...[
                const SizedBox(height: 8),
                const LinearProgressIndicator()
              ],
              if (quest == null && !state.loading && state.error == null)
                Text('วันนี้ไม่มีภารกิจตามแผน · วิ่งอิสระได้',
                    style:
                        AppText.body(size: 12, color: AppColors.textSecondary)),
              if (quest != null && state.supported && state.target != null) ...[
                const SizedBox(height: 8),
                Text(
                    'วิ่งแล้ว ${state.saved.toStringAsFixed(2)} / ${state.target!.toStringAsFixed(2)} $unit (บันทึกแล้ว)',
                    style:
                        AppText.body(size: 12, color: AppColors.textSecondary)),
                const SizedBox(height: 8),
                ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: LinearProgressIndicator(
                        value: state.fraction,
                        minHeight: 6,
                        color: const Color(0xFFC5A2FF),
                        backgroundColor: Colors.white12)),
                const SizedBox(height: 4),
                Text('${(state.fraction * 100).toStringAsFixed(2)}%',
                    style:
                        AppText.body(size: 11, color: const Color(0xFFD6F5A6))),
                if (estimatedEligible)
                  Text(
                      'ประมาณการรอบนี้ +${estimate.toStringAsFixed(2)} $unit · ยังไม่บันทึก',
                      style: AppText.body(
                          size: 11, color: AppColors.textSecondary)),
              ],
            ],
            if (!accessBlocked && state.error != null) ...[
              const SizedBox(height: 8),
              Text(state.error!,
                  style: AppText.body(size: 12, color: AppColors.red1)),
            ],
          ]),
    );
  }
}
