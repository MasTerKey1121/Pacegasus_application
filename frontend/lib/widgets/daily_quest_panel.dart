import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/daily_quest_provider.dart';
import '../providers/run_provider.dart';
import '../providers/run_setup_provider.dart';

/// One view of the same server-derived daily quest on all three surfaces.
class DailyQuestPanel extends ConsumerWidget {
  const DailyQuestPanel({super.key, this.duringRun = false, this.home = false});
  final bool duringRun, home;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(dailyQuestProvider);
    final quest = state.quest;
    final run = ref.watch(runProvider);
    final unit = quest?['unit'] == 'km' ? 'กม.' : 'นาที';
    final estimate =
        quest?['unit'] == 'km' ? run.distanceKm : run.elapsedSeconds / 60;
    final estimatedEligible = duringRun &&
        run.isRunning &&
        ref.watch(runSetupProvider).sessionType == quest?['session_type'] &&
        (quest?['running_session_id'] == null ||
            quest?['running_session_id'] ==
                ref.watch(runSetupProvider).sessionId);
    return Card(
        child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('Main Quest วันนี้'),
                if (state.loading) const LinearProgressIndicator(),
                if (quest == null && !state.loading && state.error == null)
                  const Text('วันนี้ไม่มีภารกิจตามแผน · วิ่งอิสระได้'),
                if (quest != null) ...[
                  Text(
                      '${quest['session_type']} · ${quest['planned_value']} ${quest['unit']}'),
                  if (state.completed)
                    Text(home
                        ? 'คุณทำภารกิจประจำวันสำเร็จแล้ว'
                        : 'คุณทำภารกิจประจำวันเสร็จแล้ว'),
                  if (state.supported && state.target != null) ...[
                    Text(
                        'วิ่งแล้ว ${state.saved.toStringAsFixed(2)} / ${state.target!.toStringAsFixed(2)} $unit (บันทึกแล้ว)'),
                    LinearProgressIndicator(value: state.fraction),
                    Text('${(state.fraction * 100).toStringAsFixed(2)}%'),
                    if (estimatedEligible && !state.completed)
                      Text(
                          'ประมาณการรอบนี้ +${estimate.toStringAsFixed(2)} $unit · ยังไม่บันทึก'),
                  ],
                  if (state.reward?['awarded'] == true)
                    Text(
                        'Main Quest: +${state.reward!['coins']} coin · +${state.reward!['exp']} EXP (server)'),
                ],
                if (state.error != null)
                  Text(state.error!,
                      style: const TextStyle(color: Colors.redAccent)),
                TextButton(
                    onPressed: state.loading ? null : state.refresh,
                    child: Text(
                        state.error == null ? 'โหลดสถานะล่าสุด' : 'ลองใหม่')),
              ],
            )));
  }
}
