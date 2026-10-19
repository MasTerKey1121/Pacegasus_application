import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../app_theme.dart';
import '../providers/program_provider.dart';
import '../screens/training/training_registration_screen.dart';
import '../screens/training/training_schedule_screen.dart';

/// The same prerequisite and recovery actions on every Main Quest surface.
class ProgramAccessNotice extends ConsumerStatefulWidget {
  const ProgramAccessNotice({super.key});
  @override
  ConsumerState<ProgramAccessNotice> createState() =>
      _ProgramAccessNoticeState();
}

class _ProgramAccessNoticeState extends ConsumerState<ProgramAccessNotice> {
  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      if (mounted) ref.read(programProvider).restore();
    });
  }

  @override
  Widget build(BuildContext context) {
    final program = ref.watch(programProvider);
    final access = program.access;
    final message = switch (access) {
      ProgramAccess.unregistered => 'กรุณาลงทะเบียนตารางซ้อมก่อน',
      ProgramAccess.unscheduled => 'กรุณาจัดและบันทึกตารางซ้อมก่อน',
      ProgramAccess.failed => 'ตรวจสอบสถานะแผนซ้อมไม่สำเร็จ',
      _ => 'กำลังตรวจสอบแผนและตารางซ้อม…',
    };
    return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(message, style: AppText.heading(size: 17)),
          if (access == ProgramAccess.checking)
            const Padding(
                padding: EdgeInsets.only(top: 12),
                child: LinearProgressIndicator()),
          TextButton(
            onPressed: access == ProgramAccess.checking
                ? null
                : () {
                    if (access == ProgramAccess.failed) {
                      program.restore(force: true);
                    } else {
                      Navigator.of(context).push(MaterialPageRoute(
                          builder: (_) => access == ProgramAccess.unregistered
                              ? const TrainingRegistrationScreen()
                              : const TrainingScheduleScreen()));
                    }
                  },
            child: Text(switch (access) {
              ProgramAccess.unregistered => 'ลงทะเบียนตารางซ้อม',
              ProgramAccess.unscheduled => 'จัดตารางซ้อม',
              _ => 'ลองใหม่',
            }),
          ),
        ]);
  }
}
