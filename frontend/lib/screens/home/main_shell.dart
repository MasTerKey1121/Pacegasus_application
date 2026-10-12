import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/wellness_provider.dart';
import '../../providers/mission_provider.dart';
import '../../providers/program_provider.dart';
import '../../providers/auth_provider.dart';

import 'home_screen.dart';

import '../run/run_session_screen.dart';
import '../run/run_summary_screen.dart';
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

  @override
  void initState() {
    super.initState();

    Future.microtask(_restoreHome);
  }

  Future<void> _restoreHome() async {
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
    final userId = ref.read(authProvider).user?['id']?.toString();
    final draft = await runDraftStore.loadForUser(userId);
    if (!mounted || draft == null || draft['sessionId'] == null) return;
    final continueRun = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('พบ Session การวิ่งที่ยังไม่เสร็จ'),
        content: const Text('ต้องการวิ่งต่อจากเดิมหรือไม่?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('จบ Session')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('วิ่งต่อ')),
        ],
      ),
    );
    if (!mounted) return;
    ref.read(runSetupProvider).restoreDraft(draft);
    ref.read(runProvider).restore(
          elapsed: (draft['elapsedSeconds'] as num?)?.toInt() ?? 0,
          distance: (draft['distanceKm'] as num?)?.toDouble() ?? 0,
          paused: draft['isPaused'] == true,
        );
    if (continueRun != true) {
      final route = (draft['routePoints'] as List<dynamic>? ?? const [])
          .whereType<Map>()
          .map((point) => <String, double>{
                'lat': (point['lat'] as num?)?.toDouble() ?? 13.7563,
                'lng': (point['lng'] as num?)?.toDouble() ?? 100.5018,
              })
          .toList();
      final result = await ref.read(runProvider).stop(
            sessionId: ref.read(runSetupProvider).sessionId!,
            sideQuests: ref.read(runSetupProvider).activeSideQuests,
            routePoints: route,
          );
      if (mounted && result != null) {
        await runDraftStore.clear();
        if (!mounted) return;
        Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => RunSummaryScreen(result: result)),
        );
      }
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const RunSessionScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_wellnessReady) return const HomeScreen();
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
