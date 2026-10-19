import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../app_theme.dart';
import '../../providers/onboarding_provider.dart';
import '../../services/onboarding_api.dart';
import '../../widgets/common.dart';
import 'onboarding_history_screen.dart';
import '../../models/onboarding_data.dart';

const _healthGoalOptions = [
  'ลดน้ำหนัก',
  'เพิ่มกล้ามเนื้อ',
  'เพิ่มความเร็ว',
  'เพิ่มความอึด',
  'สร้างวินัย'
];
const _distanceGoalOptions = [
  'วิ่ง 5K',
  'วิ่ง 10K',
  'Half Marathon',
  'Full Marathon'
];

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
  'เพิ่มความอึด': 'increase_endurance',
  'สร้างวินัย': 'stay_consistent',
};

const double _minPaceSecPerKm = 2 * 60 + 30;
const double _maxPaceSecPerKm = 12 * 60;

// ตัวเลือกชั่วโมง/นาทีสำหรับ dropdown
const List<int> _hourOptions = [0, 1, 2, 3, 4, 5, 6, 7, 8];
const List<int> _minuteOptions = [0, 5, 10, 15, 20, 25, 30, 35, 40, 45, 50, 55];

class OnboardingGoalScreen extends ConsumerStatefulWidget {
  const OnboardingGoalScreen({super.key});

  @override
  ConsumerState<OnboardingGoalScreen> createState() =>
      _OnboardingGoalScreenState();
}

class _OnboardingGoalScreenState extends ConsumerState<OnboardingGoalScreen> {
  int? _selectedHour;
  int? _selectedMinute;
  bool _skipTime = false;
  String? _paceError;
  bool _showValidation = false;

