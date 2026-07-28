import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../app_theme.dart';
import '../../providers/onboarding_provider.dart';
import '../../services/onboarding_api.dart';
import '../../widgets/common.dart';
import 'onboarding_history_screen.dart';
import '../../models/onboarding_data.dart';

const _healthGoalOptions = ['ลดน้ำหนัก', 'เพิ่มกล้ามเนื้อ','เพิ่มความเร็ว','เพิ่มความอึด'];
const _distanceGoalOptions = ['วิ่ง 5K', 'วิ่ง 10K', 'Half Marathon', 'Full Marathon'];

const Map<String, double> _distanceKm = {
  'วิ่ง 5K': 5.0,
  'วิ่ง 10K': 10.0,
  'Half Marathon': 21.0975,
  'Full Marathon': 42.195,
};

// แมพชื่อไทยในแอป -> enum goalType ที่ API รับ
const Map<String, String> _healthGoalTypeMap = {
  'ลดน้ำหนัก': 'lose_weight',
  'เพิ่มกล้ามเนื้อ': 'build_muscle',
  'เพิ่มความเร็ว': 'increase_speed',
  'เพิ่มความอึด': 'stay_consistent',
};
const Map<String, String> _distanceGoalTypeMap = {
  'วิ่ง 5K': 'run_5k',
  'วิ่ง 10K': 'run_10k',
  'Half Marathon': 'half_marathon',
  'Full Marathon': 'marathon',
};

const double _minPaceSecPerKm = 2 * 60 + 30;
const double _maxPaceSecPerKm = 12 * 60;

// ตัวเลือกชั่วโมง/นาทีสำหรับ dropdown
const List<int> _hourOptions = [0, 1, 2, 3, 4, 5, 6, 7, 8];
const List<int> _minuteOptions = [0, 5, 10, 15, 20, 25, 30, 35, 40, 45, 50, 55];

class OnboardingGoalScreen extends ConsumerStatefulWidget {
  const OnboardingGoalScreen({super.key});

  @override
  ConsumerState<OnboardingGoalScreen> createState() => _OnboardingGoalScreenState();
}

class _OnboardingGoalScreenState extends ConsumerState<OnboardingGoalScreen> {
  int? _selectedHour;
  int? _selectedMinute;
  bool _skipTime = false;
  String? _paceError;

  @override
  void initState() {
    super.initState();
    final existing = ref.read(onboardingProvider).data.targetFinishTime;
    if (existing != null && existing.contains(':')) {
      final parts = existing.split(':');
      _selectedHour = int.tryParse(parts[0]);
      _selectedMinute = int.tryParse(parts[1]);
    }
  }

  void _recalculate(OnboardingNotifier notifier, String distanceGoal) {
    if (_skipTime) {
      setState(() => _paceError = null);
      notifier.update((d) {
        d.targetFinishTime = '';
        d.targetPaceSecPerKm = null;
        d.targetSpeedKmPerSec = null;
      });
      return;
    }

    final h = _selectedHour;
    final m = _selectedMinute;

    if (h == null || m == null) {
      setState(() => _paceError = null);
      notifier.update((d) {
        d.targetFinishTime = '';
        d.targetPaceSecPerKm = null;
        d.targetSpeedKmPerSec = null;
      });
      return;
    }

    final finishSeconds = (h * 3600 + m * 60).toDouble();
    final distanceKm = _distanceKm[distanceGoal]!;

    if (finishSeconds <= 0) {
      setState(() => _paceError = 'กรุณาเลือกเวลาที่ต้องการจบ');
      notifier.update((d) {
        d.targetFinishTime = '$h:$m';
        d.targetPaceSecPerKm = null;
        d.targetSpeedKmPerSec = null;
      });
      return;
    }

    final paceSecPerKm = finishSeconds / distanceKm;

    if (paceSecPerKm < _minPaceSecPerKm || paceSecPerKm > _maxPaceSecPerKm) {
      setState(() =>
          _paceError = 'Pace ต้องอยู่ระหว่าง 2:30 - 12:00 นาที/กม. (ปัจจุบันคำนวณได้ ${_formatPace(paceSecPerKm)})');
      notifier.update((d) {
        d.targetFinishTime = '$h:$m';
        d.targetPaceSecPerKm = null;
        d.targetSpeedKmPerSec = null;
      });
      return;
    }

    setState(() => _paceError = null);
    notifier.update((d) {
      d.targetFinishTime = '$h:$m';
      d.targetPaceSecPerKm = paceSecPerKm;
      d.targetSpeedKmPerSec = distanceKm / finishSeconds;
    });
  }

