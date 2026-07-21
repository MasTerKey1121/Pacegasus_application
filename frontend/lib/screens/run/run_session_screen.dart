import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../app_theme.dart';
import '../../providers/run_provider.dart';
import '../../widgets/common.dart';
import 'run_summary_screen.dart';

class RunSessionScreen extends ConsumerStatefulWidget {
  const RunSessionScreen({super.key});

  @override
  ConsumerState<RunSessionScreen> createState() => _RunSessionScreenState();
}

class _RunSessionScreenState extends ConsumerState<RunSessionScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => ref.read(runProvider).start());
  }

  @override
  Widget build(BuildContext context) {
    final run = ref.watch(runProvider);

    return Scaffold(
      backgroundColor: AppColors.bg1,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _Stat(value: run.distanceKm.toStringAsFixed(2), label: 'กม.'),
                  _Stat(value: run.elapsedLabel, label: 'เวลา'),
                  _Stat(value: run.distanceKm > 0 ? '${(run.elapsedSeconds / 60 / run.distanceKm).toStringAsFixed(1)}' : '--:--', label: 'pace'),
                ],
              ),
              const SizedBox(height: 22),
              Expanded(
                child: Container(
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: const Color(0xFF211B3D),
                    borderRadius: BorderRadius.circular(24),
                  ),
                  child: Center(
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 300),
                      width: 26,
                      height: 26,
                      decoration: BoxDecoration(
                        color: AppColors.purple2,
                        shape: BoxShape.circle,
                        boxShadow: [BoxShadow(color: AppColors.purple1.withOpacity(.5), blurRadius: 18, spreadRadius: 6)],
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 18),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('ระยะทางที่เหลือ', style: AppText.body(size: 11.5, color: AppColors.textTertiary)),
                      Text('${run.distanceKm.toStringAsFixed(1)} / ${run.goalDistanceKm.toStringAsFixed(0)} km',
                          style: AppText.heading(size: 13.5)),
                    ],
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text('เป้าหมาย', style: AppText.body(size: 11.5, color: AppColors.textTertiary)),
                      Text(run.goalPace, style: AppText.heading(size: 13.5)),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  GestureDetector(
                    onTap: () => ref.read(runProvider).togglePause(),
                    child: Container(
                      width: 54,
                      height: 54,
                      decoration: BoxDecoration(
                        color: AppColors.card,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: AppColors.border),
                      ),
                      child: Icon(run.isPaused ? Icons.play_arrow_rounded : Icons.pause_rounded, color: Colors.white),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: GradientButton(
                      label: '■ จบการวิ่ง',
                      gradient: LinearGradient(colors: [AppColors.red1, AppColors.red2]),
                      onTap: () {
                        final result = ref.read(runProvider).stop();
                        Navigator.of(context).pushReplacement(
                          MaterialPageRoute(builder: (_) => RunSummaryScreen(result: result)),
                        );
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                run.isPaused ? 'หยุดชั่วคราว · ${run.elapsedLabel}' : 'กำลังวิ่ง · ${run.elapsedLabel}',
                style: AppText.body(size: 11.5, color: AppColors.textTertiary),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  final String value;
  final String label;
  const _Stat({required this.value, required this.label});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(value, style: AppText.heading(size: 22)),
        const SizedBox(height: 2),
        Text(label, style: AppText.body(size: 11.5, color: AppColors.textTertiary)),
      ],
    );
  }
}
