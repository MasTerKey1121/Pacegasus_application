import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app_theme.dart';
import '../../providers/program_provider.dart';
import '../../widgets/common.dart';

/// Displays the schedule returned by API 5.2 for the active program.
class TrainingScheduleScreen extends ConsumerWidget {
  const TrainingScheduleScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final program = ref.watch(programProvider);

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
                    Text('Training schedule', style: AppText.heading(size: 19)),
                  ],
                ),
                const SizedBox(height: 20),
                if (program.isLoading)
                  const Expanded(
                    child: Center(child: CircularProgressIndicator()),
                  )
                else if (!program.isRegistered)
                  Expanded(
                    child: Center(
                      child: Text(
                        'Register a training plan before viewing the schedule.',
                        textAlign: TextAlign.center,
                        style: AppText.body(
                          size: 13,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ),
                  )
                else if (program.quests.isEmpty)
                  Expanded(
                    child: Center(
                      child: Text(
                        'No workouts are scheduled for this week.',
                        textAlign: TextAlign.center,
                        style: AppText.body(
                          size: 13,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ),
                  )
                else
                  Expanded(
                    child: ListView.separated(
                      itemCount: program.quests.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 10),
                      itemBuilder: (context, index) {
                        final quest = program.quests[index];
                        return _QuestCard(quest: quest);
                      },
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _QuestCard extends StatelessWidget {
  const _QuestCard({required this.quest});

  final Map<String, dynamic> quest;

  @override
  Widget build(BuildContext context) {
    final type = quest['session_type']?.toString() ?? 'run';
    final value = quest['planned_value'];
    final unit = quest['unit']?.toString();
    final date = quest['scheduled_date']?.toString() ?? '';
    final target = value == null ? '' : ' $value${unit == null ? '' : ' $unit'}';

    return AppCard(
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: AppColors.purple1.withOpacity(.16),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.directions_run, color: Colors.white),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(_titleFor(type), style: AppText.heading(size: 14)),
                const SizedBox(height: 3),
                Text(
                  '$date$target',
                  style: AppText.body(
                    size: 12,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _titleFor(String type) => switch (type) {
        'easy' => 'Easy Run',
        'tempo' => 'Tempo Run',
        'vo2max' => 'VO2 Max',
        'long_run' => 'Long Run',
        _ => type,
      };
}
