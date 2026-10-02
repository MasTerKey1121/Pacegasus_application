import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../app_theme.dart';
import '../../services/api_client.dart';
import '../../services/club_api.dart';
import '../../widgets/player_profile_dialog.dart';
import '../../widgets/common.dart';

const _accent = Color(0xFFC5A2FF);
const _roles = {
  'leader': 'หัวหน้าคลับ',
  'sub_leader': 'รองหัวหน้าคลับ',
  'member': 'สมาชิก'
};
const _permissionLabels = {
  'canApproveRequests': 'อนุมัติคำขอเข้าร่วม',
  'canInvite': 'เชิญสมาชิก',
  'canKick': 'นำสมาชิกออก',
  'canEditInfo': 'แก้ไขข้อมูลคลับ'
};

String _error(Object e) =>
    e is ApiException ? e.message : 'เกิดข้อผิดพลาด กรุณาลองใหม่';
void _toast(BuildContext context, String text) =>
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
Widget _page(String title, Widget body, {List<Widget>? actions}) => Scaffold(
    appBar: AppBar(
        title: Text(title), actions: actions, backgroundColor: AppColors.bg2),
    body: AppBackground(child: SafeArea(top: false, child: body)));
Widget _empty(String text, {VoidCallback? retry}) => Padding(
    padding: const EdgeInsets.all(24),
    child: Column(mainAxisSize: MainAxisSize.min, children: [
      Text(text,
          textAlign: TextAlign.center,
          style: AppText.body(color: AppColors.textSecondary)),
      if (retry != null)
        TextButton(onPressed: retry, child: const Text('ลองอีกครั้ง')),
    ]));
Widget _crest(String? url, {double size = 56}) => ClipRRect(
    borderRadius: BorderRadius.circular(16),
    child: SizedBox(
        width: size,
        height: size,
        child: url == null || url.isEmpty
            ? const ColoredBox(
                color: Color(0xFF352845),
                child: Icon(Icons.shield_outlined, color: _accent))
            : Image.network(url,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) =>
                    const Icon(Icons.shield_outlined, color: _accent))));
Future<bool> _confirm(BuildContext context, String title, String body) async =>
    await showDialog<bool>(
        context: context,
        builder: (ctx) =>
            AlertDialog(title: Text(title), content: Text(body), actions: [
              TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('ยกเลิก')),
              FilledButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  child: const Text('ยืนยัน')),
            ])) ==
    true;

class ClubScreen extends ConsumerStatefulWidget {
  const ClubScreen({super.key});
  @override
  ConsumerState<ClubScreen> createState() => _ClubScreenState();
}

class _ClubScreenState extends ConsumerState<ClubScreen> {
  final _search = TextEditingController();
  List<Map<String, dynamic>> _clubs = [];
  String? _failure;
  bool _loading = true;
  int _total = 0, _generation = 0;
  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _load({bool more = false}) async {
    final generation = ++_generation;
    setState(() {
      _loading = true;
      _failure = null;
      if (!more) _clubs = [];
    });
    try {
      final api = ref.read(clubApiProvider);
      final mine = await api.mine();
      if (!mounted || generation != _generation) return;
      if (mine != null) {
        Navigator.of(context).pushReplacement<void, void>(MaterialPageRoute(
            builder: (_) =>
                ClubDetailScreen(clubId: mine['club']['id'] as String)));
        return;
      }
      final data =
          await api.search(_search.text.trim(), more ? _clubs.length : 0);
      if (!mounted || generation != _generation) return;
      final clubs = (data['clubs'] as List).cast<Map<String, dynamic>>();
      setState(() {
        _clubs = more ? [..._clubs, ...clubs] : clubs;
        _total = (data['total'] as num).toInt();
        _loading = false;
      });
    } catch (e) {
      if (mounted && generation == _generation) {
        setState(() {
          _failure = _error(e);
          _loading = false;
        });
      }
    }
  }

  Future<void> _open(Widget screen) async {
    await Navigator.push(
        context, MaterialPageRoute<void>(builder: (_) => screen));
    if (mounted) await _load();
  }

