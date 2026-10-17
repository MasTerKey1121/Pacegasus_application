import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/wellness_provider.dart';
import '../../providers/mission_provider.dart';
import '../../providers/program_provider.dart';
import '../../providers/auth_provider.dart';

import 'home_screen.dart';

import '../run/run_session_screen.dart';
import '../../providers/progress_provider.dart';
import '../../providers/daily_quest_provider.dart';
import '../../providers/run_provider.dart';
import '../../providers/run_setup_provider.dart';
import '../../services/run_draft_store.dart';

class MainShell extends ConsumerStatefulWidget {
  const MainShell({super.key});

  @override
  ConsumerState<MainShell> createState() => _MainShellState();
}

class _MainShellState extends ConsumerState<MainShell> {
  bool _isRestoringWellness = true;
  bool _wellnessReady = false;
  String? _draftError;
  bool _checkingDraft = false;

  @override
  void initState() {
    super.initState();

    Future.microtask(_restoreHome);
  }

  Future<void> _restoreHome() async {
    ref.invalidate(progressProvider);
    final programRestore = ref.read(programProvider).restore();
    final loaded = await ref.read(wellnessProvider).loadToday();
    if (!mounted) return;
    if (loaded) {
      ref
          .read(missionProvider)
          .setDone('wellness', ref.read(wellnessProvider).completedToday);
    }
    setState(() {
      _isRestoringWellness = false;
      _wellnessReady = loaded;
    });
    await programRestore;
    if (mounted && loaded) await _offerRunResume();
  }

  Future<void> _offerRunResume() async {
    if (_checkingDraft) return;
    final userId = ref.read(authProvider).user?['id']?.toString();
    if (userId == null) return;
    _checkingDraft = true;
    try {
      final draft = await verifiedRunDraft(
          runDraftStore, ref.read(runningSessionApiProvider), userId);
      if (!mounted ||
          ref.read(authProvider).user?['id']?.toString() != userId) {
        return;
      }
      setState(() => _draftError = null);
      if (draft == null) return;
      final pending = draft['pendingCompletion'] == true;
      final continueRun = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
                title: Text(pending
                    ? 'พบการวิ่งที่รอยืนยันการบันทึก'
                    : 'พบ Session การวิ่งที่ยังไม่เสร็จ'),
                content: Text(pending
                    ? 'เปิดเพื่อตรวจสถานะและลองบันทึกใหม่'
                    : 'ต้องการวิ่งต่อจากเดิมหรือไม่?'),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(ctx, false),
                      child: const Text('ไว้ภายหลัง')),
                  TextButton(
                      onPressed: () => Navigator.pop(ctx, true),
                      child: Text(pending ? 'ตรวจและบันทึกใหม่' : 'วิ่งต่อ')),
                ],
              ));
      if (mounted && continueRun != true) {
        setState(
            () => _draftError = 'มีข้อมูล Session ที่ยังไม่จบ เก็บไว้ให้แล้ว');
      }
      if (!mounted ||
          continueRun != true ||
          ref.read(authProvider).user?['id']?.toString() != userId) {
        return;
      }
      ref.read(runSetupProvider).restoreDraft(draft);
      ref.read(runProvider).restore(
          elapsed: (draft['elapsedSeconds'] as num?)?.toInt() ?? 0,
          distance: (draft['distanceKm'] as num?)?.toDouble() ?? 0,
          paused: draft['isPaused'] == true,
          pendingCompletion: pending);
      await Navigator.of(context)
          .push(MaterialPageRoute(builder: (_) => const RunSessionScreen()));
      if (mounted) ref.read(dailyQuestProvider).refresh();
    } catch (error) {
      if (mounted && ref.read(authProvider).user?['id']?.toString() == userId) {
        setState(() => _draftError =
            'ตรวจสถานะ Session ไม่สำเร็จ เก็บข้อมูลการวิ่งไว้แล้ว: $error');
      }
    } finally {
      _checkingDraft = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_wellnessReady) {
      return Stack(children: [
        HomeScreen(onReturned: _offerRunResume),
        if (_draftError != null)
          Positioned(
              left: 12,
              right: 12,
              bottom: 20,
              child: SafeArea(
                  child: Material(
                      color: Colors.black87,
                      child: Padding(
                          padding: const EdgeInsets.all(12),
                          child:
                              Column(mainAxisSize: MainAxisSize.min, children: [
                            Text(_draftError!),
                            TextButton(
                                onPressed:
                                    _checkingDraft ? null : _offerRunResume,
                                child: const Text('ลองตรวจสถานะอีกครั้ง')),
                          ]))))),
      ]);
    }
    return Scaffold(
      body: Center(
        child: _isRestoringWellness
            ? const CircularProgressIndicator()
            : Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('โหลดสถานะ Wellness ของวันนี้ไม่สำเร็จ'),
                  const SizedBox(height: 12),
                  TextButton(
                    onPressed: () {
                      setState(() => _isRestoringWellness = true);
                      _restoreHome();
                    },
                    child: const Text('ลองใหม่'),
                  ),
                ],
              ),
      ),
    );
  }
}
