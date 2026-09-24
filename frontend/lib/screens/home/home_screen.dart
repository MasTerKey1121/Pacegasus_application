import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../app_theme.dart';
import '../../providers/auth_provider.dart';
import '../../providers/mission_provider.dart';
import '../../providers/program_provider.dart';
import '../../providers/user_provider.dart';
import '../../providers/wellness_provider.dart';
import '../../widgets/common.dart';
import '../profile/profile_screen.dart';
import '../friends/friends_screen.dart';
import '../shop/shop_screen.dart';
import '../run/run_select_screen.dart';
import '../settings/settings_screen.dart';
import '../stats/stats_screen.dart';
import '../training/training_registration_screen.dart';
import '../training/training_schedule_screen.dart';
import '../wellness/daily_wellness_screen.dart';
import 'daily_missions_screen.dart';
import 'home_avatar.dart';

const _background = Color(0xFF110E20);
const _panel = Color(0xFF201A32);
const _accent = Color(0xFFC5A2FF);
const _lime = Color(0xFFD6F5A6);

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});
  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  final _scaffold = GlobalKey<ScaffoldState>();
  final _sheet = DraggableScrollableController();
  bool _avatarOnly = false;
  double _extent = .4;
  double _minimum = .06;
  static const _middle = .4;
  static const _maximum = .76;

  @override
  void dispose() {
    _sheet.dispose();
    super.dispose();
  }

  void _moveSheet(double extent) {
    if (!_sheet.isAttached) return;
    _sheet.animateTo(extent,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic);
  }

  void _snapSheet([double velocity = 0]) {
    final stops = [_minimum, _middle, _maximum];
    final current = _sheet.size;
    if (velocity.abs() > 250) {
      final options = stops.where(
          (stop) => velocity < 0 ? stop > current + .01 : stop < current - .01);
      _moveSheet(options.isEmpty
          ? (velocity < 0 ? _maximum : _minimum)
          : (velocity < 0 ? options.first : options.last));
    } else {
      stops.sort((a, b) => (a - current).abs().compareTo((b - current).abs()));
      _moveSheet(stops.first);
    }
  }

  Future<void> _push(Widget screen) async {
    _moveSheet(_minimum);
    await Navigator.of(context)
        .push(MaterialPageRoute<void>(builder: (_) => screen));
    // Refresh after returning from wellness, scheduling or a run.
    if (mounted && ref.read(programProvider).isRegistered) {
      await ref.read(programProvider).loadCurrentWeek();
    }
  }

  void _openPage(String title, Widget child) => _push(Scaffold(
        appBar: AppBar(title: Text(title), backgroundColor: _background),
        body: AppBackground(child: SafeArea(top: false, child: child)),
      ));

  void _schedule() {
    final program = ref.read(programProvider);
    if (program.isLoading) return;
    if (!ref.read(wellnessProvider).completedToday) {
      _push(const DailyWellnessScreen());
    } else {
      _push(program.isRegistered
          ? const TrainingScheduleScreen()
          : const TrainingRegistrationScreen());
    }
  }

  void _primaryAction() {
    final program = ref.read(programProvider);
    if (!ref.read(wellnessProvider).completedToday) {
      _push(const DailyWellnessScreen());
    } else if (program.currentWeekErrorMessage != null) {
      program.restore(force: true);
    } else if (!program.isRegistered || !program.isScheduleSaved) {
      _schedule();
    } else if (program.todayQuest == null ||
        program.todayQuest?['status'] == 'completed') {
      _schedule();
    } else {
      _push(const RunTypeSelectScreen());
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(userProvider);
    final displayName =
        ref.watch(authProvider).user?['displayName']?.toString().trim();
    final name = displayName == null || displayName.isEmpty
        ? user.username
        : displayName;
    final wellness = ref.watch(wellnessProvider);
    final program = ref.watch(programProvider);
    final missions = ref.watch(missionProvider);
    final quest = program.todayQuest;
    final done = quest?['status'] == 'completed';
    final ready = wellness.completedToday &&
        program.isRegistered &&
        program.isScheduleSaved;
    final label = program.isLoading
        ? 'กำลังโหลด…'
        : !wellness.completedToday
            ? 'เช็กอินก่อนวิ่ง'
            : program.currentWeekErrorMessage != null
                ? 'ลองโหลดอีกครั้ง'
                : !program.isRegistered
                    ? 'เลือกแผนซ้อม'
                    : !program.isScheduleSaved
                        ? 'จัดตารางซ้อม'
                        : quest == null || done
                            ? 'ดูแผนซ้อม'
                            : 'เริ่มวิ่ง';
    final title = program.isLoading
        ? 'กำลังโหลดแผนวันนี้…'
        : !wellness.completedToday
            ? 'แผนวันนี้รอคุณอยู่'
            : program.currentWeekErrorMessage != null
                ? 'โหลดแผนไม่สำเร็จ'
                : !program.isRegistered
                    ? 'เริ่มการเดินทางครั้งใหม่'
                    : !program.isScheduleSaved
                        ? 'จัดตารางซ้อมของคุณ'
                        : done
                            ? 'ทำแผนวันนี้สำเร็จ'
                            : quest == null
                                ? 'วันพักของคุณ'
                                : _questLabel(quest);
    final hint = !wellness.completedToday
        ? 'เริ่มจากเช็กความพร้อมของวันนี้'
        : program.currentWeekErrorMessage != null
            ? 'แตะเพื่อลองโหลดข้อมูลอีกครั้ง'
            : !program.isRegistered
                ? 'เลือกโปรแกรมให้เหมาะกับเป้าหมาย'
                : !program.isScheduleSaved
                    ? 'บันทึกตารางก่อนเริ่มการวิ่ง'
                    : done
                        ? 'วันนี้ทำสำเร็จแล้ว พักให้เต็มที่'
                        : quest == null
                            ? 'วันนี้ไม่มีเควสในตารางฝึก'
                            : 'พร้อมออกไปทำเป้าหมายวันนี้';

    return PopScope(
      canPop: !_avatarOnly,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop && _avatarOnly) setState(() => _avatarOnly = false);
      },
      child: Scaffold(
        key: _scaffold,
        backgroundColor: _background,
        endDrawerEnableOpenDragGesture: false,
        endDrawer: Drawer(
          key: const Key('home-menu'),
          width: MediaQuery.sizeOf(context).width * .25,
          backgroundColor: _panel,
          shape: const RoundedRectangleBorder(
              borderRadius: BorderRadius.horizontal(left: Radius.circular(24))),
          child: SafeArea(
              child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 4),
            child: Column(children: [
              _menuItem(Icons.calendar_month_outlined, 'ตารางซ้อม', _schedule),
              _menuItem(Icons.bar_chart_rounded, 'สถิติการวิ่ง',
                  () => _openPage('สถิติ', const StatsScreen())),
              _menuItem(Icons.settings_outlined, 'ตั้งค่า',
                  () => _openPage('ตั้งค่า', const SettingsScreen())),
            ]),
          )),
        ),
        body: SafeArea(child: LayoutBuilder(builder: (context, constraints) {
          final height = constraints.maxHeight;
          _minimum = (48 / height).clamp(.04, .16);
          final avatarHeight = math.min(330.0, height * .48);
          final avatarTop = math.max(205.0, height * .31);
          return Stack(children: [
            Positioned.fill(
                child: GestureDetector(
              key: const Key('home-backdrop'),
              behavior: HitTestBehavior.opaque,
              onTap: () {
                if (_avatarOnly) {
                  setState(() => _avatarOnly = false);
                } else {
                  _moveSheet(_minimum);
                }
              },
              child: const DecoratedBox(
                  decoration: BoxDecoration(
                      gradient: RadialGradient(
                          center: Alignment(0, .2),
                          radius: .85,
                          colors: [Color(0xFF443057), _background]))),
            )),
            AnimatedPositioned(
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOutCubic,
              top: _avatarOnly ? (height - avatarHeight) / 2 : avatarTop,
              left: 0,
              right: 0,
              height: avatarHeight,
              child: Center(
                  child: Semantics(
                button: true,
                label: _avatarOnly ? 'กลับหน้าหลัก' : 'ดูเฉพาะอวตารและพื้นหลัง',
                child: InkWell(
                  key: const Key('home-avatar'),
                  onTap: () => setState(() => _avatarOnly = !_avatarOnly),
                  borderRadius: BorderRadius.circular(100),
                  child: SizedBox(
                      width: 230,
                      height: avatarHeight,
                      child: const HomeAvatar()),
                ),
              )),
            ),
            if (!_avatarOnly) ...[
              Positioned(
                  top: 16,
                  left: 16,
                  right: 16,
                  child: Row(children: [
                    Expanded(
                        child: InkWell(
                      key: const Key('home-profile'),
                      onTap: () => _openPage('โปรไฟล์', const ProfileScreen()),
                      borderRadius: BorderRadius.circular(16),
                      child: Row(children: [
                        Container(
                            width: 44,
                            height: 44,
                            decoration: BoxDecoration(
                                color: const Color(0xFF564573),
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(color: _accent, width: 1.5)),
                            child: const Icon(Icons.person_outline,
                                color: Colors.white)),
                        const SizedBox(width: 10),
                        Expanded(
                            child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                              Text(name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: AppText.heading(size: 14)),
                              Text(
                                  'Lv.${user.level} · ${user.exp % 100} / 100 XP',
                                  style: AppText.body(
                                      size: 10.5,
                                      color: AppColors.textSecondary)),
                              const SizedBox(height: 5),
                              ClipRRect(
                                  borderRadius: BorderRadius.circular(4),
                                  child: LinearProgressIndicator(
                                      value: (user.exp % 100) / 100,
                                      minHeight: 3,
                                      color: _accent,
                                      backgroundColor:
                                          const Color(0xFF453650))),
                            ])),
                      ]),
                    )),
                    const SizedBox(width: 18),
                    Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 10),
                        decoration: BoxDecoration(
                            color: _panel,
                            borderRadius: BorderRadius.circular(24),
                            border: Border.all(color: AppColors.borderHi)),
                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                          const Icon(Icons.toll_outlined,
                              color: AppColors.gold2, size: 18),
                          const SizedBox(width: 6),
                          Text('${user.coin}',
                              style: AppText.body(
                                  size: 13, color: AppColors.gold2)),
                        ])),
                  ])),
              Positioned(
                  top: 88,
                  left: 16,
                  child: Column(children: [
                    _shortcut(
                        Icons.emoji_events_outlined,
                        'อันดับ',
                        () => showAppToast(
                            context, 'ระบบอันดับจะเปิดให้ใช้งานภายหลัง')),
                    const SizedBox(height: 8),
                    _shortcut(
                        Icons.people_outline,
                        'เพื่อน',
                        () => Navigator.of(context).push(MaterialPageRoute(
                            builder: (_) => const FriendsScreen()))),
                    const SizedBox(height: 8),
                    _shortcut(Icons.checkroom_outlined, 'แต่งตัว', null),
                    const SizedBox(height: 8),
                    _shortcut(Icons.storefront_outlined, 'ร้านค้า',
                        () => _push(const ShopScreen())),
                  ])),
              Positioned(
                  top: 88,
                  right: 16,
                  child: _shortcut(Icons.menu, 'เมนู', () {
                    _moveSheet(_minimum);
                    _scaffold.currentState?.openEndDrawer();
                  })),
              Positioned(
                  top: 80,
                  left: 76,
                  right: 76,
                  child: Column(children: [
                    Text('YOUR NEXT ADVENTURE',
                        textAlign: TextAlign.center,
                        style: AppText.body(
                            size: 9, color: AppColors.textSecondary)),
                    const SizedBox(height: 8),
                    FilledButton(
                        key: const Key('home-primary'),
                        onPressed: program.isLoading ? null : _primaryAction,
                        style: FilledButton.styleFrom(
                            backgroundColor: _lime,
                            foregroundColor: const Color(0xFF202C16),
                            minimumSize: const Size(0, 46),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 10)),
                        child: Text(label,
                            textAlign: TextAlign.center,
                            style: const TextStyle(fontSize: 13))),
                    const SizedBox(height: 8),
                    Text(hint,
                        textAlign: TextAlign.center,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: AppText.body(
                            size: 10.5, color: AppColors.textSecondary)),
                  ])),
              NotificationListener<DraggableScrollableNotification>(
                onNotification: (notification) {
                  if ((_extent - notification.extent).abs() > .001) {
                    setState(() => _extent = notification.extent);
                  }
                  return true;
                },
                child: DraggableScrollableSheet(
                  key: const Key('home-quest-sheet'),
                  controller: _sheet,
                  initialChildSize: _extent.clamp(_minimum, _maximum),
                  minChildSize: _minimum,
                  maxChildSize: _maximum,
                  snap: true,
                  snapSizes: const [_middle],
                  builder: (context, scrollController) => Material(
                    color: _panel,
                    borderRadius:
                        const BorderRadius.vertical(top: Radius.circular(28)),
                    clipBehavior: Clip.antiAlias,
                    child: Column(children: [
                      Semantics(
                          button: true,
                          label: 'เปิดหรือขยายแผงภารกิจ',
                          child: GestureDetector(
                            key: const Key('home-sheet-handle'),
                            behavior: HitTestBehavior.opaque,
                            onTap: () => _moveSheet(_extent < _middle - .02
                                ? _middle
                                : _extent < _maximum - .02
                                    ? _maximum
                                    : _middle),
                            onVerticalDragUpdate: (details) => _sheet.jumpTo(
                                (_sheet.size - details.delta.dy / height)
                                    .clamp(_minimum, _maximum)),
                            onVerticalDragEnd: (details) =>
                                _snapSheet(details.primaryVelocity ?? 0),
                            child: SizedBox(
                                height: 48,
                                width: double.infinity,
                                child: Center(
                                    child: Container(
                                        width: 36,
                                        height: 4,
                                        decoration: BoxDecoration(
                                            color: const Color(0xFF80708F),
                                            borderRadius:
                                                BorderRadius.circular(4))))),
                          )),
                      Expanded(
                          child: ListView(
                        controller: scrollController,
                        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                        children: [
                          Text('วันนี้ของคุณ',
                              style: AppText.heading(size: 19)),
                          const SizedBox(height: 12),
                          AppCard(
                              child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                Text('TODAY’S PLAN',
                                    style:
                                        AppText.body(size: 10, color: _accent)),
                                const SizedBox(height: 8),
                                Text(title, style: AppText.heading(size: 18)),
                                const SizedBox(height: 4),
                                Text(hint,
                                    style: AppText.body(
                                        size: 12,
                                        color: AppColors.textSecondary)),
                                if (ready &&
                                    !program.isLoading &&
                                    program.currentWeekErrorMessage == null &&
                                    quest != null) ...[
                                  const SizedBox(height: 8),
                                  Text(
                                      done
                                          ? 'สำเร็จแล้ว · ${_questLabel(quest)}'
                                          : 'พร้อมแล้ว · เริ่มวิ่งได้เลย',
                                      style:
                                          AppText.body(size: 11, color: _lime)),
                                ],
                              ])),
                          const SizedBox(height: 16),
                          Text('ภารกิจประจำวัน',
                              style: AppText.heading(size: 14)),
                          if (!wellness.completedToday)
                            _taskRow(
                                Icons.favorite_border,
                                'เช็กอินสุขภาพ',
                                'เช็กความพร้อมก่อนวิ่ง',
                                () => _push(const DailyWellnessScreen())),
                          _taskRow(
                              Icons.flag_outlined,
                              'ภารกิจของฉัน',
                              'ทำครบแล้ว ${missions.doneCount} / ${missions.missions.length}',
                              () => _push(const DailyMissionsScreen())),
                          _taskRow(
                              Icons.calendar_month_outlined,
                              'แผนสัปดาห์นี้',
                              'ดูและจัดการตารางซ้อม',
                              _schedule),
                          if (ready && program.currentWeekErrorMessage == null)
                            ...program.quests.map((item) => Padding(
                                  padding: const EdgeInsets.only(top: 8),
                                  child: Text(
                                      '${_dateLabel(item)} · ${_questLabel(item)}',
                                      style: AppText.body(
                                          size: 12,
                                          color: AppColors.textSecondary)),
                                )),
                        ],
                      )),
                    ]),
                  ),
                ),
              ),
            ],
          ]);
        })),
      ),
    );
  }

  Widget _menuItem(IconData icon, String label, VoidCallback onTap) => InkWell(
        onTap: () {
          Navigator.of(context).pop();
          onTap();
        },
        child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 22, horizontal: 3),
            child: Column(children: [
              Icon(icon, color: _accent, size: 22),
              const SizedBox(height: 9),
              Text(label,
                  textAlign: TextAlign.center, style: AppText.body(size: 11)),
            ])),
      );

  Widget _shortcut(IconData icon, String label, VoidCallback? onTap) =>
      Semantics(
          button: true,
          enabled: onTap != null,
          label: onTap == null ? '$label · เร็ว ๆ นี้' : label,
          excludeSemantics: true,
          child: Material(
            color: _panel,
            borderRadius: BorderRadius.circular(15),
            child: InkWell(
                onTap: onTap == null
                    ? null
                    : () {
                        _moveSheet(_minimum);
                        onTap();
                      },
                borderRadius: BorderRadius.circular(15),
                child: SizedBox(
                    width: 48,
                    height: 56,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(icon,
                            color: onTap == null
                                ? AppColors.textTertiary
                                : AppColors.textSecondary,
                            size: 20),
                        const SizedBox(height: 4),
                        Text(label,
                            style: AppText.body(
                                size: 10,
                                color: onTap == null
                                    ? AppColors.textSecondary
                                    : AppColors.textPrimary))
                      ],
                    ))),
          ));

  Widget _taskRow(
          IconData icon, String title, String subtitle, VoidCallback onTap) =>
      ListTile(
          contentPadding: EdgeInsets.zero,
          onTap: onTap,
          title: Text(title, style: AppText.body(size: 13)),
          subtitle: Text(subtitle,
              style: AppText.body(size: 11, color: AppColors.textSecondary)),
          trailing: Icon(icon, color: _accent, size: 21));

  String _dateLabel(Map<String, dynamic> quest) {
    final date = DateTime.tryParse(quest['scheduled_date']?.toString() ?? '');
    return date == null ? 'วันซ้อม' : '${date.day}/${date.month}';
  }

  String _questLabel(Map<String, dynamic> quest) {
    final type = (quest['session_type'] ?? 'run').toString();
    final title = switch (type) {
      'easy' => 'Easy Run',
      'tempo' => 'Tempo Run',
      'vo2max' => 'VO2 Max',
      'long_run' => 'Long Run',
      _ => type,
    };
    final value = quest['planned_value'];
    final unit = quest['unit'];
    return value == null ? title : '$title · $value ${unit ?? ''}'.trim();
  }
}
