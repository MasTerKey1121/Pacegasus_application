import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../app_theme.dart';
import '../../models/training_models.dart';
import '../../providers/training_plan_provider.dart';
import '../../providers/user_provider.dart';
import '../../widgets/common.dart';

const _dayLabels = ['จ', 'อ', 'พ', 'พฤ', 'ศ', 'ส', 'อา'];
const _typeOrder = [SessionType.easy, SessionType.vo2max, SessionType.tempo, SessionType.long];
const _phaseOrder = [PlanPhase.base, PlanPhase.build, PlanPhase.peak, PlanPhase.taper, PlanPhase.race];

class TrainingScheduleScreen extends ConsumerStatefulWidget {
  const TrainingScheduleScreen({super.key});

  @override
  ConsumerState<TrainingScheduleScreen> createState() => _TrainingScheduleScreenState();
}

class _TrainingScheduleScreenState extends ConsumerState<TrainingScheduleScreen> {
  bool rulesExpanded = false;

  @override
  Widget build(BuildContext context) {
    final notifier = ref.read(trainingPlanProvider);
    final plan = ref.watch(trainingPlanProvider);
    final phase = notifier.getPhase(plan.currentWeek);
    final caps = notifier.getCaps(plan.currentWeek);
    final week = plan.currentWeekData;

    return Scaffold(
      body: AppBackground(
        child: SafeArea(
          child: Stack(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 110),
                child: ListView(
                  children: [
                    Row(children: [
                      RoundIconButton(icon: Icons.arrow_back, onTap: () => Navigator.of(context).pop()),
                      const SizedBox(width: 14),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('ตารางซ้อม', style: AppText.heading(size: 19)),
                          Text('แผน Intermediate 10K · Sub 1:40',
                              style: AppText.body(size: 12, color: AppColors.textSecondary)),
                        ],
                      ),
                    ]),
                    const SizedBox(height: 20),

                    AppCard(
                      borderColor: AppColors.purple2.withOpacity(.3),
                      backgroundGradient: LinearGradient(
                        colors: [AppColors.purple1.withOpacity(.16), AppColors.purple2.withOpacity(.03)],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
                            _Badge('Intermediate'),
                            Text('เป้าหมาย 10K · Sub 1:40 · 8–10 สัปดาห์', style: AppText.heading(size: 14.5)),
                          ]),
                          const SizedBox(height: 10),
                          Text(
                            'แผนนี้พาคุณไล่ระดับความหนักเป็นขั้นบันได แล้วค่อยผ่อนก่อนวันแข่งจริง',
                            style: AppText.body(size: 12.5, color: AppColors.textSecondary),
                          ),
                          const SizedBox(height: 12),
                          Wrap(
                            spacing: 4,
                            runSpacing: 6,
                            children: [
                              for (int i = 0; i < _phaseOrder.length; i++) ...[
                                _PhaseNode(_phaseOrder[i]),
                                if (i != _phaseOrder.length - 1)
                                  Padding(
                                    padding: const EdgeInsets.symmetric(horizontal: 2),
                                    child: Text('→', style: AppText.body(size: 11, color: AppColors.textTertiary)),
                                  ),
                              ],
                            ],
                          ),
                        ],
                      ),
                    ),

                    const SectionLabel(title: 'แผนการฝึกของคุณ'),
                    AppCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('ระยะเวลาแผนฝึก',
                              style: AppText.body(size: 11.5, color: AppColors.textSecondary, weight: FontWeight.w600)),
                          const SizedBox(height: 10),
                          Wrap(
                            spacing: 8,
                            children: TrainingPlanNotifier.availablePlanLengths
                                .map((w) => SelectChip(
                                      label: '$w สัปดาห์',
                                      active: plan.planWeeks == w,
                                      onTap: () => notifier.setPlanWeeks(w),
                                    ))
                                .toList(),
                          ),
                          const SizedBox(height: 10),
                          Text('Base → Build → Peak (สลับ VO2Max/Tempo ทุกสัปดาห์) → Taper → Race',
                              style: AppText.body(size: 12, color: AppColors.textSecondary)),
                          const SizedBox(height: 20),
                          Text('องค์ประกอบการซ้อม — ${phase.label}',
                              style: AppText.body(size: 11.5, color: AppColors.textSecondary, weight: FontWeight.w600)),
                          const SizedBox(height: 10),
                          Column(
                            children: [
                              for (final type in _typeOrder)
                                if (caps.capFor(type) > 0) _TypeCard(type: type, phase: phase, cap: caps.capFor(type)),
                              if (phase == PlanPhase.race)
                                const _RaceInfoCard(),
                            ],
                          ),
                          const SizedBox(height: 14),
                          Container(
                            padding: const EdgeInsets.all(13),
                            decoration: BoxDecoration(
                              color: AppColors.purple2.withOpacity(.08),
                              border: Border.all(color: AppColors.purple2.withOpacity(.22)),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              _minNoteText(phase),
                              style: AppText.body(size: 11.5, color: AppColors.textSecondary),
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 14),
                    _RulesCard(expanded: rulesExpanded, onToggle: () => setState(() => rulesExpanded = !rulesExpanded)),

                    const SectionLabel(title: 'จัดตารางรายสัปดาห์'),
                    SizedBox(
                      height: 40,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        itemCount: _phaseOrder.length,
                        separatorBuilder: (_, __) => const SizedBox(width: 8),
                        itemBuilder: (context, i) {
                          final p = _phaseOrder[i];
                          final active = p == phase;
                          final start = notifier.phaseStartWeeks[p]!;
                          return GestureDetector(
                            onTap: () => notifier.goToWeek(start),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 14),
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                gradient: active ? AppColors.purpleGradient : null,
                                color: active ? null : AppColors.card,
                                border: Border.all(color: active ? Colors.transparent : AppColors.border),
                                borderRadius: BorderRadius.circular(999),
                              ),
                              child: Text('${p.shortNumber} ${p.label.split(" ").first}',
                                  style: AppText.heading(size: 12.5, color: active ? Colors.white : AppColors.textSecondary)),
                            ),
                          );
                        },
                      ),
                    ),
                    const SizedBox(height: 16),

                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        NavArrowButton(
                          icon: Icons.chevron_left_rounded,
                          onTap: plan.currentWeek > 0 ? notifier.prevWeek : null,
                        ),
                        const SizedBox(width: 12),
                        Container(
                          width: 190,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [AppColors.purple1.withOpacity(.2), AppColors.purple2.withOpacity(.08)],
                            ),
                            border: Border.all(color: AppColors.purple2.withOpacity(.4)),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Column(children: [
                            Text('บอกสัปดาห์ ${plan.currentWeek + 1}', style: AppText.heading(size: 14.5)),
                            Text(phase.label, style: AppText.body(size: 10.5, color: AppColors.textSecondary)),
                          ]),
                        ),
                        const SizedBox(width: 12),
                        NavArrowButton(
                          icon: Icons.chevron_right_rounded,
                          onTap: plan.currentWeek < plan.planWeeks - 1 ? notifier.nextWeek : null,
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),

                    Row(
                      children: [
                        for (final type in _typeOrder)
                          if (caps.capFor(type) > 0)
                            Expanded(
                              child: Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 4),
                                child: _TrayChip(
                                  type: type,
                                  cap: caps.capFor(type),
                                  placed: week.where((d) => d == type).length,
                                  selected: plan.selectedType == type,
                                  onTap: () => notifier.selectType(type),
                                ),
                              ),
                            ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Center(
                      child: Text('แตะไอคอนด้านบน แล้วแตะวันที่ต้องการลงตาราง',
                          style: AppText.body(size: 12, color: AppColors.textSecondary)),
                    ),
                    const SizedBox(height: 16),

                    Row(
                      children: List.generate(7, (i) {
                        return Expanded(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 3),
                            child: _DaySlot(
                              label: _dayLabels[i],
                              value: week[i],
                              onTap: () {
                                final err = notifier.handleDayTap(i);
                                if (err != null) showAppToast(context, err);
                              },
                            ),
                          ),
                        );
                      }),
                    ),

                    const SizedBox(height: 20),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('ความคืบหน้าสัปดาห์นี้', style: AppText.body(size: 12, color: AppColors.textSecondary)),
                        Text('${caps.asMap.entries.where((e) => e.value > 0).fold<int>(0, (s, e) => s + week.where((d) => d == e.key).length)} / ${caps.total}',
                            style: AppText.body(size: 12, color: AppColors.textSecondary)),
                      ],
                    ),
                    const SizedBox(height: 6),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(999),
                      child: LinearProgressIndicator(
                        value: caps.total == 0
                            ? 1.0
                            : ((caps.asMap.entries.where((e) => e.value > 0).fold<int>(0, (s, e) => s + week.where((d) => d == e.key).length) / caps.total)
                                .clamp(0, 1))
                                .toDouble(),
                        minHeight: 8,
                        backgroundColor: Colors.white.withOpacity(.07),
                        valueColor: AlwaysStoppedAnimation(AppColors.gold1),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Center(
                      child: Text('จัดครบแล้ว ${notifier.overallDoneCount} / ${plan.planWeeks} สัปดาห์',
                          style: AppText.body(size: 11.5, color: AppColors.textSecondary)),
                    ),
                  ],
                ),
              ),

              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: Container(
                  padding: const EdgeInsets.fromLTRB(20, 14, 20, 18),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [AppColors.bg1.withOpacity(0), AppColors.bg1],
                    ),
                  ),
                  child: GradientButton(
                    label: 'บันทึกแผนทั้งหมด',
                    gradient: AppColors.greenGradient,
                    onTap: notifier.allWeeksComplete
                        ? () => _showSavedSheet(context)
                        : null,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showSavedSheet(BuildContext context) {
    ref.read(userProvider).addReward(coin: 20, exp: 50);
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => Container(
        padding: const EdgeInsets.fromLTRB(24, 28, 24, 30),
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF1A1433), Color(0xFF0F0B21)],
          ),
          borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('🏅', style: TextStyle(fontSize: 44)),
            const SizedBox(height: 10),
            Text('บันทึกแผนแล้ว!', style: AppText.heading(size: 18)),
            const SizedBox(height: 4),
            Text('แผน Intermediate 10K ทุก Phase พร้อมเริ่มซ้อม',
                style: AppText.body(size: 12.5, color: AppColors.textSecondary)),
            const SizedBox(height: 18),
            Row(children: [
              Expanded(
                child: AppCard(
                  child: Column(children: [
                    Text('+20', style: AppText.heading(size: 19, color: AppColors.gold1)),
                    Text('COIN', style: AppText.body(size: 11, color: AppColors.textSecondary)),
                  ]),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: AppCard(
                  child: Column(children: [
                    Text('+50', style: AppText.heading(size: 19, color: AppColors.purple2)),
                    Text('EXP', style: AppText.body(size: 11, color: AppColors.textSecondary)),
                  ]),
                ),
              ),
            ]),
            const SizedBox(height: 20),
            GradientButton(label: 'กลับหน้าหลัก', onTap: () => Navigator.of(sheetContext).pop()),
          ],
        ),
      ),
    );
  }

  String _minNoteText(PlanPhase phase) {
    if (phase == PlanPhase.taper) {
      return 'Taper คือสัปดาห์ผ่อนความหนัก ลดปริมาณลงเพื่อให้ร่างกายพร้อมที่สุดก่อนวันแข่ง';
    }
    if (phase == PlanPhase.race) {
      return '🏁 วันแข่ง (10K) ถูกล็อกไว้อัตโนมัติที่วันอาทิตย์ และวันเสาร์ก่อนหน้าต้องพักห้ามวิ่ง';
    }
    return 'เป้าหมายรวมของ Phase 1–3 ตลอดโปรแกรม: Easy ≥ 16 ครั้ง · Long Run ≥ 8 ครั้ง · Tempo ≥ 4 ครั้ง · VO2Max ≥ 4 ครั้ง';
  }
}