  @override
  Widget build(BuildContext _) {
    if (_loading && _clubs.isEmpty) {
      return _page('Club', const Center(child: CircularProgressIndicator()));
    }
    return _page(
        'Club',
        RefreshIndicator(
            onRefresh: _load,
            child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(20),
                children: [
                  TextField(
                      controller: _search,
                      textInputAction: TextInputAction.search,
                      onSubmitted: (_) => _load(),
                      decoration: InputDecoration(
                          hintText: 'ค้นหาชื่อคลับ',
                          prefixIcon: const Icon(Icons.search),
                          suffixIcon: IconButton(
                              tooltip: 'ค้นหา',
                              onPressed: () => _load(),
                              icon: const Icon(Icons.arrow_forward)),
                          filled: true,
                          fillColor: AppColors.cardHi,
                          border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(16)))),
                  const SizedBox(height: 16),
                  if (!_loading && _failure == null)
                    OutlinedButton.icon(
                        onPressed: () => _open(const ClubFormScreen()),
                        icon: const Icon(Icons.add),
                        label: const Text('สร้างคลับ')),
                  TextButton.icon(
                      onPressed: () => _open(const ClubRequestsScreen()),
                      icon: const Icon(Icons.mail_outline),
                      label: const Text('คำเชิญและคำขอของฉัน')),
                  const SizedBox(height: 12),
                  Text('ค้นพบคลับ', style: AppText.heading(size: 20)),
                  const SizedBox(height: 12),
                  for (final club in _clubs)
                    Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: AppCard(
                            child: Column(children: [
                          Row(children: [
                            _crest(club['imageUrl'] as String?),
                            const SizedBox(width: 12),
                            Expanded(
                                child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                  Text(club['name'] as String,
                                      style: AppText.heading(size: 16)),
                                  Text(
                                      '${club['memberCount']} / ${club['maxMembers']} คน',
                                      style: AppText.body(
                                          size: 12,
                                          color: AppColors.textSecondary)),
                                ]))
                          ]),
                          if ((club['description'] as String? ?? '').isNotEmpty)
                            Padding(
                                padding: const EdgeInsets.only(top: 10),
                                child: Align(
                                    alignment: Alignment.centerLeft,
                                    child: Text(club['description'] as String,
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis))),
                          Align(
                              alignment: Alignment.centerRight,
                              child: OutlinedButton(
                                  onPressed: () => _open(ClubDetailScreen(
                                      clubId: club['id'] as String)),
                                  child: const Text('ดูคลับ'))),
                        ]))),
                  if (_loading)
                    const Center(child: CircularProgressIndicator())
                  else if (_failure != null)
                    _empty(_failure!,
                        retry: () => _load(more: _clubs.isNotEmpty))
                  else if (_clubs.isEmpty)
                    _empty('ยังไม่พบคลับ')
                  else if (_clubs.length < _total)
                    OutlinedButton(
                        onPressed: () => _load(more: true),
                        child: const Text('โหลดเพิ่มเติม')),
                ])));
  }
}

class ClubFormScreen extends ConsumerStatefulWidget {
  final Map<String, dynamic>? club;
  const ClubFormScreen({super.key, this.club});
  @override
  ConsumerState<ClubFormScreen> createState() => _ClubFormScreenState();
}

class _ClubFormScreenState extends ConsumerState<ClubFormScreen> {
  final _form = GlobalKey<FormState>();
  late final TextEditingController _name, _description, _image;
  bool _busy = false;
  String? _failure;
  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.club?['name'] as String?);
    _description =
        TextEditingController(text: widget.club?['description'] as String?);
    _image = TextEditingController(text: widget.club?['imageUrl'] as String?);
  }

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    _image.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_busy || !_form.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _failure = null;
    });
    try {
      await ref.read(clubApiProvider).save({
        'name': _name.text.trim(),
        'description': _description.text.trim(),
        'imageUrl': _image.text.trim().isEmpty ? null : _image.text.trim()
      }, id: widget.club?['id'] as String?);
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _failure = _error(e);
        });
      }
    }
  }

  @override
  Widget build(BuildContext _) => PopScope(
      canPop: !_busy,
      child: _page(
          widget.club == null ? 'สร้างคลับ' : 'แก้ไขข้อมูลคลับ',
          SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Form(
                  key: _form,
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Center(child: _crest(_image.text.trim(), size: 96)),
                        const SizedBox(height: 24),
                        TextFormField(
                            controller: _name,
                            enabled: !_busy,
                            maxLength: 40,
                            decoration: const InputDecoration(
                                labelText: 'ชื่อคลับ',
                                border: OutlineInputBorder()),
                            validator: (value) =>
                                (value ?? '').trim().length < 3
                                    ? 'ชื่อคลับต้องมี 3–40 ตัวอักษร'
                                    : null),
                        const SizedBox(height: 16),
                        TextFormField(
                            controller: _description,
                            enabled: !_busy,
                            maxLength: 500,
                            minLines: 3,
                            maxLines: 6,
                            decoration: const InputDecoration(
                                labelText: 'คำอธิบายและกติกาคลับ',
                                border: OutlineInputBorder())),
                        const SizedBox(height: 16),
                        TextFormField(
                            controller: _image,
                            enabled: !_busy,
                            keyboardType: TextInputType.url,
                            onChanged: (_) => setState(() {}),
                            decoration: const InputDecoration(
                                labelText: 'ลิงก์รูปตราคลับ (ไม่บังคับ)',
                                border: OutlineInputBorder()),
                            validator: (value) {
                              if ((value ?? '').trim().isEmpty) return null;
                              final uri = Uri.tryParse(value!.trim());
                              return uri != null &&
                                      ['http', 'https'].contains(uri.scheme) &&
                                      uri.host.isNotEmpty &&
                                      value.length <= 2048
                                  ? null
                                  : 'กรอกลิงก์รูป http หรือ https ให้ถูกต้อง';
                            }),
                        const SizedBox(height: 20),
                        const ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading:
                                Icon(Icons.how_to_reg_outlined, color: _accent),
                            title: Text('อนุมัติก่อนเข้าร่วม'),
                            subtitle:
                                Text('ผู้ดูแลตรวจคำขอก่อนเพิ่มสมาชิกเข้าคลับ')),
                        if (_failure != null) _empty(_failure!),
                        const SizedBox(height: 20),
                        FilledButton(
                            onPressed: _busy ? null : _save,
                            child: Padding(
                                padding: const EdgeInsets.all(14),
                                child: Text(_busy
                                    ? 'กำลังบันทึก…'
                                    : widget.club == null
                                        ? 'สร้างคลับ'
                                        : 'บันทึก'))),
                      ])))));
}

