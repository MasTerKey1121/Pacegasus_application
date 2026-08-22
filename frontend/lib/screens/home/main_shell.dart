import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../app_theme.dart';
import '../../providers/wellness_provider.dart';
import '../../providers/mission_provider.dart';
import '../../providers/program_provider.dart';

import 'home_screen.dart';
import '../stats/stats_screen.dart';
import '../profile/profile_screen.dart';
import '../settings/settings_screen.dart';
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
  int _index = 0;

  @override
  void initState() {
    super.initState();

    Future.microtask(() async {
      await ref.read(programProvider).restore();
      await ref.read(wellnessProvider).loadToday();

      if (ref.read(wellnessProvider).completedToday) {
        ref.read(missionProvider).setDone('wellness', true);
      }
      await _offerRunResume();
    });
  }

  Future<void> _offerRunResume() async {
    final draft = await runDraftStore.load();
    if (!mounted || draft == null || draft['sessionId'] == null) return;
    final continueRun = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('พบ Session การวิ่งที่ยังไม่เสร็จ'),
        content: const Text('ต้องการวิ่งต่อจากเดิมหรือไม่?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('จบ Session')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('วิ่งต่อ')),
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

  final _tabs = const [
    _TabItem('🏠', 'หน้าหลัก'),
    _TabItem('📊', 'สถิติ'),
    _TabItem('🏆', 'โปรไฟล์'),
    _TabItem('⚙️', 'ตั้งค่า'),
  ];

  final _screens = const [
    HomeScreen(),
    StatsScreen(),
    ProfileScreen(),
    SettingsScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: AppBackground(
        child: SafeArea(
          bottom: false,
          child: IndexedStack(
            index: _index,
            children: _screens,
          ),
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Container(
          height: 66,
          margin: const EdgeInsets.fromLTRB(16, 0, 16, 10),
          decoration: BoxDecoration(
            color: const Color(0xFF130F26),
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: AppColors.border),
          ),
          child: Row(
            children: List.generate(_tabs.length, (i) {
              final active = i == _index;
              final tab = _tabs[i];

              return Expanded(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () {
                    setState(() {
                      _index = i;
                    });
                  },
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        tab.icon,
                        style: const TextStyle(fontSize: 19),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        tab.label,
                        style: AppText.body(
                          size: 10.5,
                          weight: FontWeight.w600,
                          color: active
                              ? AppColors.purple2
                              : AppColors.textTertiary,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }),
          ),
        ),
      ),
    );
  }
}

class _TabItem {
  final String icon;
  final String label;

  const _TabItem(this.icon, this.label);
}