class _Badge extends StatelessWidget {
  final String text;
  const _Badge(this.text);
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      decoration: BoxDecoration(gradient: AppColors.purpleGradient, borderRadius: BorderRadius.circular(999)),
      child: Text(text, style: AppText.heading(size: 12, color: Colors.white)),
    );
  }
}

class _PhaseNode extends StatelessWidget {
  final PlanPhase phase;
  const _PhaseNode(this.phase);
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(color: Colors.white.withOpacity(.06), borderRadius: BorderRadius.circular(999)),
      child: Text('${phase.shortNumber} ${phase.label.split(" ").first}', style: AppText.heading(size: 10.5)),
    );
  }
}

class _TypeCard extends StatelessWidget {
  final SessionType type;
  final PlanPhase phase;
  final int cap;
  const _TypeCard({required this.type, required this.phase, required this.cap});

  @override
  Widget build(BuildContext context) {
    final meta = sessionMeta[type]!;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: _iconBg(type).withOpacity(.15),
              border: Border.all(color: _iconBg(type).withOpacity(.35)),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(meta.icon, style: const TextStyle(fontSize: 18)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(meta.label, style: AppText.heading(size: 14)),
                Text(sessionDescription(type, phase), style: AppText.body(size: 11.5, color: AppColors.textSecondary)),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(color: Colors.white.withOpacity(.06), borderRadius: BorderRadius.circular(999)),
            child: Text('$cap วัน', style: AppText.heading(size: 12)),
          ),
        ],
      ),
    );
  }

  Color _iconBg(SessionType t) {
    switch (t) {
      case SessionType.easy:
        return AppColors.green1;
      case SessionType.long:
        return AppColors.purple2;
      case SessionType.tempo:
        return AppColors.red1;
      case SessionType.vo2max:
        return AppColors.gold1;
      default:
        return AppColors.gold1;
    }
  }
}