class ClubDetailScreen extends ConsumerStatefulWidget {
  final String clubId;
  const ClubDetailScreen({super.key, required this.clubId});
  @override
  ConsumerState<ClubDetailScreen> createState() => _ClubDetailScreenState();
}

class _ClubDetailScreenState extends ConsumerState<ClubDetailScreen> {
  late Future<Map<String, dynamic>> _data;
  bool _busy = false, _menuOpen = false;
  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    _data = ref.read(clubApiProvider).detail(widget.clubId);
  }

  Future<void> _refresh() async {
    setState(_reload);
    await _data;
  }

  Future<void> _open(Widget screen) async {
    await Navigator.push(
        context, MaterialPageRoute<void>(builder: (_) => screen));
    if (mounted) setState(_reload);
  }

  Future<void> _edit(Map<String, dynamic> club, String field) async {
    final changed = await showDialog<bool>(
        context: context,
        builder: (_) => _ClubEditDialog(club: club, field: field));
    if (mounted && changed == true) setState(_reload);
  }

  Future<void> _join() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await ref.read(clubApiProvider).join(widget.clubId);
      if (mounted) {
        _toast(context, 'อัปเดตคำขอเข้าร่วมแล้ว');
        setState(_reload);
      }
    } catch (e) {
      if (mounted) _toast(context, _error(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _action(String action, bool leader) async {
    setState(() => _menuOpen = false);
    if (action == 'requests') {
      await _open(ClubRequestsScreen(clubId: widget.clubId));
    } else if (action == 'permissions') {
      await _open(ClubPermissionsScreen(clubId: widget.clubId));
    } else if (action == 'leave') {
      if (_busy || !await _confirmLeave(context, leader)) return;
      if (!mounted) return;
      setState(() => _busy = true);
      try {
        await ref.read(clubApiProvider).leave(widget.clubId);
        if (!mounted) return;
        Navigator.of(context).pushReplacement<void, void>(
            MaterialPageRoute(builder: (_) => const ClubScreen()));
      } catch (e) {
        if (mounted) _toast(context, _error(e));
      } finally {
        if (mounted) setState(() => _busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext _) => _page(
      'คลับของเรา',
      FutureBuilder<Map<String, dynamic>>(
          future: _data,
          builder: (_, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              return _empty(_error(snapshot.error!),
                  retry: () => setState(_reload));
            }
            final data = snapshot.data!;
            final club = data['club'] as Map<String, dynamic>;
            final membership = data['myMembership'] as Map<String, dynamic>?;
            final leader = membership?['role'] == 'leader';
            final members =
                (data['members'] as List).cast<Map<String, dynamic>>();
            return Stack(children: [
              Column(children: [
                Expanded(
                    child: RefreshIndicator(
                        onRefresh: _refresh,
                        child: ListView(
                            physics: const AlwaysScrollableScrollPhysics(),
                            padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
                            children: [
                              Container(
                                  padding: const EdgeInsets.all(20),
                                  decoration: BoxDecoration(
                                      gradient: const RadialGradient(
                                          radius: 1.2,
                                          center: Alignment(0, -.3),
                                          colors: [
                                            Color(0xFF493460),
                                            Color(0xFF181226)
                                          ]),
                                      borderRadius: BorderRadius.circular(24),
                                      border: Border.all(
                                          color:
                                              _accent.withValues(alpha: .2))),
                                  child: Column(children: [
                                    SizedBox(
                                        width: 130,
                                        height: 130,
                                        child: Stack(children: [
                                          Center(
                                              child: _crest(
                                                  club['imageUrl'] as String?,
                                                  size: 116)),
                                          if (leader)
                                            Positioned(
                                                right: 0,
                                                bottom: 0,
                                                child: _editButton(
                                                    'แก้ไขตราคลับ',
                                                    () => _edit(
                                                        club, 'imageUrl'))),
                                        ])),
                                    const SizedBox(height: 16),
                                    Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.center,
                                        children: [
                                          Flexible(
                                              child: Text(
                                                  club['name'] as String,
                                                  textAlign: TextAlign.center,
                                                  style: AppText.heading(
                                                      size: 24,
                                                      color: _accent))),
                                          if (leader) ...[
                                            const SizedBox(width: 6),
                                            _editButton('แก้ไขชื่อคลับ',
                                                () => _edit(club, 'name'))
                                          ],
                                        ]),
                                    const SizedBox(height: 8),
                                    SelectableText('ID คลับ ${club['id']}',
                                        textAlign: TextAlign.center,
                                        style: AppText.body(
                                            size: 11,
                                            color: AppColors.textSecondary)),
                                    const SizedBox(height: 12),
                                    Container(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 14, vertical: 6),
                                        decoration: BoxDecoration(
                                            borderRadius:
                                                BorderRadius.circular(20),
                                            border: Border.all(
                                                color: _accent.withValues(
                                                    alpha: .5))),
                                        child: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              const Icon(Icons.groups_outlined,
                                                  size: 18, color: _accent),
                                              const SizedBox(width: 8),
                                              Text(
                                                  '${club['memberCount']} / ${club['maxMembers']} คน',
                                                  style: AppText.body(size: 12))
                                            ])),
                                  ])),
                              const SizedBox(height: 16),
                              AppCard(
                                  child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                    Row(children: [
                                      Expanded(
                                          child: Text('คำขวัญคลับ',
                                              style: AppText.heading(
                                                  size: 17, color: _accent))),
                                      if (leader)
                                        _editButton('แก้ไขคำขวัญคลับ',
                                            () => _edit(club, 'description'))
                                    ]),
                                    const SizedBox(height: 8),
                                    Text(
                                        (club['description'] as String? ?? '')
                                                .isEmpty
                                            ? 'ยังไม่ได้ตั้งคำขวัญคลับ'
                                            : club['description'] as String,
                                        style: AppText.body(size: 14)),
                                  ])),
                              const SizedBox(height: 24),
                              Row(children: [
                                Expanded(
                                    child: Text('สมาชิกคลับ',
                                        style: AppText.heading(
                                            size: 18, color: _accent))),
                                TextButton(
                                    onPressed: () => _open(ClubMembersScreen(
                                        clubId: widget.clubId)),
                                    child: const Text('ดูทั้งหมด ›',
                                        style: TextStyle(color: _accent)))
                              ]),
                              if (members.isEmpty)
                                _empty('ยังไม่มีข้อมูลสมาชิก'),
                              for (final member in members.take(6))
                                Padding(
                                    padding: const EdgeInsets.only(bottom: 10),
                                    child: AppCard(
                                        onTap: () async {
                                          await showPlayerProfile(context,
                                              member['user']['uid'] as String);
                                          if (mounted) setState(_reload);
                                        },
                                        padding: const EdgeInsets.all(12),
                                        child: Row(children: [
                                          _memberAvatar(member['user']
                                              ['avatarUrl'] as String?),
                                          const SizedBox(width: 12),
                                          Expanded(
                                              child: Column(
                                                  crossAxisAlignment:
                                                      CrossAxisAlignment.start,
                                                  children: [
                                                Text(
                                                    member['user']
                                                                ['displayName']
                                                            as String? ??
                                                        'นักวิ่ง',
                                                    maxLines: 1,
                                                    overflow:
                                                        TextOverflow.ellipsis,
                                                    style: AppText.heading(
                                                        size: 14)),
                                                const SizedBox(height: 5),
                                                Container(
                                                    padding: const EdgeInsets.symmetric(
                                                        horizontal: 8,
                                                        vertical: 3),
                                                    decoration: BoxDecoration(
                                                        borderRadius:
                                                            BorderRadius.circular(
                                                                12),
                                                        border: Border.all(
                                                            color: member['role'] == 'leader'
                                                                ? AppColors
                                                                    .gold2
                                                                : _accent.withValues(
                                                                    alpha:
                                                                        .4))),
                                                    child: Text(_roles[member['role']] ?? 'สมาชิก',
                                                        style: AppText.body(
                                                            size: 10,
                                                            color: member['role'] ==
                                                                    'leader'
                                                                ? AppColors.gold2
                                                                : _accent))),
                                              ])),
                                        ]))),
                            ]))),
                if (membership != null)
                  const SizedBox(height: 76)
                else
                  Padding(
                      padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
                      child: SizedBox(
                          width: double.infinity,
                          child: FilledButton(
                              onPressed: _busy ||
                                      data['myPendingRequest']?['kind'] ==
                                          'request' ||
                                      club['memberCount'] >= club['maxMembers']
                                  ? null
                                  : _join,
                              child: Text(_busy
                                  ? 'กำลังส่ง…'
                                  : data['myPendingRequest']?['kind'] ==
                                          'request'
                                      ? 'ส่งคำขอแล้ว รออนุมัติ'
                                      : data['myPendingRequest']?['kind'] ==
                                              'invite'
                                          ? 'ตอบรับคำเชิญ'
                                          : 'ขอเข้าร่วมคลับ')))),
              ]),
              if (_menuOpen && membership != null) ...[
                Positioned.fill(
                    child: GestureDetector(
                        onTap: () => setState(() => _menuOpen = false),
                        child: ColoredBox(
                            color: Colors.black.withValues(alpha: .45)))),
                Positioned(
                    left: 20,
                    right: 20,
                    bottom: 84,
                    child: _ClubManagementMenu(
                        leader: leader,
                        onAction: (action) => _action(action, leader))),
              ],
              if (membership != null)
                Positioned(
                    left: 20,
                    right: 20,
                    bottom: 12,
                    child: FilledButton.icon(
                        onPressed: _busy
                            ? null
                            : () => setState(() => _menuOpen = !_menuOpen),
                        style: FilledButton.styleFrom(
                            backgroundColor: _accent,
                            foregroundColor: AppColors.bg1,
                            minimumSize: const Size(0, 52),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16))),
                        icon: const Icon(Icons.settings_outlined),
                        label: Text(_busy ? 'กำลังดำเนินการ…' : 'จัดการคลับ',
                            style:
                                const TextStyle(fontWeight: FontWeight.w600)))),
            ]);
          }));
}

