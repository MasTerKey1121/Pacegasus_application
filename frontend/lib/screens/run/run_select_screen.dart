import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../app_theme.dart';
import '../../providers/program_provider.dart';
import '../../providers/run_setup_provider.dart';
import '../../widgets/common.dart';
import 'run_session_screen.dart';

const _environments = [
  {'key': 'road', 'label': 'Road', 'icon': '🛣️'},
  {'key': 'park', 'label': 'Park', 'icon': '🌳'},
  {'key': 'city', 'label': 'City', 'icon': '🏙️'},
  {'key': 'treadmill', 'label': 'Treadmill', 'icon': '🏃‍♂️'},
  {'key': 'trail', 'label': 'Trail', 'icon': '⛰️'},
];

class RunTypeSelectScreen extends ConsumerWidget {
  const RunTypeSelectScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final setup = ref.watch(runSetupProvider);
    final program = ref.watch(programProvider);
    final todayQuest = program.todayQuest;
    final sessionType = todayQuest?['session_type']?.toString();

    return Scaffold(
      backgroundColor: AppColors.bg1,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                RoundIconButton(icon: Icons.arrow_back, onTap: () => Navigator.of(context).pop()),
                const SizedBox(width: 14),
                Text('เลือกประเภทการวิ่ง', style: AppText.heading(size: 18)),
              ]),
              const SizedBox(height: 20),

              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: _environments.map((e) {
                  final active = setup.environment == e['key'];
                  return GestureDetector(
                    onTap: () => ref
                        .read(runSetupProvider)
                        .selectEnvironment(
                          env: e['key']!,
                          mainQuestSessionType: sessionType,
                        ),
                    child: Container(
                      width: 96,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      decoration: BoxDecoration(
                        color: active ? AppColors.purple2.withOpacity(.18) : AppColors.card,
                        border: Border.all(color: active ? AppColors.purple2 : AppColors.border),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Column(children: [
                        Text(e['icon']!, style: const TextStyle(fontSize: 22)),
                        const SizedBox(height: 6),
                        Text(e['label']!, style: AppText.body(size: 12)),
                      ]),
                    ),
                  );
                }).toList(),
              ),

              const SizedBox(height: 20),
              if (setup.isLoadingQuests) const Center(child: CircularProgressIndicator())
              else if (setup.environment != null) ...[
                const SectionLabel(title: 'Side Quest'),
                if (setup.sideQuests.isEmpty)
                  Text('ไม่มี side quest สำหรับตัวเลือกนี้',
                      style: AppText.body(size: 12, color: AppColors.textSecondary))
                else
                  ...setup.sideQuests.map((q) {
                    final selected = setup.selectedInstanceIds.contains(q.instanceId);
                    return GestureDetector(
                      onTap: () => ref.read(runSetupProvider).selectSideQuest(q.instanceId),
                      child: AppCard(
                        borderColor: selected ? AppColors.purple2 : AppColors.border,
                        child: Row(children: [
                          Text(q.icon ?? '🎯', style: const TextStyle(fontSize: 20)),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(q.title, style: AppText.heading(size: 13.5)),
                                Text(q.description, style: AppText.body(size: 11.5, color: AppColors.textSecondary)),
                              ],
                            ),
                          ),
                          Icon(selected ? Icons.check_circle : Icons.circle_outlined,
                              color: selected ? AppColors.purple2 : AppColors.textTertiary),
                        ]),
                      ),
                    );
                  }),
              ],

              const SectionLabel(title: 'Main Quest วันนี้'),
              AppCard(
                child: todayQuest == null
                    ? Text('วันนี้ไม่มีเควสในตารางฝึก',
                        style: AppText.body(size: 12, color: AppColors.textSecondary))
                    : Text(
                        '${todayQuest['session_type'] ?? ''} · ${todayQuest['planned_value'] ?? ''} ${todayQuest['unit'] ?? ''}',
                        style: AppText.heading(size: 13.5),
                      ),
              ),

              const Spacer(),
              GradientButton(
                label: setup.isStarting ? 'กำลังเริ่ม...' : 'เริ่มต้นการวิ่ง',
                loading: setup.isStarting,
                onTap: setup.environment == null || setup.isStarting
                    ? null
                    : () async {
                        final ok = await ref
                            .read(runSetupProvider)
                            .startRun(mainQuestSessionType: sessionType);
                        if (ok && context.mounted) {
                          Navigator.of(context).pushReplacement(
                            MaterialPageRoute(builder: (_) => const RunSessionScreen()),
                          );
                        }
                      },
              ),
            ],
          ),
        ),
      ),
    );
  }
}