class _RaceInfoCard extends StatelessWidget {
  const _RaceInfoCard();
  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 42,
          height: 42,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: AppColors.gold1.withOpacity(.15),
            border: Border.all(color: AppColors.gold1.withOpacity(.35)),
            borderRadius: BorderRadius.circular(12),
          ),
          child: const Text('🏁', style: TextStyle(fontSize: 18)),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Race Day', style: AppText.heading(size: 14)),
              Text('ล็อกอัตโนมัติวันอาทิตย์ · วันเสาร์ก่อนหน้าห้ามวิ่ง',
                  style: AppText.body(size: 11.5, color: AppColors.textSecondary)),
            ],
          ),
        ),
      ],
    );
  }
}

class _RulesCard extends StatelessWidget {
  final bool expanded;
  final VoidCallback onToggle;
  const _RulesCard({required this.expanded, required this.onToggle});

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          InkWell(
            onTap: onToggle,
            borderRadius: BorderRadius.circular(16),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 13),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('กฎการจัดตาราง', style: AppText.heading(size: 13.5)),
                  AnimatedRotation(
                    turns: expanded ? .5 : 0,
                    duration: const Duration(milliseconds: 150),
                    child: Icon(Icons.keyboard_arrow_down_rounded, color: AppColors.textSecondary),
                  ),
                ],
              ),
            ),
          ),
          AnimatedCrossFade(
            duration: const Duration(milliseconds: 180),
            crossFadeState: expanded ? CrossFadeState.showFirst : CrossFadeState.showSecond,
            firstChild: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: const [
                  _RuleLine('Phase 1–3 (Base / Build / Peak): ทุกสัปดาห์มี Easy 2 · Long Run 1 · Quality 1 วัน (สลับ VO2Max กับ Tempo สัปดาห์เว้นสัปดาห์)'),
                  _RuleLine('VO2Max, Tempo และ Long Run ห้ามอยู่ติดกันเอง ต้องมีวันพักหรือ Easy คั่นก่อนเสมอ'),
                  _RuleLine('Phase 4.1 Taper: Easy 2 (4 กม./ครั้ง) · Tempo 1 (10 นาที) · Long Run 1 (6 กม.)'),
                  _RuleLine('Phase 4.2 Race: Easy 4 (3–4 กม./ครั้ง) · ห้ามวิ่งวันก่อนแข่ง · ปิดท้ายด้วยวันแข่ง 10K'),
                ],
              ),
            ),
            secondChild: const SizedBox(width: double.infinity),
          ),
        ],
      ),
    );
  }
}