Widget _editButton(String label, VoidCallback action) => IconButton.filledTonal(
    tooltip: label,
    onPressed: action,
    icon: const Icon(Icons.edit_outlined, size: 20),
    style: IconButton.styleFrom(
        backgroundColor: _accent,
        foregroundColor: AppColors.bg1,
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))));
Widget _memberAvatar(String? url) => CircleAvatar(
    radius: 25,
    backgroundColor: const Color(0xFF493460),
    child: url == null || url.isEmpty
        ? const Icon(Icons.person, color: _accent)
        : ClipOval(
            child: Image.network(url,
                width: 50,
                height: 50,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) =>
                    const Icon(Icons.person, color: _accent))));

class _ClubManagementMenu extends StatelessWidget {
  final bool leader;
  final ValueChanged<String> onAction;
  const _ClubManagementMenu({required this.leader, required this.onAction});
  @override
  Widget build(BuildContext context) => Material(
      color: const Color(0xFF241C38),
      borderRadius: BorderRadius.circular(20),
      clipBehavior: Clip.antiAlias,
      child: Padding(
          padding: const EdgeInsets.all(8),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            if (leader) ...[
              _row(Icons.person_add_outlined, 'คำขอสมัคร', 'requests'),
              _row(Icons.shield_outlined, 'บทบาทและสิทธิ์', 'permissions'),
              const Divider(height: 12),
            ],
            _row(Icons.logout, 'ออกจากคลับ', 'leave', color: AppColors.red2),
          ])));
  Widget _row(IconData icon, String label, String value,
          {Color color = _accent}) =>
      ListTile(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          leading: Icon(icon, color: color),
          title: Text(label, style: TextStyle(color: color)),
          trailing: Icon(Icons.chevron_right, color: color),
          onTap: () => onAction(value));
}

