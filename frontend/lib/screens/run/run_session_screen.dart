import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../app_theme.dart';
import '../../models/side_quest.dart';
import '../../providers/run_provider.dart';
import '../../widgets/common.dart';
import 'run_summary_screen.dart';
import '../../providers/run_setup_provider.dart';

class RunSessionScreen extends ConsumerStatefulWidget {
  const RunSessionScreen({super.key});

  @override
  ConsumerState<RunSessionScreen> createState() => _RunSessionScreenState();
}

class _RunSessionScreenState extends ConsumerState<RunSessionScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance
        .addPostFrameCallback((_) => ref.read(runProvider).start());
  }

  void _openMissionsSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => const _MissionsMiniWindow(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final run = ref.watch(runProvider);
    final setup = ref.watch(runSetupProvider);
    final quests = setup.activeSideQuests;
    final doneCount = quests.where((q) => q.done).length;

    return Scaffold(
      backgroundColor: AppColors.bg1,
      body: SafeArea(
        child: Stack(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      _Stat(value: run.distanceKm.toStringAsFixed(2), label: 'กม.'),
                      _Stat(value: run.elapsedLabel, label: 'เวลา'),
                      _Stat(
                          value: run.distanceKm > 0
                              ? '${(run.elapsedSeconds / 60 / run.distanceKm).toStringAsFixed(1)}'
                              : '--:--',
                          label: 'pace'),
                    ],
                  ),
                  const SizedBox(height: 22),
                  Expanded(
                    child: Container(
                      width: double.infinity,
                      decoration: BoxDecoration(
                        color: const Color(0xFF211B3D),
                        borderRadius: BorderRadius.circular(24),
                      ),
                      child: Center(
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 300),
                          width: 26,
                          height: 26,
                          decoration: BoxDecoration(
                            color: AppColors.purple2,
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                  color: AppColors.purple1.withOpacity(.5),
                                  blurRadius: 18,
                                  spreadRadius: 6)
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('ระยะทางที่เหลือ',
                              style: AppText.body(
                                  size: 11.5, color: AppColors.textTertiary)),
                          Text(
                              '${run.distanceKm.toStringAsFixed(1)} / ${run.goalDistanceKm.toStringAsFixed(0)} km',
                              style: AppText.heading(size: 13.5)),
                        ],
                      ),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text('เป้าหมาย',
                              style: AppText.body(
                                  size: 11.5, color: AppColors.textTertiary)),
                          Text(run.goalPace, style: AppText.heading(size: 13.5)),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  if (quests.isNotEmpty)
                    Center(
                      child: GestureDetector(
                        onTap: _openMissionsSheet,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 18, vertical: 10),
                          decoration: BoxDecoration(
                            color: const Color(0xFF211B3D),
                            borderRadius: BorderRadius.circular(999),
                            border: Border.all(color: AppColors.border),
                            boxShadow: [
                              BoxShadow(
                                  color: Colors.black.withOpacity(.25),
                                  blurRadius: 10,
                                  offset: const Offset(0, 4)),
                            ],
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Text('🎯', style: TextStyle(fontSize: 14)),
                              const SizedBox(width: 8),
                              Text('ภารกิจ $doneCount/${quests.length}',
                                  style: AppText.heading(size: 13)),
                            ],
                          ),
                        ),
                      ),
                    ),
                  const SizedBox(height: 18),
                  Row(
                    children: [
                      GestureDetector(
                        onTap: run.isStopping
                            ? null
                            : () => ref.read(runProvider).togglePause(),
                        child: Container(
                          width: 54,
                          height: 54,
                          decoration: BoxDecoration(
                            color: AppColors.card,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: AppColors.border),
                          ),
                          child: Icon(
                              run.isPaused
                                  ? Icons.play_arrow_rounded
                                  : Icons.pause_rounded,
                              color: Colors.white),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: GradientButton(
                          label: '■ จบการวิ่ง',
                          loading: run.isStopping,
                          gradient: LinearGradient(
                              colors: [AppColors.red1, AppColors.red2]),
                          onTap: run.isStopping
                              ? null
                              : () async {
                                  final confirmed = await showDialog<bool>(
                                    context: context,
                                    builder: (ctx) => AlertDialog(
                                      title: Text('จบการวิ่ง?'),
                                      content: Text('ต้องการจบการวิ่งจริงหรือไม่'),
                                      actions: [
                                        TextButton(
                                            onPressed: () =>
                                                Navigator.pop(ctx, false),
                                            child: Text('ยกเลิก')),
                                        TextButton(
                                            onPressed: () =>
                                                Navigator.pop(ctx, true),
                                            child: Text('จบการวิ่ง')),
                                      ],
                                    ),
                                  );
                                  if (confirmed != true) return;
                                  final result =
                                      await ref.read(runProvider).stop(
                                            sessionId: ref
                                                .read(runSetupProvider)
                                                .sessionId!,
                                            sideQuests: ref
                                                .read(runSetupProvider)
                                                .activeSideQuests,
                                          );
                                  if (!context.mounted) return;
                                  final failed =
                                      ref.read(runProvider).failedQuestTitles;
                                  if (failed.isNotEmpty) {
                                    showAppToast(
                                      context,
                                      'จบการวิ่งสำเร็จ แต่ยืนยันภารกิจไม่สำเร็จ: '
                                      '${failed.join(', ')}',
                                    );
                                  }
                                  if (result != null && context.mounted) {
                                    Navigator.of(context).pushReplacement(
                                      MaterialPageRoute(
                                          builder: (_) =>
                                              RunSummaryScreen(result: result)),
                                    );
                                  }
                                },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    run.isPaused
                        ? 'หยุดชั่วคราว · ${run.elapsedLabel}'
                        : 'กำลังวิ่ง · ${run.elapsedLabel}',
                    style: AppText.body(size: 11.5, color: AppColors.textTertiary),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// หน้าต่างเล็ก ๆ (modal bottom sheet) แสดงภารกิจที่เลือกไว้ตอนหน้าเลือกประเภทการวิ่ง
/// กดจบทีละภารกิจได้เลยระหว่างที่ยังวิ่งอยู่
class _MissionsMiniWindow extends ConsumerWidget {
  const _MissionsMiniWindow();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final setup = ref.watch(runSetupProvider);
    final quests = setup.activeSideQuests;

    return SafeArea(
      child: Container(
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: const Color(0xFF17122B),
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: AppColors.border),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('ภารกิจระหว่างวิ่ง', style: AppText.heading(size: 15)),
                RoundIconButton(
                    icon: Icons.close, onTap: () => Navigator.of(context).pop()),
              ],
            ),
            const SizedBox(height: 12),
            if (quests.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Text('ไม่ได้เลือกภารกิจไว้สำหรับการวิ่งนี้',
                    style:
                        AppText.body(size: 12.5, color: AppColors.textSecondary)),
              )
            else
              ...quests.map((q) => Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: AppCard(
                      borderColor:
                          q.done ? AppColors.green1.withOpacity(.4) : AppColors.border,
                      child: Row(
                        children: [
                          Text(q.icon ?? '🎯', style: const TextStyle(fontSize: 20)),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(q.title, style: AppText.heading(size: 13.5)),
                                if (q.description.isNotEmpty)
                                  Text(q.description,
                                      style: AppText.body(
                                          size: 11.5, color: AppColors.textSecondary)),
                                Text('+${q.coinReward} coin',
                                    style:
                                        AppText.body(size: 11, color: AppColors.gold1)),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          _MissionActionButton(quest: q),
                        ],
                      ),
                    ),
                  )),
          ],
        ),
      ),
    );
  }
}

class _MissionActionButton extends ConsumerWidget {
  final ActiveSideQuest quest;
  const _MissionActionButton({required this.quest});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final setup = ref.watch(runSetupProvider);
    final loading = setup.isCompletingQuest(quest.sideQuestId);

    if (quest.done) {
      return const Icon(Icons.check_circle, color: AppColors.green1, size: 26);
    }

    if (loading) {
      return const SizedBox(
        width: 22,
        height: 22,
        child: CircularProgressIndicator(strokeWidth: 2.4),
      );
    }

    return GestureDetector(
      onTap: () =>
          ref.read(runSetupProvider).completeSideQuest(quest.sideQuestId),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: AppColors.purple2.withOpacity(.18),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: AppColors.purple2),
        ),
        child: Text('จบภารกิจ',
            style: AppText.body(
                size: 11.5, weight: FontWeight.w600, color: AppColors.purple2)),
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  final String value;
  final String label;
  const _Stat({required this.value, required this.label});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(value, style: AppText.heading(size: 22)),
        const SizedBox(height: 2),
        Text(label,
            style: AppText.body(size: 11.5, color: AppColors.textTertiary)),
      ],
    );
  }
}