  @override
  void initState() {
    super.initState();
    final data = ref.read(onboardingProvider).data;
    _skipTime = data.skipTargetFinishTime;
    final parts = data.targetFinishTime.split(':');
    if (!_skipTime && parts.length == 2) {
      final hour = int.tryParse(parts[0]);
      final minute = int.tryParse(parts[1]);
      _selectedHour = _hourOptions.contains(hour) ? hour : null;
      _selectedMinute = _minuteOptions.contains(minute) ? minute : null;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final notifier = ref.read(onboardingProvider);
      _recalculate(notifier, notifier.data.distanceGoal);
    });
  }

  double? _currentPace(String? distanceGoal) {
    final km = _distanceKm[distanceGoal];
    if (_skipTime ||
        km == null ||
        !_hourOptions.contains(_selectedHour) ||
        !_minuteOptions.contains(_selectedMinute)) {
      return null;
    }
    final seconds = _selectedHour! * 3600 + _selectedMinute! * 60;
    if (seconds <= 0) return null;
    final pace = seconds / km;
    return pace >= _minPaceSecPerKm && pace <= _maxPaceSecPerKm ? pace : null;
  }

  bool _hasValidSelection(OnboardingData data) =>
      _healthGoalTypeMap.containsKey(data.healthGoal) &&
      _distanceKm.containsKey(data.distanceGoal) &&
      (_skipTime || _currentPace(data.distanceGoal) != null);

  String? _validationMessage(OnboardingData data) {
    final missingHealth = !_healthGoalTypeMap.containsKey(data.healthGoal);
    final missingDistance = !_distanceKm.containsKey(data.distanceGoal);
    if (missingHealth && missingDistance) {
      return 'กรุณากรอกเป้าหมายด้านสุขภาพและด้านระยะทาง';
    }
    if (missingHealth) return 'กรุณากรอกเป้าหมายด้านสุขภาพ';
    if (missingDistance) return 'กรุณากรอกเป้าหมายด้านระยะทาง';
    if (!_skipTime && (_selectedHour == null || _selectedMinute == null)) {
      return 'กรุณาระบุเวลาจบให้ครบ หรือเลือกไม่สนใจเวลาจบ';
    }
    if (!_skipTime && _currentPace(data.distanceGoal) == null) {
      return _paceError ?? 'กรุณาระบุเวลาจบให้ถูกต้อง';
    }
    return null;
  }

  void _recalculate(OnboardingNotifier notifier, String? distanceGoal) {
    final h = _selectedHour;
    final m = _selectedMinute;
    final distance = _distanceKm[distanceGoal];
    final hasTime = !_skipTime && distance != null && h != null && m != null;
    final seconds = hasTime ? h * 3600 + m * 60 : 0;
    final pace = _currentPace(distanceGoal);
    String? error;
    if (hasTime && seconds <= 0) {
      error = 'กรุณาเลือกเวลาที่ต้องการจบ';
    } else if (hasTime && pace == null) {
      error =
          'Pace ต้องอยู่ระหว่าง 2:30 - 12:00 นาที/กม. (ปัจจุบันคำนวณได้ ${_formatPace(seconds / distance)})';
    }
    setState(() => _paceError = error);
    notifier.update((d) {
      d.skipTargetFinishTime = _skipTime;
      d.targetFinishTime = hasTime
          ? '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}'
          : '';
      d.targetPaceSecPerKm = pace;
      d.targetSpeedKmPerSec = pace == null ? null : distance! / seconds;
    });
  }

  String _formatPace(double secPerKm) {
    final rounded = secPerKm.round();
    final m = rounded ~/ 60;
    final s = (rounded % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  Map<String, dynamic> _buildBody(OnboardingData d) {
    return {
      'goals': [
        {
          'goalType': _healthGoalTypeMap[d.healthGoal]!,
          'targetDistanceKm': _distanceKm[d.distanceGoal],
          'targetPaceSecPerKm':
              _skipTime ? null : _currentPace(d.distanceGoal)!.round(),
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

    final canProceed = _hasValidSelection(data) && !ob.isSubmitting;
    final validationMessage = _validationMessage(data);

    return Scaffold(
      body: AppBackground(
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
            child: Column(
              children: [
                Row(children: [
                  RoundIconButton(
                      icon: Icons.arrow_back,
                      onTap: () => Navigator.of(context).pop()),
                  const SizedBox(width: 12),
                  Expanded(child: OnboardingProgress(steps: 4, active: 3)),
                ]),
                const SizedBox(height: 22),
                Align(
                  alignment: Alignment.centerLeft,
                  child:
                      Text('เป้าหมายการวิ่ง', style: AppText.heading(size: 20)),
                ),
                const SizedBox(height: 4),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                      'เลือกเป้าหมายด้านสุขภาพและด้านระยะทางอย่างละ 1 ข้อ',
                      style: AppText.body(
                          size: 13, color: AppColors.textSecondary)),
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
                              style: AppText.body(
                                  size: 12.5, color: AppColors.textSecondary)),
                          const SizedBox(height: 12),
                          Wrap(
                            spacing: 10,
                            runSpacing: 10,
                            children: _distanceGoalOptions
                                .map((g) => MultiChip(
                                      label: g,
                                      selected: data.distanceGoal == g,
                                      onTap: () {
                                        if (ob.isSubmitting) return;
                                        final cleared = data.distanceGoal == g;
                                        if (cleared) {
                                          setState(() {
                                            _selectedHour = null;
                                            _selectedMinute = null;
                                            _skipTime = false;
                                            _paceError = null;
                                          });
                                        }
                                        notifier.update((d) => d.distanceGoal =
                                            cleared ? null : g);
                                        _recalculate(
                                            notifier, cleared ? null : g);
                                      },
                                    ))
                                .toList(),
                          ),
                          if (data.distanceGoal != null) ...[
                            const SizedBox(height: 22),
                            Text('ต้องการจบภายในเวลาเท่าไหร่',
                                style: AppText.body(
                                    size: 12.5,
                                    color: AppColors.textSecondary)),
                            const SizedBox(height: 10),
                            Row(
                              children: [
                                Expanded(
                                  child: DropdownButtonFormField<int>(
                                    key: ValueKey(
                                        'goal-hour-$_skipTime-$_selectedHour'),
                                    initialValue: _selectedHour,
                                    isExpanded: true,
                                    decoration: const InputDecoration(
                                      labelText: 'ชั่วโมง',
                                      border: OutlineInputBorder(),
                                    ),
                                    items: _hourOptions
                                        .map((h) => DropdownMenuItem(
                                            value: h, child: Text('$h ชม.')))
                                        .toList(),
                                    onChanged: _skipTime || ob.isSubmitting
                                        ? null
                                        : (v) {
                                            setState(() => _selectedHour = v);
                                            _recalculate(
                                                notifier, data.distanceGoal!);
                                          },
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: DropdownButtonFormField<int>(
                                    key: ValueKey(
                                        'goal-minute-$_skipTime-$_selectedMinute'),
                                    initialValue: _selectedMinute,
                                    isExpanded: true,
                                    decoration: const InputDecoration(
                                      labelText: 'นาที',
                                      border: OutlineInputBorder(),
                                    ),
                                    items: _minuteOptions
                                        .map((m) => DropdownMenuItem(
                                            value: m, child: Text('$m นาที')))
                                        .toList(),
                                    onChanged: _skipTime || ob.isSubmitting
                                        ? null
                                        : (v) {
                                            setState(() => _selectedMinute = v);
                                            _recalculate(
                                                notifier, data.distanceGoal!);
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
                                  onChanged: ob.isSubmitting
                                      ? null
                                      : (v) {
                                          setState(() {
                                            _skipTime = v ?? false;
                                            if (_skipTime) {
                                              _selectedHour = null;
                                              _selectedMinute = null;
                                              _paceError = null;
                                            }
                                          });
                                          _recalculate(
                                              notifier, data.distanceGoal!);
                                        },
                                ),
                                Text('ไม่สนใจเวลาจบ',
                                    style: AppText.body(size: 13)),
                              ],
                            ),
                            const SizedBox(height: 8),
                            if (!_skipTime && _paceError != null)
                              Text(_paceError!,
                                  style: AppText.body(
                                      size: 12, color: AppColors.red1))
                            else if (!_skipTime &&
                                data.targetPaceSecPerKm != null)
                              Text(
                                'Pace โดยประมาณ: ${_formatPace(data.targetPaceSecPerKm!)} นาที/กม.',
                                style: AppText.body(
                                    size: 12, color: AppColors.textSecondary),
                              ),
                          ],
                          const SizedBox(height: 28),
                          // ---------- โซนสุขภาพ (ย้ายมาไว้ทีหลัง) ----------
                          Text('เป้าหมายด้านสุขภาพ (เลือกได้ 1 ข้อ)',
                              style: AppText.body(
                                  size: 12.5, color: AppColors.textSecondary)),
                          const SizedBox(height: 12),
                          Wrap(
                            spacing: 10,
                            runSpacing: 10,
                            children: _healthGoalOptions
                                .map((g) => MultiChip(
                                      label: g,
                                      selected: data.healthGoal == g,
                                      onTap: () {
                                        if (ob.isSubmitting) return;
                                        notifier.update((d) => d.healthGoal =
                                            d.healthGoal == g ? null : g);
                                      },
                                    ))
                                .toList(),
                          ),
                          if (ob.errorMessage != null) ...[
                            const SizedBox(height: 16),
                            Text(ob.errorMessage!,
                                style: AppText.body(
                                    size: 12.5, color: AppColors.red1)),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
                if (_showValidation && validationMessage != null) ...[
                  Semantics(
                    liveRegion: true,
                    child: Text(validationMessage,
                        key: const Key('goal-required-message'),
                        textAlign: TextAlign.center,
                        style: AppText.body(size: 12.5, color: AppColors.red1)),
                  ),
                  const SizedBox(height: 10),
                ],
                Row(children: [
                  Expanded(
                      child: OutlineButton(
                          label: 'ย้อนกลับ',
                          onTap: () => Navigator.of(context).pop())),
                  const SizedBox(width: 12),
                  Expanded(
                    // Keep the submit button disabled, but let a tap on its
                    // area explain missing fields without sending a request.
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: canProceed || ob.isSubmitting
                          ? null
                          : () => setState(() => _showValidation = true),
                      child: GradientButton(
                        label: ob.isSubmitting ? 'กำลังบันทึก...' : 'ถัดไป',
                        onTap: canProceed
                            ? () async {
                                if (notifier.isSubmitting) return;
                                if (!_hasValidSelection(notifier.data)) {
                                  setState(() => _showValidation = true);
                                  return;
                                }
                                _recalculate(
                                    notifier, notifier.data.distanceGoal);
                                final ok = await notifier.submitStep(
                                  () => ref
                                      .read(onboardingApiProvider)
                                      .step3(_buildBody(notifier.data)),
                                );
                                if (ok && context.mounted) {
                                  Navigator.of(context).push(MaterialPageRoute(
                                      builder: (_) =>
                                          const OnboardingHistoryScreen()));
                                }
                              }
                            : null,
                      ),
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