Future<bool> _confirmLeave(BuildContext context, bool leader) async {
  if (leader) {
    await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
                title: const Text('โอนสิทธิ์หัวหน้าก่อน'),
                content: const Text(
                    'หัวหน้าต้องโอนสิทธิ์ให้สมาชิกก่อนออกจากคลับ\n\nระบบโอนสิทธิ์จะเพิ่มภายหลัง'),
                actions: [
                  FilledButton(
                      onPressed: () => Navigator.pop(ctx),
                      child: const Text('รับทราบ'))
                ]));
    return false;
  }
  return await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
                  title: const Text('ยืนยันออกจากคลับ'),
                  content: const Text('ต้องการออกจากคลับนี้หรือไม่?'),
                  actions: [
                    TextButton(
                        onPressed: () => Navigator.pop(ctx, false),
                        child: const Text('ยกเลิก')),
                    FilledButton(
                        style: FilledButton.styleFrom(
                            backgroundColor: AppColors.red1),
                        onPressed: () => Navigator.pop(ctx, true),
                        child: const Text('ออกจากคลับ'))
                  ])) ==
      true;
}

class _ClubEditDialog extends ConsumerStatefulWidget {
  final Map<String, dynamic> club;
  final String field;
  const _ClubEditDialog({required this.club, required this.field});
  @override
  ConsumerState<_ClubEditDialog> createState() => _ClubEditDialogState();
}