class _RuleLine extends StatelessWidget {
  final String text;
  const _RuleLine(this.text);
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('•  ', style: AppText.body(size: 12.5, color: AppColors.textSecondary)),
          Expanded(child: Text(text, style: AppText.body(size: 12.5, color: AppColors.textSecondary))),
        ],
      ),
    );
  }
}

class _TrayChip extends StatelessWidget {
  final SessionType type;
  final int cap;
  final int placed;
  final bool selected;
  final VoidCallback onTap;
  const _TrayChip({
    required this.type,
    required this.cap,
    required this.placed,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final remaining = cap - placed;
    final meta = sessionMeta[type]!;
    final disabled = remaining <= 0;
    return GestureDetector(
      onTap: disabled ? null : onTap,
      child: Opacity(
        opacity: disabled ? .35 : 1,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
          decoration: BoxDecoration(
            color: selected ? AppColors.purple2.withOpacity(.14) : AppColors.card,
            border: Border.all(color: selected ? AppColors.purple2 : AppColors.border, width: selected ? 1.5 : 1),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            children: [
              Text(meta.icon, style: const TextStyle(fontSize: 19)),
              const SizedBox(height: 5),
              Text(meta.label, style: AppText.heading(size: 11), textAlign: TextAlign.center, maxLines: 1, overflow: TextOverflow.ellipsis),
              Text('เหลือ $remaining', style: AppText.body(size: 10, color: AppColors.textSecondary)),
            ],
          ),
        ),
      ),
    );
  }
}

