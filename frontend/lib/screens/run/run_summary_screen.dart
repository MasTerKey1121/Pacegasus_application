import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../app_theme.dart';
import '../../models/run_result.dart';
import '../../models/run_reward.dart';
import '../../providers/progress_provider.dart';
import '../../providers/auth_provider.dart';
import '../../providers/user_provider.dart';
import '../../providers/mission_provider.dart';
import '../../widgets/common.dart';
import 'reward_screen.dart';
import '../../widgets/run_route_map.dart';
import '../../providers/run_setup_provider.dart';
import '../../providers/run_rewards_provider.dart';
import '../../providers/daily_quest_provider.dart';
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
  bool _submitted = false;
  bool _routeLoading = false;
  bool _routeFailed = false;
  bool _isTreadmill = false;
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

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _loadSession();
    });
  }

  Future<void> _loadSession() async {
    final setup = ref.read(runSetupProvider);
    final sessionId = setup.sessionId;
    setState(() {
      _routeFailed = false;
      _isTreadmill = setup.environment == 'treadmill';
      _routeLoading = sessionId != null && result.routePoints.isEmpty;
    });

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
          final route =
              RunRoutePoint.parse(data['routePoints'] ?? data['route_points']);
          setState(() {
            _isTreadmill =
                (data['environment'] ?? setup.environment) == 'treadmill';
            result = RunResult(
              distanceKm: distance,
              duration: Duration(seconds: durationSeconds),
              avgPace: _paceLabel(distance, durationSeconds),
              calories: (distance * 62).round(),
              routePoints: route.isEmpty ? result.routePoints : route,
              rpe: result.rpe,
              stressLevel: result.stressLevel,
              moodIndex: result.moodIndex,
              hasInjury: result.hasInjury,
            );
          });
        }
      } catch (error) {
        debugPrint('Could not load completed running session: $error');
        if (mounted) setState(() => _routeFailed = true);
      } finally {
        if (mounted) setState(() => _routeLoading = false);
      }
    }
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
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.only(bottom: 20),
                    child: Column(
                      children: [
                        RunRouteMap(
                            sessionId: ref.watch(runSetupProvider).sessionId,
                            points: result.routePoints,
                            loading: _routeLoading,
                            loadFailed: _routeFailed,
                            onRetry: _loadSession,
                            treadmill: _isTreadmill),
                        const SizedBox(height: 16),
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
                          value: (result.rpe ?? 1).toDouble(),
                          min: 1,
                          max: 10,
                          divisions: 9,
                          minCaption: 'เบาสบาย',
                          maxCaption: 'หนักสุด',
                          displayText: result.rpe == null ? '—' : null,
                          onChanged: (value) =>
                              setState(() => result.rpe = value.round()),
                        ),
                        const SizedBox(height: 6),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            result.rpe == null
                                ? 'กรุณาเลือกระดับความหนัก'
                                : 'ระดับ ${result.rpe} — ${result.rpe! >= 9 ? "หนักสุด · หมดแรงจนไม่มีอะไรจะออกแรงแล้ว" : result.rpe! >= 6 ? "หนักพอสมควร" : "เบาสบาย"}',
                            style: AppText.body(
                              size: 11.5,
                              color: AppColors.textTertiary,
                            ),
                          ),
                        ),
                        const SizedBox(height: 20),
                        LabeledSlider(
                          label: 'ความเครียด',
                          value: (result.stressLevel ?? 1).toDouble(),
                          min: 1,
                          max: 10,
                          divisions: 10,
                          minCaption: 'ผ่อนคลาย',
                          maxCaption: 'เครียดมาก',
                          displayText: result.stressLevel == null ? '—' : null,
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
                              key: Key('run-mood-$i'),
                              onTap: () => setState(() => result.moodIndex = i),
                              child: Container(
                                width: 48,
                                height: 48,
                                alignment: Alignment.center,
                                decoration: BoxDecoration(
                                  color: active
                                      ? AppColors.purple1.withValues(alpha: .25)
                                      : Colors.white.withValues(alpha: .04),
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
                            child: _InjuryChoice(
                                label: 'ไม่มี',
                                selected: result.hasInjury == false,
                                onPressed: () =>
                                    setState(() => result.hasInjury = false)),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                              child: _InjuryChoice(
                                  label: 'มีอาการ',
                                  selected: result.hasInjury == true,
                                  onPressed: () =>
                                      setState(() => result.hasInjury = true))),
                        ]),
                        if (result.hasInjury == true) ...[
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
                              fillColor: Colors.white.withValues(alpha: .05),
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
                  onTap: _isSubmitting ||
                          result.rpe == null ||
                          result.stressLevel == null ||
                          result.moodIndex == null ||
                          result.hasInjury == null
                      ? null
                      : () async {
                          if (_isSubmitting || _submitted) return;
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
                          if (result.hasInjury == true && painNote.isEmpty) {
                            showAppToast(
                              context,
                              'กรุณาระบุอาการหรือบริเวณที่เจ็บ',
                            );
                            return;
                          }

                          final owner = ref.read(authProvider).user?['id'];
                          setState(() => _isSubmitting = true);
                          try {
                            final history = await ref
                                .read(runningSessionApiProvider)
                                .history();
                            if (!mounted ||
                                ref.read(authProvider).user?['id'] != owner) {
                              return;
                            }
                            final sessions =
                                ((history['data'] as Map)['sessions'] as List)
                                    .whereType<Map>();
                            final previous =
                                sessions.where((s) => s['id'] == sessionId);
                            final alreadySaved = previous.isNotEmpty &&
                                (previous.first['rpe_logs'] as List? ?? [])
                                    .isNotEmpty;
                            Map<String, dynamic> response = {};
                            if (!alreadySaved) {
                              response = await ref
                                  .read(rpeApiProvider)
                                  .logRunFeedback(
                                    runningSessionId: sessionId,
                                    durationMinutes: result.duration.inMinutes
                                        .clamp(1, 1440)
                                        .toInt(),
                                    rpeScore: result.rpe!,
                                    stressLevel: result.stressLevel!
                                        .clamp(1, 10)
                                        .toInt(),
                                    mood: _apiMoods[
                                        result.moodIndex!.clamp(0, 4).toInt()],
                                    hasPain: result.hasInjury!,
                                    painNote: painNote,
                                  );
                            }
                            if (!context.mounted ||
                                ref.read(authProvider).user?['id'] != owner) {
                              return;
                            }
                            await ref.read(dailyQuestProvider).refresh();
                            if (!mounted ||
                                ref.read(authProvider).user?['id'] != owner) {
                              return;
                            }
                            final ledger = ref.read(runRewardsProvider);
                            await ledger.load(sessionId);
                            final reward = RunReward.fromFeedback(response);
                            if (reward != null && response['data'] is Map) {
                              final id = response['data']['id']?.toString() ??
                                  sessionId;
                              await ledger.record(RewardReceipt(
                                  'แบบสอบถามหลังวิ่ง',
                                  id,
                                  sessionId,
                                  reward.coins,
                                  reward.exp));
                            } else if (!ledger.hasSource(
                                sessionId, 'แบบสอบถามหลังวิ่ง')) {
                              await ledger.expectSource(
                                  sessionId, 'แบบสอบถามหลังวิ่ง');
                            }
                            final currentSetup = ref.read(runSetupProvider);
                            for (final side
                                in currentSetup.rewardsForSession(sessionId)) {
                              await ledger.record(RewardReceipt('Side Quest',
                                  side.questId, sessionId, side.coins, null));
                            }
                            final daily = ref.read(dailyQuestProvider);
                            if (currentSetup.mainQuestAtStart != null &&
                                daily.completed &&
                                daily.quest?['id']?.toString() ==
                                    currentSetup.mainQuestAtStart) {
                              await ledger.expectSource(
                                  sessionId, 'Main Quest');
                            }
                            if (!mounted ||
                                ref.read(authProvider).user?['id'] != owner) {
                              return;
                            }
                            ref.invalidate(progressProvider);
                            ref.read(userProvider).addRunStats(
                                km: result.distanceKm, sessions: 1);
                            ref.read(missionProvider).setDone('run', true);
                            final sideRewards = ref
                                .read(runSetupProvider)
                                .rewardsForSession(sessionId);
                            ref.read(runSetupProvider).reset();
                            _submitted = true;
                            Navigator.of(context).pushReplacement(
                              MaterialPageRoute(
                                builder: (_) => RewardScreen(
                                    sessionId: sessionId,
                                    coin: reward?.coins,
                                    exp: reward?.exp,
                                    sideRewards: sideRewards),
                              ),
                            );
                          } on ApiException catch (error) {
                            if (context.mounted) {
                              showAppToast(
                                context,
                                'ยังตรวจผลบันทึกหลังวิ่งไม่ได้ กรุณาลองใหม่: ${error.message}',
                              );
                            }
                          } catch (_) {
                            if (context.mounted) {
                              showAppToast(
                                context,
                                'ตรวจหรือเก็บรายละเอียดรางวัลไม่สำเร็จ กรุณาลองใหม่ ระบบจะตรวจสถานะก่อนส่งอีกครั้ง',
                              );
                            }
                          } finally {
                            if (mounted && !_submitted) {
                              setState(() => _isSubmitting = false);
                            }
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

class _InjuryChoice extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onPressed;
  const _InjuryChoice(
      {required this.label, required this.selected, required this.onPressed});
  @override
  Widget build(BuildContext context) => Semantics(
      selected: selected,
      button: true,
      child: SizedBox(
          height: 48,
          child: OutlinedButton(
              style: OutlinedButton.styleFrom(
                  backgroundColor:
                      selected ? const Color(0xFF268DDB) : AppColors.cardHi,
                  foregroundColor: AppColors.textPrimary,
                  side: BorderSide(
                      color: selected
                          ? const Color(0xFF64BEFF)
                          : AppColors.border),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(24))),
              onPressed: onPressed,
              child: Text(label,
                  style: AppText.body(size: 13, weight: FontWeight.w600)))));
}
