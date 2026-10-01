import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../app_theme.dart';
import '../../services/api_client.dart';
import '../../services/club_api.dart';
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
                child: Icon(Icons.groups_outlined, color: _accent))
            : Image.network(url,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) =>
                    const Icon(Icons.groups_outlined, color: _accent))));
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
  Map<String, dynamic>? _mine;
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
      final results = await Future.wait([
        api.search(_search.text.trim(), more ? _clubs.length : 0),
        api.mine()
      ]);
      if (!mounted || generation != _generation) return;
      final data = results[0]!;
      final clubs = (data['clubs'] as List).cast<Map<String, dynamic>>();
      setState(() {
        _clubs = more ? [..._clubs, ...clubs] : clubs;
        _total = (data['total'] as num).toInt();
        _mine = results[1];
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
  Widget build(BuildContext _) => _page(
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
                if (_mine != null)
                  AppCard(
                      child: ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading:
                              _crest(_mine!['club']['imageUrl'] as String?),
                          title: Text(_mine!['club']['name'] as String),
                          subtitle: const Text('คลับของฉัน'),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () => _open(ClubDetailScreen(
                              clubId: _mine!['club']['id'] as String)))),
                if (!_loading && _failure == null && _mine == null)
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
                                  crossAxisAlignment: CrossAxisAlignment.start,
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
                  _empty(_failure!, retry: () => _load(more: _clubs.isNotEmpty))
                else if (_clubs.isEmpty)
                  _empty('ยังไม่พบคลับ')
                else if (_clubs.length < _total)
                  OutlinedButton(
                      onPressed: () => _load(more: true),
                      child: const Text('โหลดเพิ่มเติม')),
              ])));
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
  bool _busy = false;
  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    _data = ref.read(clubApiProvider).detail(widget.clubId);
  }

  Future<void> _open(Widget screen) async {
    final removed = await Navigator.push<bool>(
        context, MaterialPageRoute<bool>(builder: (_) => screen));
    if (!mounted) return;
    if (removed == true) {
      Navigator.pop(context);
      return;
    }
    if (mounted) {
      setState(() {
        _refresh();
      });
    }
  }

  Future<void> _join() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await ref.read(clubApiProvider).join(widget.clubId);
      if (mounted) {
        _toast(context, 'อัปเดตคำขอเข้าร่วมแล้ว');
        setState(() {
          _refresh();
        });
      }
    } catch (e) {
      if (mounted) _toast(context, _error(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext _) => _page(
      'คลับ',
      FutureBuilder<Map<String, dynamic>>(
          future: _data,
          builder: (_, snapshot) {
            if (snapshot.hasError) {
              return _empty(_error(snapshot.error!),
                  retry: () => setState(() {
                        _refresh();
                      }));
            }
            if (!snapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            final data = snapshot.data!;
            final club = data['club'] as Map<String, dynamic>;
            final membership = data['myMembership'] as Map<String, dynamic>?;
            final permissions =
                membership?['permissions'] as Map<String, dynamic>? ?? {};
            final canManage = membership?['role'] == 'leader' ||
                permissions.values.any((v) => v == true);
            return RefreshIndicator(
                onRefresh: () async {
                  setState(() {
                    _refresh();
                  });
                  await _data;
                },
                child: ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.all(20),
                    children: [
                      Container(
                          padding: const EdgeInsets.all(24),
                          decoration: BoxDecoration(
                              gradient: const LinearGradient(colors: [
                                Color(0xFF493460),
                                Color(0xFF21192F)
                              ]),
                              borderRadius: BorderRadius.circular(24)),
                          child: Column(children: [
                            _crest(club['imageUrl'] as String?, size: 90),
                            const SizedBox(height: 16),
                            Text(club['name'] as String,
                                style: AppText.heading(size: 24),
                                textAlign: TextAlign.center),
                            const SizedBox(height: 8),
                            Text(
                                '${club['memberCount']} / ${club['maxMembers']} สมาชิก'),
                            if (membership != null)
                              Text(_roles[membership['role']] ?? 'สมาชิก',
                                  style:
                                      const TextStyle(color: AppColors.gold2)),
                          ])),
                      const SizedBox(height: 20),
                      if ((club['description'] as String? ?? '').isNotEmpty)
                        AppCard(
                            child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                              Text('เกี่ยวกับคลับและกติกา',
                                  style: AppText.heading(size: 17)),
                              const SizedBox(height: 8),
                              Text(club['description'] as String),
                            ])),
                      if (canManage)
                        Padding(
                            padding: const EdgeInsets.only(top: 12),
                            child: OutlinedButton.icon(
                                onPressed: () => _open(
                                    ClubManageScreen(clubId: widget.clubId)),
                                icon: const Icon(Icons.settings_outlined),
                                label: const Text('จัดการคลับ'))),
                      if (membership == null)
                        Padding(
                            padding: const EdgeInsets.only(top: 12),
                            child: FilledButton(
                                onPressed: _busy ||
                                        data['myPendingRequest']?['kind'] ==
                                            'request' ||
                                        club['memberCount'] >=
                                            club['maxMembers']
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
                                            : 'ขอเข้าร่วมคลับ'))),
                      const SizedBox(height: 24),
                      Text('สมาชิก', style: AppText.heading(size: 20)),
                      for (final member in data['members'] as List)
                        ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: _crest(
                                member['user']['avatarUrl'] as String?,
                                size: 42),
                            title: Text(
                                member['user']['displayName'] as String? ??
                                    'นักวิ่ง'),
                            subtitle: Text(_roles[member['role']] ?? 'สมาชิก')),
                      if (membership != null)
                        TextButton(
                            onPressed: _busy
                                ? null
                                : () async {
                                    if (!await _confirm(
                                        context,
                                        'ออกจากคลับ',
                                        membership['role'] == 'leader'
                                            ? 'ถ้ายังมีสมาชิกอยู่ ระบบจะให้โอนหัวหน้าก่อนออกจากคลับ'
                                            : 'ต้องการออกจากคลับนี้หรือไม่?')) {
                                      return;
                                    }
                                    if (!mounted) return;
                                    setState(() => _busy = true);
                                    try {
                                      await ref
                                          .read(clubApiProvider)
                                          .leave(widget.clubId);
                                      if (mounted) Navigator.pop(context);
                                    } catch (e) {
                                      if (mounted) _toast(context, _error(e));
                                    } finally {
                                      if (mounted) {
                                        setState(() => _busy = false);
                                      }
                                    }
                                  },
                            child: const Text('ออกจากคลับ',
                                style: TextStyle(color: AppColors.red2))),
                    ]));
          }));
}

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

  Future<void> _open(Widget screen) async {
    await Navigator.push(
        context, MaterialPageRoute<void>(builder: (_) => screen));
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
            if (snapshot.hasError) {
              return _empty(_error(snapshot.error!),
                  retry: () => setState(() =>
                      _data = ref.read(clubApiProvider).detail(widget.clubId)));
            }
            if (!snapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            final data = snapshot.data!;
            final membership = data['myMembership'] as Map<String, dynamic>?;
            if (membership == null) return _empty('คุณไม่ได้เป็นสมาชิกคลับนี้');
            final club = data['club'] as Map<String, dynamic>;
            final leader = membership['role'] == 'leader';
            final permissions =
                membership['permissions'] as Map<String, dynamic>;
            return ListView(padding: const EdgeInsets.all(20), children: [
              AppCard(
                  child: ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: _crest(club['imageUrl'] as String?),
                      title: Text(club['name'] as String),
                      subtitle: Text(_roles[membership['role']] ?? 'สมาชิก'))),
              const SizedBox(height: 24),
              Text('สมาชิกและสิทธิ์', style: AppText.heading(size: 18)),
              _menu(Icons.groups_outlined, 'สมาชิกทั้งหมด',
                  () => _open(ClubMembersScreen(clubId: widget.clubId))),
              if (permissions['canApproveRequests'] == true)
                _menu(Icons.person_add_outlined, 'คำขอเข้าร่วม',
                    () => _open(ClubRequestsScreen(clubId: widget.clubId))),
              if (permissions['canInvite'] == true)
                _menu(Icons.mail_outline, 'เชิญสมาชิกด้วย UID', () async {
                  final input = TextEditingController();
                  final uid = await showDialog<String>(
                      context: context,
                      builder: (ctx) => AlertDialog(
                              title: const Text('เชิญสมาชิก'),
                              content: TextField(
                                  controller: input,
                                  decoration: const InputDecoration(
                                      labelText: 'UID 10 ตัว')),
                              actions: [
                                TextButton(
                                    onPressed: () => Navigator.pop(ctx),
                                    child: const Text('ยกเลิก')),
                                FilledButton(
                                    onPressed: () =>
                                        Navigator.pop(ctx, input.text),
                                    child: const Text('ส่งคำเชิญ')),
                              ]));
                  // Controller lives until the dialog's reverse transition finishes.
                  await Future<void>.delayed(const Duration(milliseconds: 300));
                  input.dispose();
                  if (uid == null || !mounted) return;
                  if (!RegExp(r'^[23456789ABCDEFGHJKLMNPQRSTUVWXYZ]{10}$')
                      .hasMatch(uid.trim().toUpperCase())) {
                    _toast(context, 'กรอก UID 10 ตัวให้ถูกต้อง');
                    return;
                  }
                  try {
                    await ref.read(clubApiProvider).invite(widget.clubId, uid);
                    if (mounted) _toast(context, 'ส่งคำเชิญแล้ว');
                  } catch (e) {
                    if (mounted) _toast(context, _error(e));
                  }
                }),
              if (leader)
                _menu(Icons.shield_outlined, 'บทบาทและสิทธิ์',
                    () => _open(ClubPermissionsScreen(clubId: widget.clubId))),
              if (permissions['canEditInfo'] == true) ...[
                const SizedBox(height: 24),
                Text('ดูแลคลับ', style: AppText.heading(size: 18)),
                _menu(Icons.edit_outlined, 'แก้ไขข้อมูลและกติกาคลับ',
                    () => _open(ClubFormScreen(club: club)))
              ],
              if (leader) ...[
                const SizedBox(height: 28),
                TextButton.icon(
                    onPressed: _busy
                        ? null
                        : () async {
                            if (!await _confirm(context, 'ยุบคลับ',
                                'คลับและสมาชิกทั้งหมดจะถูกนำออก ต้องการยุบ ${club['name']} หรือไม่?')) {
                              return;
                            }
                            if (!mounted) return;
                            setState(() => _busy = true);
                            try {
                              await ref
                                  .read(clubApiProvider)
                                  .disband(widget.clubId);
                              if (mounted) Navigator.pop(context, true);
                            } catch (e) {
                              if (mounted) _toast(context, _error(e));
                            } finally {
                              if (mounted) setState(() => _busy = false);
                            }
                          },
                    icon:
                        const Icon(Icons.delete_outline, color: AppColors.red2),
                    label: const Text('ยุบคลับ',
                        style: TextStyle(color: AppColors.red2)))
              ],
            ]);
          }));
  Widget _menu(IconData icon, String label, VoidCallback action) => ListTile(
      leading: Icon(icon, color: _accent),
      title: Text(label),
      trailing: const Icon(Icons.chevron_right),
      onTap: action);
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
