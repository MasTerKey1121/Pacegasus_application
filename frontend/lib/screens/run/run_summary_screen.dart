import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../app_theme.dart';
import '../../models/run_result.dart';
import '../../providers/user_provider.dart';
import '../../providers/mission_provider.dart';
import '../../widgets/common.dart';
import 'reward_screen.dart';
import '../../providers/run_setup_provider.dart';
import '../../providers/rpe_provider.dart';
import '../../services/api_client.dart';

const _moods = ['😩', '🙁', '🙂', '😃', '🤩'];

class RunSummaryScreen extends ConsumerStatefulWidget {
  final RunResult result;
  const RunSummaryScreen({super.key, required this.result});

  @override
  ConsumerState<RunSummaryScreen> createState() => _RunSummaryScreenState();
}

class _RunSummaryScreenState extends ConsumerState<RunSummaryScreen> {
  late RunResult result = widget.result;
  bool _isSubmitting = false;
  final _painNoteController = TextEditingController();

  static const _apiMoods = [
    'exhausted',
    'bad',
    'neutral',
    'good',
    'great',
  ];

  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final setup = ref.read(runSetupProvider);
      final sessionId = setup.sessionId;

      // โหลดข้อมูลจริงจาก Backend
      if (sessionId != null) {
        try {
          final detail = await ref
              .read(runningSessionApiProvider)
              .getDetail(sessionId: sessionId);
          final data = detail['data'];
          if (mounted && data is Map) {
            // PostgreSQL returns snake_case while older API responses used
            // camelCase. Accept both so this screen always shows the session
            // the runner has just completed.
            final distance = _asDouble(
              data['distanceKm'] ?? data['distance_km'],
              result.distanceKm,
            );
            final durationSeconds = _asInt(
              data['durationSeconds'] ?? data['duration_seconds'],
              result.duration.inSeconds,
            );
            setState(() {
              result = RunResult(
                distanceKm: distance,
                duration: Duration(seconds: durationSeconds),
                avgPace: _paceLabel(distance, durationSeconds),
                calories: (distance * 62).round(),
                rpe: result.rpe,
                stressLevel: result.stressLevel,
                moodIndex: result.moodIndex,
                hasInjury: result.hasInjury,
              );
            });
          }
        } catch (error) {
          debugPrint('Could not load completed running session: $error');
        }
      }

