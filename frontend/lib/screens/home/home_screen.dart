import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../app_theme.dart';
import '../../providers/auth_provider.dart';
import '../../providers/mission_provider.dart';
import '../../providers/program_provider.dart';
import '../../models/training_date.dart';
import '../../providers/user_provider.dart';
import '../../providers/wallet_provider.dart';
import '../../providers/wellness_provider.dart';
import '../../widgets/common.dart';
import '../profile/profile_screen.dart';
import '../friends/friends_screen.dart';
import '../club/club_screen.dart';
import '../leaderboard/leaderboard_screen.dart';
import '../shop/shop_screen.dart';
import '../run/run_select_screen.dart';
import '../settings/settings_screen.dart';
import '../stats/stats_screen.dart';
import '../training/training_registration_screen.dart';
import '../training/training_schedule_screen.dart';
import '../wellness/daily_wellness_screen.dart';
import 'daily_missions_screen.dart';
import 'home_avatar.dart';
import 'avatar_layout.dart';

const _background = Color(0xFF110E20);
const _panel = Color(0xFF201A32);
const _accent = Color(0xFFC5A2FF);
const _lime = Color(0xFFD6F5A6);

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key, this.avatarRendererBuilder});
  final WidgetBuilder? avatarRendererBuilder;
  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  final _sheet = DraggableScrollableController();
  bool _avatarOnly = false;
  bool _leftMenuOpen = false, _rightMenuOpen = false;
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
    setState(() {
      _leftMenuOpen = false;
      _rightMenuOpen = false;
    });
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
    final wallet = ref.watch(walletProvider);
    final account = ref.watch(authProvider).user;
    final displayName = account?['displayName']?.toString().trim();
    final avatarUrl = account?['avatarUrl']?.toString().trim();
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
      canPop: !_avatarOnly && !_leftMenuOpen && !_rightMenuOpen,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) {
          setState(() {
            _avatarOnly = false;
            _leftMenuOpen = false;
            _rightMenuOpen = false;
          });
        }
      },
      child: Scaffold(
        backgroundColor: _background,
        body: SafeArea(child: LayoutBuilder(builder: (context, constraints) {
          final height = constraints.maxHeight;
          _minimum = (48 / height).clamp(.04, .16);
          final avatar =
              AvatarLayout.home(constraints.biggest, avatarOnly: _avatarOnly);
          final avatarHeight = avatar.height;
          final avatarWidth = avatar.width;
          return Stack(children: [
            Positioned.fill(
                child: GestureDetector(
              key: const Key('home-backdrop'),
              behavior: HitTestBehavior.opaque,
              onTap: () {
                setState(() {
                  _leftMenuOpen = false;
                  _rightMenuOpen = false;
                });
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
              top: _avatarOnly ? (height - avatarHeight) / 2 - 5 : avatar.top,
              left: 0,
              right: 0,
              height: avatarHeight,
              child: Center(
                  child: Semantics(
                button: true,
                label: _avatarOnly ? 'กลับหน้าหลัก' : 'ดูเฉพาะอวตารและพื้นหลัง',
                child: InkWell(
                  key: const Key('home-avatar'),
                  onTap: () => setState(() {
                    _avatarOnly = !_avatarOnly;
                    _leftMenuOpen = false;
                    _rightMenuOpen = false;
                  }),
                  borderRadius: BorderRadius.circular(100),
                  child: SizedBox(
                      width: avatarWidth,
                      height: avatarHeight,
                      child: HomeAvatar(
                          rendererBuilder: widget.avatarRendererBuilder)),
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
                            padding: const EdgeInsets.all(1.5),
                            child: ClipRRect(
                                borderRadius: BorderRadius.circular(14.5),
                                child: avatarUrl == null || avatarUrl.isEmpty
                                    ? const Icon(Icons.person_outline,
                                        color: Colors.white)
                                    : Image.network(avatarUrl,
                                        key: const Key('home-profile-image'),
                                        width: double.infinity,
                                        height: double.infinity,
                                        fit: BoxFit.cover,
                                        errorBuilder: (_, __, ___) =>
                                            const Icon(Icons.person_outline,
                                                color: Colors.white)))),
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
                          Text(wallet.valueOrNull?.toString() ?? '—',
                              style: AppText.body(
                                  size: 13, color: AppColors.gold2)),
                        ])),
                  ])),
              Positioned(
                  top: 88, left: 16, child: _sideMenu(height, left: true)),
              Positioned(
                  top: 88, right: 16, child: _sideMenu(height, left: false)),
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
                                Text('แผนวันนี้',
                                    style:
                                        AppText.body(size: 10, color: _accent)),
                                const SizedBox(height: 8),
                                Text(title, style: AppText.heading(size: 18)),
                                if (quest != null &&
                                    program.currentWeekErrorMessage == null)
                                  Text(_dateLabel(quest),
                                      style: AppText.body(
                                          size: 12, color: _accent)),
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
                              'จัดตารางซ้อม',
                              'ดูและจัดการตารางซ้อม',
                              _schedule),
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

  Widget _sideMenu(double height, {required bool left}) {
    final open = left ? _leftMenuOpen : _rightMenuOpen;
    void toggle() => setState(() {
          if (left) {
            _leftMenuOpen = !open;
            _rightMenuOpen = false;
          } else {
            _rightMenuOpen = !open;
            _leftMenuOpen = false;
          }
        });
    if (!open) {
      final button = left
          ? _shortcut(Icons.more_horiz, '', toggle,
              key: const Key('home-shortcuts-toggle'),
              tooltip: 'เปิดเมนูทางลัด')
          : _shortcut(Icons.menu, 'เมนู', toggle,
              key: const Key('home-menu-toggle'));
      return _animateMenu(button, left: left, open: false);
    }
    return _animateMenu(
        SizedBox(
          key: Key(left ? 'home-shortcuts' : 'home-menu'),
          width: 56,
          height: math.max(56.0, height * (1 - _extent) - 88),
          child: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
            if (left) ...[
              _shortcut(Icons.emoji_events_outlined, 'อันดับ',
                  () => _push(const LeaderboardScreen())),
              const SizedBox(height: 8),
              _shortcut(Icons.people_outline, 'เพื่อน',
                  () => _push(const FriendsScreen())),
              const SizedBox(height: 8),
              _shortcut(Icons.checkroom_outlined, 'แต่งตัว',
                  () => _push(const ShopScreen(wardrobe: true))),
              const SizedBox(height: 8),
              _shortcut(Icons.storefront_outlined, 'ร้านค้า',
                  () => _push(const ShopScreen())),
              const SizedBox(height: 8),
              _shortcut(Icons.groups_outlined, 'คลับ',
                  () => _push(const ClubScreen())),
              const SizedBox(height: 8),
              _shortcut(Icons.arrow_drop_down, '', toggle,
                  key: const Key('home-shortcuts-collapse'),
                  tooltip: 'ย่อเมนูทางลัด'),
            ] else ...[
              _shortcut(Icons.calendar_month_outlined, 'ตารางซ้อม', _schedule),
              const SizedBox(height: 8),
              _shortcut(Icons.bar_chart_rounded, 'สถิติ',
                  () => _openPage('สถิติ', const StatsScreen())),
              const SizedBox(height: 8),
              _shortcut(Icons.settings_outlined, 'ตั้งค่า',
                  () => _openPage('ตั้งค่า', const SettingsScreen())),
              const SizedBox(height: 8),
              _shortcut(Icons.close, '', toggle,
                  key: const Key('home-menu-close'), tooltip: 'ปิดเมนู'),
            ],
          ])),
        ),
        left: left,
        open: true);
  }

  Widget _animateMenu(Widget child, {required bool left, required bool open}) {
    final activeKey = ValueKey(
        '${left ? 'left' : 'right'}-${open ? 'expanded' : 'collapsed'}');
    final reducedMotion = MediaQuery.disableAnimationsOf(context);
    final animation = AnimatedSwitcher(
      duration:
          reducedMotion ? Duration.zero : const Duration(milliseconds: 280),
      reverseDuration:
          reducedMotion ? Duration.zero : const Duration(milliseconds: 280),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      layoutBuilder: (current, previous) => Stack(
        alignment: Alignment.topCenter,
        children: [...previous, if (current != null) current],
      ),
      transitionBuilder: (item, progress) {
        final expanded =
            item.key == ValueKey('${left ? 'left' : 'right'}-expanded');
        final content =
            expanded ? item : FadeTransition(opacity: progress, child: item);
        return IgnorePointer(
          ignoring: item.key != activeKey,
          child: ExcludeSemantics(
            excluding: item.key != activeKey,
            child: expanded
                ? SlideTransition(
                    position: Tween<Offset>(
                            begin: left
                                ? const Offset(0, -1)
                                : const Offset(1.5, 0),
                            end: Offset.zero)
                        .animate(progress),
                    child: content,
                  )
                : content,
          ),
        );
      },
      child: KeyedSubtree(key: activeKey, child: child),
    );
    return left ? ClipRect(child: animation) : animation;
  }

  Widget _shortcut(IconData icon, String label, VoidCallback? onTap,
          {Key? key, String? tooltip}) =>
      Semantics(
          key: key,
          button: true,
          enabled: onTap != null,
          label: tooltip ?? (onTap == null ? '$label · เร็ว ๆ นี้' : label),
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
                    width: 56,
                    height: 56,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(icon,
                            color: onTap == null
                                ? AppColors.textTertiary
                                : AppColors.textSecondary,
                            size: 20),
                        if (label.isNotEmpty) const SizedBox(height: 4),
                        if (label.isNotEmpty)
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
    final date = trainingDate(quest['scheduled_date']);
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