  String _formatPace(double secPerKm) {
    final m = (secPerKm ~/ 60);
    final s = (secPerKm % 60).round().toString().padLeft(2, '0');
    return '$m:$s';
  }

  Map<String, dynamic> _buildBody(OnboardingData d) {
    return {
      'goals': [
        if (d.healthGoal != null)
          {
            'goalType': _healthGoalTypeMap[d.healthGoal]!,
            'targetDistanceKm': null,
            'targetPaceSecPerKm': null,
            'isPrimary': d.distanceGoal == null,
          },
        if (d.distanceGoal != null)
          {
            'goalType': _distanceGoalTypeMap[d.distanceGoal]!,
            'targetDistanceKm': _distanceKm[d.distanceGoal],
            'targetPaceSecPerKm': d.targetPaceSecPerKm?.round(),
            'isPrimary': true,
          },
      ],
    };
  }

  @override
  Widget build(BuildContext context) {
    final notifier = ref.read(onboardingProvider);
    final ob = ref.watch(onboardingProvider);
    final data = ob.data;

    final hasAnyGoal = data.healthGoal != null || data.distanceGoal != null;
    // ต้องกรอกเวลาให้ครบเฉพาะตอนเลือกระยะทางแล้ว และยังไม่ได้ติ๊ก "ไม่สนใจเวลาจบ"
    final needsValidTime = data.distanceGoal != null && !_skipTime;
    final canProceed =
        hasAnyGoal && (!needsValidTime || data.targetSpeedKmPerSec != null) && !ob.isSubmitting;

    return Scaffold(
      body: AppBackground(
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
            child: Column(
              children: [
                Row(children: [
                  RoundIconButton(icon: Icons.arrow_back, onTap: () => Navigator.of(context).pop()),
                  const SizedBox(width: 12),
                  Expanded(child: OnboardingProgress(steps: 4, active: 3)),
                ]),
                const SizedBox(height: 22),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text('เป้าหมายการวิ่ง', style: AppText.heading(size: 20)),
                ),
                const SizedBox(height: 4),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text('เลือกอย่างน้อย 1 อย่าง จากด้านสุขภาพ หรือ ด้านระยะทาง',
                      style: AppText.body(size: 13, color: AppColors.textSecondary)),
                ),
                Expanded(
                  child: SingleChildScrollView(
                    child: Padding(
                      padding: const EdgeInsets.only(top: 22),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // ---------- โซนระยะทาง (ขึ้นก่อน) ----------
                          Text('เป้าหมายด้านระยะทาง (เลือกได้ 1 ข้อ)',
                              style: AppText.body(size: 12.5, color: AppColors.textSecondary)),
                          const SizedBox(height: 12),
                          Wrap(
                            spacing: 10,
                            runSpacing: 10,
                            children: _distanceGoalOptions
                                .map((g) => MultiChip(
                                      label: g,
                                      selected: data.distanceGoal == g,
                                      onTap: () => notifier.update((d) {
                                        final cleared = d.distanceGoal == g;
                                        d.distanceGoal = cleared ? null : g;
                                        if (cleared) {
                                          d.targetFinishTime = '';
                                          d.targetPaceSecPerKm = null;
                                          d.targetSpeedKmPerSec = null;
                                          setState(() {
                                            _selectedHour = null;
                                            _selectedMinute = null;
                                            _skipTime = false;
                                            _paceError = null;
                                          });
                                        }
                                      }),
                                    ))
                                .toList(),
                          ),
                          if (data.distanceGoal != null) ...[
                            const SizedBox(height: 22),
                            Text('ต้องการจบภายในเวลาเท่าไหร่',
                                style: AppText.body(size: 12.5, color: AppColors.textSecondary)),
                            const SizedBox(height: 10),
                            Row(
                              children: [
                                Expanded(
                                  child: DropdownButtonFormField<int>(
                                    value: _selectedHour,
                                    isExpanded: true,
                                    decoration: const InputDecoration(
                                      labelText: 'ชั่วโมง',
                                      border: OutlineInputBorder(),
                                    ),
                                    items: _hourOptions
                                        .map((h) => DropdownMenuItem(value: h, child: Text('$h ชม.')))
                                        .toList(),
                                    onChanged: _skipTime
                                        ? null
                                        : (v) {
                                            setState(() => _selectedHour = v);
                                            _recalculate(notifier, data.distanceGoal!);
                                          },
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: DropdownButtonFormField<int>(
                                    value: _selectedMinute,
                                    isExpanded: true,
                                    decoration: const InputDecoration(
                                      labelText: 'นาที',
                                      border: OutlineInputBorder(),
                                    ),
                                    items: _minuteOptions
                                        .map((m) => DropdownMenuItem(value: m, child: Text('$m นาที')))
                                        .toList(),
                                    onChanged: _skipTime
                                        ? null
                                        : (v) {
                                            setState(() => _selectedMinute = v);
                                            _recalculate(notifier, data.distanceGoal!);
                                          },
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            Row(
                              children: [
                                Checkbox(
                                  value: _skipTime,
                                  onChanged: (v) {
                                    setState(() {
                                      _skipTime = v ?? false;
                                      if (_skipTime) {
                                        _selectedHour = null;
                                        _selectedMinute = null;
                                        _paceError = null;
                                      }
                                    });
                                    _recalculate(notifier, data.distanceGoal!);
                                  },
                                ),
                                Text('ไม่สนใจเวลาจบ', style: AppText.body(size: 13)),
                              ],
                            ),
                            const SizedBox(height: 8),
                            if (!_skipTime && _paceError != null)
                              Text(_paceError!, style: AppText.body(size: 12, color: AppColors.red1))
                            else if (!_skipTime && data.targetPaceSecPerKm != null)
                              Text(
                                'Pace โดยประมาณ: ${_formatPace(data.targetPaceSecPerKm!)} นาที/กม.',
                                style: AppText.body(size: 12, color: AppColors.textSecondary),
                              ),
                          ],
                          const SizedBox(height: 28),
                          // ---------- โซนสุขภาพ (ย้ายมาไว้ทีหลัง) ----------
                          Text('เป้าหมายด้านสุขภาพ (เลือกได้ 1 ข้อ)',
                              style: AppText.body(size: 12.5, color: AppColors.textSecondary)),
                          const SizedBox(height: 12),
                          Wrap(
                            spacing: 10,
                            runSpacing: 10,
                            children: _healthGoalOptions
                                .map((g) => MultiChip(
                                      label: g,
                                      selected: data.healthGoal == g,
                                      onTap: () => notifier.update(
                                          (d) => d.healthGoal = d.healthGoal == g ? null : g),
                                    ))
                                .toList(),
                          ),
                          if (ob.errorMessage != null) ...[
                            const SizedBox(height: 16),
                            Text(ob.errorMessage!, style: AppText.body(size: 12.5, color: AppColors.red1)),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
                Row(children: [
                  Expanded(child: OutlineButton(label: 'ย้อนกลับ', onTap: () => Navigator.of(context).pop())),
                  const SizedBox(width: 12),
                  Expanded(
                    child: GradientButton(
                      label: ob.isSubmitting ? 'กำลังบันทึก...' : 'ถัดไป',
                      onTap: canProceed
                          ? () async {
                              final ok = await notifier.submitStep(
                                () => ref.read(onboardingApiProvider).step3(_buildBody(data)),
                              );
                              if (ok && context.mounted) {
                                Navigator.of(context)
                                    .push(MaterialPageRoute(builder: (_) => const OnboardingHistoryScreen()));
                              }
                            }
                          : null,
                    ),
                  ),
                ]),
              ],
            ),
          ),
        ),
      ),
    );
  }
}