class _DaySlot extends StatelessWidget {
  final String label;
  final SessionType? value;
  final VoidCallback onTap;
  const _DaySlot({required this.label, required this.value, required this.onTap});

  @override
  Widget build(BuildContext context) {
    Color borderColor = AppColors.border;
    Color bg = Colors.white.withOpacity(.02);
    String icon = '';
    String note = '';
    bool dashed = true;

    if (value == SessionType.race) {
      borderColor = AppColors.gold1.withOpacity(.6);
      bg = AppColors.gold1.withOpacity(.2);
      icon = '🏁';
      note = 'วันแข่ง';
      dashed = false;
    } else if (value == SessionType.restForced) {
      borderColor = Colors.white.withOpacity(.16);
      bg = Colors.white.withOpacity(.025);
      note = 'ห้ามวิ่ง';
    } else if (value != null) {
      final meta = sessionMeta[value]!;
      icon = meta.icon;
      dashed = false;
      switch (value!) {
        case SessionType.easy:
          borderColor = AppColors.green1.withOpacity(.45);
          bg = AppColors.green1.withOpacity(.12);
          break;
        case SessionType.long:
          borderColor = AppColors.purple2.withOpacity(.55);
          bg = AppColors.purple2.withOpacity(.16);
          break;
        case SessionType.tempo:
          borderColor = AppColors.red1.withOpacity(.5);
          bg = AppColors.red1.withOpacity(.14);
          break;
        case SessionType.vo2max:
          borderColor = AppColors.gold1.withOpacity(.55);
          bg = AppColors.gold1.withOpacity(.16);
          break;
        default:
          break;
      }
    }

    return Column(
      children: [
        Text(label, style: AppText.body(size: 11, color: AppColors.textTertiary, weight: FontWeight.w600)),
        const SizedBox(height: 6),
        GestureDetector(
          onTap: onTap,
          child: AspectRatio(
            aspectRatio: 1,
            child: Container(
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: bg,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: borderColor, width: 1.5),
              ),
              child: Text(icon, style: const TextStyle(fontSize: 16)),
            ),
          ),
        ),
        const SizedBox(height: 4),
        SizedBox(
          height: 11,
          child: Text(note, style: AppText.body(size: 9, color: AppColors.textTertiary)),
        ),
      ],
    );
  }
}
