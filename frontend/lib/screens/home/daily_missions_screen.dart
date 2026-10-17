import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../widgets/daily_quest_panel.dart';
import '../../widgets/daily_side_quest_panel.dart';

/// Quests come from the plan and recorded sessions, never a reward checklist.
class DailyMissionsScreen extends ConsumerWidget {
  const DailyMissionsScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) => Scaffold(
        appBar: AppBar(title: const Text('ภารกิจประจำวัน')),
        body: const SingleChildScrollView(
            child: Column(children: [
          DailyQuestPanel(home: true),
          DailySideQuestPanel(),
          Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                  'Main Quest ประเมินจากผลวิ่งที่ server บันทึกแล้ว · กดจบ Side Quest ระหว่างวิ่ง')),
        ])),
      );
}
