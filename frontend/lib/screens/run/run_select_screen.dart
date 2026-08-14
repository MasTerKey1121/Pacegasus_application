import 'package:geolocator/geolocator.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../app_theme.dart';
import '../../providers/program_provider.dart';
import '../../providers/run_setup_provider.dart';
import '../../widgets/common.dart';
import '../home/main_shell.dart';
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
    // Comment out ไว้ก่อน เพราะกด "อนุญาต" GPS ทุกครั้งตอนเทสมันยุ่งยาก
    // WidgetsBinding.instance.addPostFrameCallback((_) async {
    //   await _requestGpsAccess(context);
    // });
  }

  Future<bool> _requestGpsAccess(BuildContext context) async {
    final accepted = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        title: const Text('อนุญาตการเข้าถึง GPS'),
        content: const Text(
          'Pacegasus ต้องใช้ตำแหน่งของคุณเพื่อบันทึกระยะทางและเส้นทางการวิ่ง',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('ไม่อนุญาต'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('อนุญาต'),
          ),
        ],
      ),
    );

    if (accepted != true) {
      if (context.mounted) {
        _returnToHome(context);
      }
      return false;
    }

    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }

      if (serviceEnabled &&
          permission != LocationPermission.denied &&
          permission != LocationPermission.deniedForever) {
        return true;
      }
    } catch (_) {
      // Treat a platform/location-service failure like unavailable GPS.
    }

    if (context.mounted) {
      _returnToHome(context);
    }
    return false;
  }

  void _returnToHome(BuildContext context) {
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const MainShell()),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
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
                            return AppCard(
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
                              ]),
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
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 16),
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