class _ClubEditDialogState extends ConsumerState<_ClubEditDialog> {
  final _form = GlobalKey<FormState>();
  late final TextEditingController _input;
  bool _busy = false;
  String? _failure;
  String get _label => {
        'name': 'ชื่อคลับ',
        'imageUrl': 'ตราคลับ',
        'description': 'คำขวัญคลับ'
      }[widget.field]!;
  @override
  void initState() {
    super.initState();
    _input = TextEditingController(text: widget.club[widget.field] as String?);
  }

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_busy || !_form.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _failure = null;
    });
    final value = _input.text.trim();
    try {
      await ref.read(clubApiProvider).save({
        widget.field: widget.field == 'imageUrl' && value.isEmpty ? null : value
      }, id: widget.club['id'] as String);
      if (!mounted) return;
      setState(() => _busy = false);
      await WidgetsBinding.instance.endOfFrame;
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _failure = _error(e);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
      canPop: !_busy,
      child: AlertDialog(
          title: Text('แก้ไข$_label'),
          content: SingleChildScrollView(
              child: Form(
                  key: _form,
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    if (widget.field == 'imageUrl') ...[
                      _crest(_input.text.trim(), size: 80),
                      const SizedBox(height: 12)
                    ],
                    TextFormField(
                        controller: _input,
                        enabled: !_busy,
                        maxLength: widget.field == 'name'
                            ? 40
                            : widget.field == 'description'
                                ? 500
                                : 2048,
                        maxLines: widget.field == 'description' ? 4 : 1,
                        keyboardType: widget.field == 'imageUrl'
                            ? TextInputType.url
                            : TextInputType.text,
                        onChanged: widget.field == 'imageUrl'
                            ? (_) => setState(() {})
                            : null,
                        decoration: InputDecoration(
                            labelText: widget.field == 'imageUrl'
                                ? 'ลิงก์รูปตราคลับ'
                                : _label,
                            border: const OutlineInputBorder()),
                        validator: (text) {
                          final value = (text ?? '').trim();
                          if (widget.field == 'name' && value.length < 3) {
                            return 'ชื่อคลับต้องมี 3–40 ตัวอักษร';
                          }
                          if (widget.field == 'imageUrl' && value.isNotEmpty) {
                            final uri = Uri.tryParse(value);
                            if (uri == null ||
                                !['http', 'https'].contains(uri.scheme) ||
                                uri.host.isEmpty) {
                              return 'กรอกลิงก์รูป http หรือ https ให้ถูกต้อง';
                            }
                          }
                          return null;
                        }),
                    if (_failure != null)
                      Text(_failure!,
                          style: const TextStyle(color: AppColors.red2)),
                  ]))),
          actions: [
            TextButton(
                onPressed: _busy ? null : () => Navigator.pop(context),
                child: const Text('ยกเลิก')),
            FilledButton(
                onPressed: _busy ? null : _save,
                child: Text(_busy ? 'กำลังบันทึก…' : 'บันทึก'))
          ]));
}

// Retained for existing navigation links; the club page opens this same menu inline.
class ClubManageScreen extends ConsumerStatefulWidget {
  final String clubId;
  const ClubManageScreen({super.key, required this.clubId});
  @override
  ConsumerState<ClubManageScreen> createState() => _ClubManageScreenState();
}

class _ClubManageScreenState extends ConsumerState<ClubManageScreen> {
  late Future<Map<String, dynamic>> _data;
  bool _busy = false;
  @override
  void initState() {
    super.initState();
    _data = ref.read(clubApiProvider).detail(widget.clubId);
  }

  Future<void> _action(String action, bool leader) async {
    if (_busy) return;
    if (action == 'leave') {
      if (!await _confirmLeave(context, leader) || !mounted) return;
      setState(() => _busy = true);
      try {
        await ref.read(clubApiProvider).leave(widget.clubId);
        if (mounted) Navigator.pop(context, true);
      } catch (e) {
        if (mounted) _toast(context, _error(e));
      } finally {
        if (mounted) setState(() => _busy = false);
      }
      return;
    }
    await Navigator.push(
        context,
        MaterialPageRoute<void>(
            builder: (_) => action == 'requests'
                ? ClubRequestsScreen(clubId: widget.clubId)
                : ClubPermissionsScreen(clubId: widget.clubId)));
    if (mounted) {
      setState(() => _data = ref.read(clubApiProvider).detail(widget.clubId));
    }
  }

  @override
  Widget build(BuildContext _) => _page(
      'จัดการคลับ',
      FutureBuilder<Map<String, dynamic>>(
          future: _data,
          builder: (_, snapshot) {
            if (!snapshot.hasData) {
              return snapshot.hasError
                  ? _empty(_error(snapshot.error!),
                      retry: () => setState(() => _data =
                          ref.read(clubApiProvider).detail(widget.clubId)))
                  : const Center(child: CircularProgressIndicator());
            }
            final membership =
                snapshot.data!['myMembership'] as Map<String, dynamic>?;
            if (membership == null) return _empty('คุณไม่ได้เป็นสมาชิกคลับนี้');
            return SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: AbsorbPointer(
                    absorbing: _busy,
                    child: _ClubManagementMenu(
                        leader: membership['role'] == 'leader',
                        onAction: (action) =>
                            _action(action, membership['role'] == 'leader'))));
          }));
}

