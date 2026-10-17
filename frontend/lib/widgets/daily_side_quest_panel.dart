import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/run_setup_provider.dart';

class DailySideQuestPanel extends ConsumerWidget {
  const DailySideQuestPanel({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final setup = ref.watch(runSetupProvider);
    if (setup.sideQuests.isEmpty) return const SizedBox.shrink();
    return Card(
        child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('Side Quest วันนี้'),
                if (setup.dailyComplete)
                  const Text('คุณทำ Side Quest ของวันนี้สำเร็จแล้ว'),
                for (final q in setup.sideQuests)
                  Text(
                      '${q.title} · ${setup.isDone(q.instanceId) ? 'คุณสำเร็จภารกิจนี้แล้ว' : 'ทำได้ระหว่าง Session ที่ผูกไว้'}'),
                if (setup.errorMessage != null) Text(setup.errorMessage!),
              ],
            )));
  }
}
