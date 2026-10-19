import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../app_theme.dart';
import '../../models/side_quest.dart';
import '../../providers/daily_quest_provider.dart';
import '../../providers/program_provider.dart';
import '../../providers/run_setup_provider.dart';
import '../../widgets/common.dart';
import '../../widgets/daily_quest_panel.dart';
import 'run_session_screen.dart';

const _environments = [
  {'key': 'road', 'label': 'Road', 'icon': '🛣️'},
  {'key': 'park', 'label': 'Park', 'icon': '🌳'},
  {'key': 'city', 'label': 'City', 'icon': '🏙️'},
  {'key': 'treadmill', 'label': 'Treadmill', 'icon': '🏃‍♂️'},
  {'key': 'trail', 'label': 'Trail', 'icon': '⛰️'},
];

class RunTypeSelectScreen extends ConsumerStatefulWidget {
  const RunTypeSelectScreen({super.key});

  @override
  ConsumerState<RunTypeSelectScreen> createState() =>
      _RunTypeSelectScreenState();
}

class _RunTypeSelectScreenState extends ConsumerState<RunTypeSelectScreen> {
  @override
  void initState() {
    super.initState();
    Future.microtask(() => ref.read(programProvider).restore(force: true));
  }

  @override
  Widget build(BuildContext context) {
    final setup = ref.watch(runSetupProvider);
    final daily = ref.watch(dailyQuestProvider);
    final eligible = ref.watch(programProvider).access == ProgramAccess.ready;
    final todayQuest = daily.completed ? null : daily.quest;
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
                RoundIconButton(
                    icon: Icons.arrow_back,
                    onTap: () => Navigator.of(context).pop()),
                const SizedBox(width: 14),
                Text('เลือกประเภทการวิ่ง', style: AppText.heading(size: 18)),
              ]),
              const SizedBox(height: 20),
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Wrap(
                        spacing: 10,
                        runSpacing: 10,
                        children: _environments.map((e) {
                          final active = setup.environment == e['key'];
                          return GestureDetector(
                            onTap: !eligible
                                ? null
                                : () => ref
                                    .read(runSetupProvider)
                                    .selectEnvironment(
                                      env: e['key']!,
                                      mainQuestSessionType: sessionType,
                                    ),
                            child: Container(
                              width: 96,
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              decoration: BoxDecoration(
                                color: active
                                    ? AppColors.purple2.withValues(alpha: .18)
                                    : AppColors.card,
                                border: Border.all(
                                    color: active
                                        ? AppColors.purple2
                                        : AppColors.border),
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: Column(children: [
                                Text(e['icon']!,
                                    style: const TextStyle(fontSize: 22)),
                                const SizedBox(height: 6),
                                Text(e['label']!,
                                    style: AppText.body(size: 12)),
                              ]),
                            ),
                          );
                        }).toList(),
                      ),
                      const SizedBox(height: 20),
                      if (setup.isLoadingQuests)
                        const Center(child: CircularProgressIndicator())
                      else if (eligible && setup.environment != null) ...[
                        const SectionLabel(title: 'Side Quest วันนี้'),
                        if (setup.noSideQuestsMessage != null)
                          Text(setup.noSideQuestsMessage!,
                              style: AppText.body(
                                  size: 12, color: AppColors.textSecondary))
                        else ...[
                          Text(
                            setup.dailyComplete
                                ? 'ทำ Side Quest ของวันนี้เสร็จแล้ว'
                                : 'เลือกทำ Side Quest อันใดอันหนึ่งระหว่างวิ่ง เพื่อสำเร็จภารกิจของสถานที่นี้ในวันนี้',
                            style: AppText.body(
                                size: 12, color: AppColors.textSecondary),
                          ),
                          const SizedBox(height: 12),
                          if (setup.sideQuests.isEmpty &&
                              setup.errorMessage == null)
                            Text('ไม่มี side quest สำหรับตัวเลือกนี้',
                                style: AppText.body(
                                    size: 12, color: AppColors.textSecondary))
                          else
                            ...setup.visibleSideQuests.map((q) =>
                                _SideQuestCard(
                                    quest: q,
                                    completed: setup.isDone(q.instanceId),
                                    notice: setup
                                        .questSessionNotice(q.instanceId))),
                        ],
                      ],
                      const DailyQuestPanel(),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              if (setup.errorMessage != null) ...[
                Text(
                  setup.errorMessage!,
                  textAlign: TextAlign.center,
                  style: AppText.body(size: 12, color: AppColors.red1),
                ),
                if (setup.canRetryQuests)
                  TextButton(
                      onPressed:
                          setup.isLoadingQuests ? null : setup.retrySideQuests,
                      child: const Text('ลองโหลด Side Quest ใหม่')),
                const SizedBox(height: 10),
              ],
              GradientButton(
                label: setup.isStarting ? 'กำลังเริ่ม...' : 'เริ่มต้นการวิ่ง',
                loading: setup.isStarting,
                onTap: !eligible ||
                        setup.environment == null ||
                        setup.isLoadingQuests ||
                        setup.isStarting
                    ? null
                    : () async {
                        ref.read(runSetupProvider).mainQuestAtStart =
                            todayQuest?['id']?.toString();
                        final ok = await ref
                            .read(runSetupProvider)
                            .startRun(mainQuestSessionType: sessionType);
                        if (ok && context.mounted) {
                          Navigator.of(context).pushReplacement(
                            MaterialPageRoute(
                                builder: (_) => const RunSessionScreen()),
                          );
                        } else if (context.mounted &&
                            ref.read(runSetupProvider).errorMessage == null) {
                          showAppToast(
                              context, 'เริ่ม Session ไม่สำเร็จ กรุณาลองใหม่');
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

class _SideQuestCard extends StatelessWidget {
  const _SideQuestCard(
      {required this.quest, required this.completed, this.notice});
  final SideQuest quest;
  final bool completed;
  final String? notice;

  @override
  Widget build(BuildContext context) => Stack(children: [
        Opacity(
          opacity: completed ? .38 : 1,
          child: AppCard(
            child: Padding(
              padding: EdgeInsets.only(bottom: completed ? 40 : 0),
              child: Row(children: [
                Text(quest.icon ?? '🎯', style: const TextStyle(fontSize: 20)),
                const SizedBox(width: 10),
                Expanded(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                      Text(quest.title, style: AppText.heading(size: 13.5)),
                      Text(quest.description,
                          style: AppText.body(
                              size: 11.5, color: AppColors.textSecondary)),
                      if (!completed)
                        Text('รางวัลที่เสนอ ${quest.coinReward} เหรียญ',
                            style:
                                AppText.body(size: 11, color: AppColors.gold1)),
                      if (notice != null)
                        Text(notice!,
                            style: AppText.body(
                                size: 11, color: AppColors.textSecondary)),
                    ])),
              ]),
            ),
          ),
        ),
        if (completed) ...[
          Positioned.fill(
              child: IgnorePointer(
                  child: CustomPaint(
            key: ValueKey('completed-quest-cross-${quest.instanceId}'),
            painter: _CompletedQuestCross(),
          ))),
          Positioned(
              left: 12,
              right: 12,
              bottom: 18,
              child: Text('ทำภารกิจเสริมของวันนี้สำเร็จแล้ว',
                  textAlign: TextAlign.center,
                  style: AppText.heading(size: 18, color: AppColors.gold1))),
        ],
      ]);
}

class _CompletedQuestCross extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = AppColors.textSecondary.withValues(alpha: .45)
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(
        const Offset(18, 14), Offset(size.width - 18, size.height - 50), paint);
    canvas.drawLine(
        Offset(size.width - 18, 14), Offset(18, size.height - 50), paint);
  }

  @override
  bool shouldRepaint(covariant _CompletedQuestCross oldDelegate) => false;
}