class ClubMembersScreen extends ConsumerStatefulWidget {
  final String clubId;
  const ClubMembersScreen({super.key, required this.clubId});
  @override
  ConsumerState<ClubMembersScreen> createState() => _ClubMembersScreenState();
}

class _ClubMembersScreenState extends ConsumerState<ClubMembersScreen> {
  late Future<Map<String, dynamic>> _data;
  bool _busy = false;
  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    _data = ref.read(clubApiProvider).detail(widget.clubId);
  }

  @override
  Widget build(BuildContext _) => _page(
      'สมาชิกทั้งหมด',
      FutureBuilder<Map<String, dynamic>>(
          future: _data,
          builder: (_, snapshot) {
            if (snapshot.hasError) {
              return _empty(_error(snapshot.error!),
                  retry: () => setState(_reload));
            }
            if (!snapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            final membership =
                snapshot.data!['myMembership'] as Map<String, dynamic>?;
            final permissions =
                membership?['permissions'] as Map<String, dynamic>? ?? {};
            final myRank = {
                  'leader': 3,
                  'sub_leader': 2,
                  'member': 1
                }[membership?['role']] ??
                0;
            return ListView(padding: const EdgeInsets.all(16), children: [
              if (_busy) const LinearProgressIndicator(),
              for (final member in snapshot.data!['members'] as List)
                ListTile(
                    onTap: () async {
                      await showPlayerProfile(
                          context, member['user']['uid'] as String);
                      if (mounted) setState(_reload);
                    },
                    leading: _crest(member['user']['avatarUrl'] as String?,
                        size: 44),
                    title: Text(
                        member['user']['displayName'] as String? ?? 'นักวิ่ง'),
                    subtitle: Text(
                        '${_roles[member['role']]} · UID: ${member['user']['uid']}'),
                    trailing: ((permissions['canKick'] == true &&
                                myRank >
                                    ({
                                          'leader': 3,
                                          'sub_leader': 2,
                                          'member': 1
                                        }[member['role']] ??
                                        0)) ||
                            (myRank == 3 && member['role'] != 'leader'))
                        ? PopupMenuButton<String>(
                            enabled: !_busy,
                            itemBuilder: (_) => [
                                  if (myRank == 3 && member['role'] != 'leader')
                                    PopupMenuItem(
                                        value: member['role'] == 'member'
                                            ? 'sub_leader'
                                            : 'member',
                                        child: Text(member['role'] == 'member'
                                            ? 'แต่งตั้งรองหัวหน้า'
                                            : 'เปลี่ยนเป็นสมาชิก')),
                                  if (permissions['canKick'] == true &&
                                      myRank >
                                          ({
                                                'leader': 3,
                                                'sub_leader': 2,
                                                'member': 1
                                              }[member['role']] ??
                                              0))
                                    const PopupMenuItem(
                                        value: 'kick',
                                        child: Text('นำออกจากคลับ')),
                                ],
                            onSelected: (value) async {
                              if (!await _confirm(
                                  context,
                                  'ยืนยันการจัดการสมาชิก',
                                  'ดำเนินการกับ ${member['user']['displayName'] ?? 'สมาชิก'} หรือไม่?')) {
                                return;
                              }
                              if (!mounted) return;
                              setState(() => _busy = true);
                              try {
                                final api = ref.read(clubApiProvider);
                                if (value == 'kick') {
                                  await api.kick(widget.clubId,
                                      member['user']['id'] as String);
                                } else {
                                  await api.role(widget.clubId,
                                      member['user']['id'] as String, value);
                                }
                                if (mounted) setState(_reload);
                              } catch (e) {
                                if (mounted) _toast(context, _error(e));
                              } finally {
                                if (mounted) setState(() => _busy = false);
                              }
                            })
                        : null),
            ]);
          }));
}

class ClubRequestsScreen extends ConsumerStatefulWidget {
  final String? clubId;
  const ClubRequestsScreen({super.key, this.clubId});
  @override
  ConsumerState<ClubRequestsScreen> createState() => _ClubRequestsScreenState();
}

class _ClubRequestsScreenState extends ConsumerState<ClubRequestsScreen> {
  late Future<List<Map<String, dynamic>>> _data;
  String _kind = 'invite';
  bool _busy = false;
  @override
  void initState() {
    super.initState();
    if (widget.clubId != null) _kind = 'request';
    _reload();
  }

  void _reload() {
    _data =
        ref.read(clubApiProvider).requests(clubId: widget.clubId, kind: _kind);
  }

