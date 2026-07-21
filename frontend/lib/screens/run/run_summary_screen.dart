import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../app_theme.dart';
import '../../models/run_result.dart';
import '../../providers/user_provider.dart';
import '../../providers/mission_provider.dart';
import '../../widgets/common.dart';
import 'reward_screen.dart';

const _moods = ['😩', '🙁', '🙂', '😃', '🤩'];

class RunSummaryScreen extends ConsumerStatefulWidget {
  final RunResult result;
  const RunSummaryScreen({super.key, required this.result});

  @override
  ConsumerState<RunSummaryScreen> createState() => _RunSummaryScreenState();
}

class _RunSummaryScreenState extends ConsumerState<RunSummaryScreen> {
  late RunResult result = widget.result;

  @override
  Widget build(BuildContext context) {
    final dur = result.duration;
    final mm = dur.inMinutes.remainder(60).toString().padLeft(2, '0');
    final ss = dur.inSeconds.remainder(60).toString().padLeft(2, '0');

    return Scaffold(
      body: AppBackground(
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
            child: Column(
              children: [
                const Text('🏃', style: TextStyle(fontSize: 40)),
                const SizedBox(height: 8),
                Text('วิ่งเสร็จแล้ว!', style: AppText.heading(size: 20)),
                const SizedBox(height: 4),
                Text('บอกความรู้สึกหลังวิ่งให้เราหน่อย',
                    style: AppText.body(size: 12.5, color: AppColors.textSecondary)),
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.only(top: 20),
                    child: Column(
                      children: [
                        Row(children: [
                          Expanded(child: _StatBox(value: result.distanceKm.toStringAsFixed(2), label: 'ระยะทาง (KM)')),
                          const SizedBox(width: 10),
                          Expanded(child: _StatBox(value: '$mm:$ss', label: 'เวลา')),
                        ]),
                        const SizedBox(height: 10),
                        Row(children: [
                          Expanded(child: _StatBox(value: result.avgPace, label: 'Pace เฉลี่ย')),
                          const SizedBox(width: 10),
                          Expanded(child: _StatBox(value: '${result.calories}', label: 'แคลอรี่')),
                        ]),
                        const SizedBox(height: 24),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: Text('ความหนัก RPE', style: AppText.body(size: 13, weight: FontWeight.w600)),
                        ),
                        const SizedBox(height: 10),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: List.generate(10, (i) {
                            final v = i + 1;
                            final active = result.rpe == v;
                            return GestureDetector(
                              onTap: () => setState(() => result.rpe = v),
                              child: Container(
                                width: 36,
                                height: 36,
                                alignment: Alignment.center,
                                decoration: BoxDecoration(
                                  gradient: active ? AppColors.purpleGradient : null,
                                  color: active ? null : Colors.white.withOpacity(.05),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Text('$v',
                                    style: AppText.heading(size: 13, color: active ? Colors.white : AppColors.textSecondary)),
                              ),
                            );
                          }),
                        ),
                        const SizedBox(height: 6),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: Text('ระดับ ${result.rpe} — ${result.rpe >= 9 ? "หนักสุด · หมดแรงจนไม่มีอะไรจะออกแรงแล้ว" : result.rpe >= 6 ? "หนักพอสมควร" : "เบาสบาย"}',
                              style: AppText.body(size: 11.5, color: AppColors.textTertiary)),
                        ),
                        const SizedBox(height: 20),
                        LabeledSlider(
                          label: 'ความเครียด',
                          value: result.stressLevel.toDouble(),
                          min: 0,
                          max: 10,
                          divisions: 10,
                          minCaption: 'ผ่อนคลาย',
                          maxCaption: 'เครียดมาก',
                          onChanged: (v) => setState(() => result.stressLevel = v.round()),
                        ),
                        const SizedBox(height: 20),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: Text('อารมณ์หลังวิ่ง', style: AppText.body(size: 13, weight: FontWeight.w600)),
                        ),
                        const SizedBox(height: 10),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: List.generate(_moods.length, (i) {
                            final active = result.moodIndex == i;
                            return GestureDetector(
                              onTap: () => setState(() => result.moodIndex = i),
                              child: Container(
                                width: 48,
                                height: 48,
                                alignment: Alignment.center,
                                decoration: BoxDecoration(
                                  color: active ? AppColors.purple1.withOpacity(.25) : Colors.white.withOpacity(.04),
                                  shape: BoxShape.circle,
                                  border: Border.all(color: active ? AppColors.purple2 : AppColors.border),
                                ),
                                child: Text(_moods[i], style: const TextStyle(fontSize: 20)),
                              ),
                            );
                          }),
                        ),
                        const SizedBox(height: 20),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: Text('มีอาการบาดเจ็บไหม?', style: AppText.body(size: 13, weight: FontWeight.w600)),
                        ),
                        const SizedBox(height: 10),
                        Row(children: [
                          Expanded(
                            child: GradientButton(
                              label: 'ไม่มี',
                              gradient: !result.hasInjury ? AppColors.greenGradient : null,
                              height: 46,
                              onTap: () => setState(() => result.hasInjury = false),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: OutlineButton(label: 'มีอาการ', onTap: () => setState(() => result.hasInjury = true)),
                          ),
                        ]),
                      ],
                    ),
                  ),
                ),
                GradientButton(
                  label: 'ส่งข้อมูล',
                  onTap: () {
                    ref.read(userProvider).addRunStats(km: result.distanceKm, sessions: 1);
                    ref.read(missionProvider).setDone('run', true);
                    Navigator.of(context).pushReplacement(
                      MaterialPageRoute(builder: (_) => const RewardScreen(coin: 20, exp: 50)),
                    );
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _StatBox extends StatelessWidget {
  final String value;
  final String label;
  const _StatBox({required this.value, required this.label});

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Column(
        children: [
          Text(value, style: AppText.heading(size: 20)),
          const SizedBox(height: 4),
          Text(label, style: AppText.body(size: 11.5, color: AppColors.textSecondary)),
        ],
      ),
    );
  }
}