      // อัปเดต Progress ของ Side Quest
      for (final id in setup.sideQuestIds) {
        await ref.read(questApiProvider).updateSideQuestProgress(
              sideQuestId: id,
              progressCount: 1,
            );
      }
    });
  }

  @override
  void dispose() {
    _painNoteController.dispose();
    super.dispose();
  }

  double _asDouble(Object? value, double fallback) => value is num
      ? value.toDouble()
      : double.tryParse(value?.toString() ?? '') ?? fallback;

  int _asInt(Object? value, int fallback) => value is num
      ? value.toInt()
      : int.tryParse(value?.toString() ?? '') ?? fallback;

  String _paceLabel(double distanceKm, int durationSeconds) {
    if (distanceKm <= 0 || durationSeconds <= 0) return '--:--';
    final totalSeconds = (durationSeconds / distanceKm).round();
    final minutes = totalSeconds ~/ 60;
    final seconds = (totalSeconds % 60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

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
                    style: AppText.body(
                        size: 12.5, color: AppColors.textSecondary)),
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.only(top: 20),
                    child: Column(
                      children: [
                        Row(children: [
                          Expanded(
                              child: _StatBox(
                                  value: result.distanceKm.toStringAsFixed(2),
                                  label: 'ระยะทาง (KM)')),
                          const SizedBox(width: 10),
                          Expanded(
                              child: _StatBox(value: '$mm:$ss', label: 'เวลา')),
                        ]),
                        const SizedBox(height: 10),
                        Row(children: [
                          Expanded(
                              child: _StatBox(
                                  value: result.avgPace, label: 'Pace เฉลี่ย')),
                          const SizedBox(width: 10),
                          Expanded(
                              child: _StatBox(
                                  value: '${result.calories}',
                                  label: 'แคลอรี่')),
                        ]),
                        const SizedBox(height: 24),
                        LabeledSlider(
                          label: 'ความหนัก RPE',
                          value: result.rpe.toDouble(),
                          min: 1,
                          max: 10,
                          divisions: 9,
                          minCaption: 'เบาสบาย',
                          maxCaption: 'หนักสุด',
                          onChanged: (value) =>
                              setState(() => result.rpe = value.round()),
                        ),
                        const SizedBox(height: 6),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            'ระดับ ${result.rpe} — ${result.rpe >= 9 ? "หนักสุด · หมดแรงจนไม่มีอะไรจะออกแรงแล้ว" : result.rpe >= 6 ? "หนักพอสมควร" : "เบาสบาย"}',
                            style: AppText.body(
                              size: 11.5,
                              color: AppColors.textTertiary,
                            ),
                          ),
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
                          onChanged: (v) =>
                              setState(() => result.stressLevel = v.round()),
                        ),
                        const SizedBox(height: 20),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: Text('อารมณ์หลังวิ่ง',
                              style: AppText.body(
                                  size: 13, weight: FontWeight.w600)),
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
                                  color: active
                                      ? AppColors.purple1.withOpacity(.25)
                                      : Colors.white.withOpacity(.04),
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                      color: active
                                          ? AppColors.purple2
                                          : AppColors.border),
                                ),
                                child: Text(_moods[i],
                                    style: const TextStyle(fontSize: 20)),
                              ),
                            );
                          }),
                        ),
                        const SizedBox(height: 20),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: Text('มีอาการบาดเจ็บไหม?',
                              style: AppText.body(
                                  size: 13, weight: FontWeight.w600)),
                        ),
                        const SizedBox(height: 10),
                        Row(children: [
                          Expanded(
                            child: GradientButton(
                              label: 'ไม่มี',
                              gradient: !result.hasInjury
                                  ? AppColors.greenGradient
                                  : null,
                              height: 46,
                              onTap: () =>
                                  setState(() => result.hasInjury = false),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: OutlineButton(
                                label: 'มีอาการ',
                                onTap: () =>
                                    setState(() => result.hasInjury = true)),
                          ),
                        ]),
                        if (result.hasInjury) ...[
                          const SizedBox(height: 12),
                          TextField(
                            controller: _painNoteController,
                            maxLength: 1000,
                            maxLines: 3,
                            style: AppText.body(size: 13),
                            decoration: InputDecoration(
                              hintText: 'ระบุอาการหรือบริเวณที่เจ็บ',
                              hintStyle: AppText.body(
                                size: 12.5,
                                color: AppColors.textTertiary,
                              ),
                              filled: true,
                              fillColor: Colors.white.withOpacity(.05),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: BorderSide(color: AppColors.border),
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                GradientButton(
                  label: 'ส่งข้อมูล',
                  loading: _isSubmitting,
                  onTap: _isSubmitting
                      ? null
                      : () async {
                          final sessionId =
                              ref.read(runSetupProvider).sessionId;
                          if (sessionId == null) {
                            showAppToast(
                              context,
                              'ไม่พบข้อมูลการวิ่ง กรุณาลองเริ่มการวิ่งใหม่',
                            );
                            return;
                          }
                          final painNote = _painNoteController.text.trim();
                          if (result.hasInjury && painNote.isEmpty) {
                            showAppToast(
                              context,
                              'กรุณาระบุอาการหรือบริเวณที่เจ็บ',
                            );
                            return;
                          }

                          setState(() => _isSubmitting = true);
                          try {
                            await ref.read(rpeApiProvider).logRunFeedback(
                                  runningSessionId: sessionId,
                                  durationMinutes: result.duration.inMinutes
                                      .clamp(1, 1440)
                                      .toInt(),
                                  rpeScore: result.rpe,
                                  stressLevel: result.stressLevel
                                      .clamp(1, 10)
                                      .toInt(),
                                  mood: _apiMoods[
                                    result.moodIndex.clamp(0, 4).toInt()
                                  ],
                                  hasPain: result.hasInjury,
                                  painNote: painNote,
                                );
                            if (!mounted) return;
                            ref
                                .read(userProvider)
                                .addRunStats(km: result.distanceKm, sessions: 1);
                            ref.read(missionProvider).setDone('run', true);
                            ref.read(runSetupProvider).reset();
                            Navigator.of(context).pushReplacement(
                              MaterialPageRoute(
                                builder: (_) =>
                                    const RewardScreen(coin: 20, exp: 50),
                              ),
                            );
                          } on ApiException catch (error) {
                            if (mounted) {
                              showAppToast(
                                context,
                                'บันทึกข้อมูลหลังวิ่งไม่สำเร็จ: ${error.message}',
                              );
                            }
                          } catch (_) {
                            if (mounted) {
                              showAppToast(
                                context,
                                'บันทึกข้อมูลหลังวิ่งไม่สำเร็จ กรุณาลองอีกครั้ง',
                              );
                            }
                          } finally {
                            if (mounted) setState(() => _isSubmitting = false);
                          }
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
          Text(label,
              style: AppText.body(size: 11.5, color: AppColors.textSecondary)),
        ],
      ),
    );
  }
}