  @override
  Widget build(BuildContext _) => _page(
      widget.clubId == null ? 'คำเชิญและคำขอของฉัน' : 'คำขอเข้าร่วม',
      Column(children: [
        if (widget.clubId == null)
          Padding(
              padding: const EdgeInsets.all(12),
              child: SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(value: 'invite', label: Text('คำเชิญ')),
                    ButtonSegment(value: 'request', label: Text('คำขอที่ส่ง'))
                  ],
                  selected: {
                    _kind
                  },
                  onSelectionChanged: _busy
                      ? null
                      : (value) => setState(() {
                            _kind = value.first;
                            _reload();
                          }))),
        if (_busy) const LinearProgressIndicator(),
        Expanded(
            child: FutureBuilder<List<Map<String, dynamic>>>(
                future: _data,
                builder: (_, snapshot) {
                  if (snapshot.hasError) {
                    return _empty(_error(snapshot.error!),
                        retry: () => setState(_reload));
                  }
                  if (!snapshot.hasData) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (snapshot.data!.isEmpty) return _empty('ยังไม่มีรายการ');
                  return ListView(padding: const EdgeInsets.all(16), children: [
                    for (final request in snapshot.data!)
                      Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: AppCard(
                              child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                Text(
                                    (widget.clubId == null
                                            ? request['club']['name']
                                            : request['user']
                                                ['displayName']) as String? ??
                                        'นักวิ่ง',
                                    style: AppText.heading(size: 17)),
                                if ((request['message'] as String? ?? '')
                                    .isNotEmpty)
                                  Text(request['message'] as String),
                                Wrap(spacing: 8, children: [
                                  if (widget.clubId != null ||
                                      _kind == 'invite')
                                    FilledButton(
                                        onPressed: _busy
                                            ? null
                                            : () => _act(request, true),
                                        child: Text(widget.clubId != null
                                            ? 'อนุมัติ'
                                            : 'ตอบรับ')),
                                  TextButton(
                                      onPressed: _busy
                                          ? null
                                          : () => _act(request, false),
                                      child: Text(widget.clubId != null ||
                                              _kind == 'invite'
                                          ? 'ปฏิเสธ'
                                          : 'ยกเลิกคำขอ')),
                                ]),
                              ]))),
                  ]);
                })),
      ]));
  Future<void> _act(Map<String, dynamic> request, bool accept) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await ref.read(clubApiProvider).handleRequest(
          request['requestId'] as String,
          clubId: widget.clubId,
          accept: accept);
      if (mounted) setState(_reload);
    } catch (e) {
      if (mounted) _toast(context, _error(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}

class ClubPermissionsScreen extends ConsumerStatefulWidget {
  final String clubId;
  const ClubPermissionsScreen({super.key, required this.clubId});
  @override
  ConsumerState<ClubPermissionsScreen> createState() =>
      _ClubPermissionsScreenState();
}

class _ClubPermissionsScreenState extends ConsumerState<ClubPermissionsScreen> {
  Map<String, dynamic>? _data;
  String? _failure;
  bool _busy = false;
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _data = null;
      _failure = null;
    });
    try {
      final data = await ref.read(clubApiProvider).permissions(widget.clubId);
      if (mounted) setState(() => _data = data);
    } catch (e) {
      if (mounted) setState(() => _failure = _error(e));
    }
  }

  @override
  Widget build(BuildContext _) => _page(
      'บทบาทและสิทธิ์',
      _failure != null
          ? _empty(_failure!, retry: _load)
          : _data == null
              ? const Center(child: CircularProgressIndicator())
              : ListView(padding: const EdgeInsets.all(16), children: [
                  if (_busy) const LinearProgressIndicator(),
                  const Text('หัวหน้าคลับมีทุกสิทธิ์เสมอ'),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.groups_outlined, color: _accent),
                    title: const Text('จัดการบทบาทสมาชิก'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: _busy
                        ? null
                        : () => Navigator.push(
                            context,
                            MaterialPageRoute<void>(
                                builder: (_) =>
                                    ClubMembersScreen(clubId: widget.clubId))),
                  ),
                  const SizedBox(height: 20),
                  for (final role in ['sub_leader', 'member'])
                    Padding(
                        padding: const EdgeInsets.only(bottom: 20),
                        child: AppCard(
                            child: Column(children: [
                          Text(_roles[role]!, style: AppText.heading(size: 20)),
                          for (final entry in _permissionLabels.entries)
                            SwitchListTile(
                                contentPadding: EdgeInsets.zero,
                                title: Text(entry.value),
                                value: _data![role]?[entry.key] == true,
                                onChanged: _busy
                                    ? null
                                    : (value) async {
                                        setState(() => _busy = true);
                                        try {
                                          await ref
                                              .read(clubApiProvider)
                                              .setPermissions(widget.clubId,
                                                  role, {entry.key: value});
                                          if (mounted) {
                                            setState(() => _data![role]
                                                [entry.key] = value);
                                          }
                                        } catch (e) {
                                          if (mounted) {
                                            _toast(context, _error(e));
                                          }
                                        } finally {
                                          if (mounted) {
                                            setState(() => _busy = false);
                                          }
                                        }
                                      }),
                        ]))),
                ]));
}
