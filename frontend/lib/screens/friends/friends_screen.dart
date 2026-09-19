import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../app_theme.dart';
import '../../providers/auth_provider.dart';
import '../../services/api_client.dart';
import '../../services/friend_api.dart';

final friendApiProvider =
    Provider<FriendApi>((ref) => FriendApi(ref.watch(apiClientProvider)));

class FriendsScreen extends ConsumerStatefulWidget {
  const FriendsScreen({super.key});

  @override
  ConsumerState<FriendsScreen> createState() => _FriendsScreenState();
}

class _FriendsScreenState extends ConsumerState<FriendsScreen> {
  final _search = TextEditingController();
  List<FriendEntry> _entries = [];
  int _tab = 0, _generation = 0;
  bool _loading = true;
  String? _error;
  final _busy = <String>{};

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

  Future<void> _load() async {
    final generation = ++_generation;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final entries = await ref.read(friendApiProvider).list(
          direction: _tab == 0
              ? null
              : _tab == 1
                  ? 'incoming'
                  : 'outgoing');
      if (!mounted || generation != _generation) return;
      setState(() {
        _entries = entries;
        _loading = false;
      });
    } catch (error) {
      if (!mounted || generation != _generation) return;
      setState(() {
        _error = _message(error);
        _loading = false;
      });
    }
  }

  Future<void> _add() async {
    final result = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: AppColors.bg2,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
      builder: (_) => const _AddFriendSheet(),
    );
    if (!mounted || result == null) return;
    _toast(
        result ? 'เป็นเพื่อนกันเรียบร้อยแล้ว' : 'ส่งคำขอแล้ว รอเพื่อนตอบรับ');
    setState(() {
      _tab = result ? 0 : 2;
      _search.clear();
    });
    await _load();
  }

  void _toast(String message) => ScaffoldMessenger.of(context)
      .showSnackBar(SnackBar(content: Text(message)));

  Future<void> _act(FriendEntry entry, {required bool accept}) async {
    if (_busy.contains(entry.friendshipId)) return;
    setState(() => _busy.add(entry.friendshipId));
    try {
      final api = ref.read(friendApiProvider);
      if (accept) {
        await api.accept(entry.friendshipId);
      } else {
        await api.removeRequest(entry.friendshipId);
      }
      if (!mounted) return;
      _toast(accept ? 'ตอบรับเพื่อนแล้ว' : 'นำคำขอออกแล้ว');
      await _load();
    } catch (error) {
      if (mounted) _toast(_message(error));
    } finally {
      if (mounted) setState(() => _busy.remove(entry.friendshipId));
    }
  }

  @override
  Widget build(BuildContext context) {
    final query = _search.text.trim().toLowerCase();
    final visible =
        _entries.where((e) => e.name.toLowerCase().contains(query)).toList();
    return Scaffold(
      appBar:
          AppBar(title: const Text('Friends'), backgroundColor: AppColors.bg2),
      body: AppBackground(
          child: SafeArea(
              child: Column(children: [
        Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('เพื่อนร่วมทาง', style: AppText.heading(size: 28)),
                const SizedBox(height: 4),
                Text('เพิ่มเพื่อน แล้วออกวิ่งไปด้วยกัน',
                    style: AppText.body(color: AppColors.textSecondary)),
                const SizedBox(height: 24),
                Row(children: [
                  Expanded(
                      child: TextField(
                    controller: _search,
                    onChanged: (_) => setState(() {}),
                    decoration: InputDecoration(
                      hintText:
                          _tab == 0 ? 'ค้นหาชื่อเพื่อน' : 'ค้นหาชื่อในคำขอ',
                      prefixIcon: const Icon(Icons.search_rounded),
                      suffixIcon: query.isEmpty
                          ? null
                          : IconButton(
                              tooltip: 'ล้างการค้นหา',
                              onPressed: () => setState(_search.clear),
                              icon: const Icon(Icons.close, size: 18)),
                      filled: true,
                      fillColor: AppColors.cardHi,
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16),
                          borderSide: BorderSide.none),
                    ),
                  )),
                  const SizedBox(width: 10),
                  SizedBox(
                      height: 56,
                      width: 56,
                      child: IconButton.filled(
                        key: const Key('add-friend'),
                        tooltip: 'เพิ่มเพื่อน',
                        onPressed: _add,
                        style: IconButton.styleFrom(
                            backgroundColor: AppColors.purple1,
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16))),
                        icon: const Icon(Icons.person_add_alt_1_rounded),
                      )),
                ]),
                const SizedBox(height: 20),
                SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(children: [
                      for (final (index, label) in [
                        'เพื่อนของฉัน',
                        'คำขอที่ได้รับ',
                        'ส่งแล้ว'
                      ].indexed)
                        Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: ChoiceChip(
                              label: Text(label),
                              selected: _tab == index,
                              showCheckmark: false,
                              onSelected: (_) {
                                if (_tab == index) return;
                                setState(() {
                                  _tab = index;
                                  _search.clear();
                                });
                                _load();
                              },
                            )),
                    ])),
                const SizedBox(height: 12),
              ],
            )),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _error != null
                  ? _notice(
                      Icons.cloud_off_rounded, 'โหลดรายการไม่สำเร็จ', _error!,
                      action: TextButton.icon(
                          onPressed: _load,
                          icon: const Icon(Icons.refresh),
                          label: const Text('ลองอีกครั้ง')))
                  : RefreshIndicator(
                      onRefresh: _load,
                      child: CustomScrollView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        slivers: [
                          if (visible.isEmpty)
                            SliverFillRemaining(
                                hasScrollBody: false,
                                child: _notice(
                                  query.isNotEmpty
                                      ? Icons.search_off_rounded
                                      : Icons.people_outline_rounded,
                                  query.isNotEmpty
                                      ? 'ไม่พบชื่อนี้'
                                      : _tab == 0
                                          ? 'ยังไม่มีเพื่อน'
                                          : 'ยังไม่มีคำขอ',
                                  query.isNotEmpty
                                      ? 'ลองค้นหาด้วยชื่ออื่น'
                                      : _tab == 0
                                          ? 'กดปุ่ม + ข้างช่องค้นหาเพื่อเพิ่มเพื่อนด้วย UID'
                                          : 'คำขอเป็นเพื่อนจะแสดงที่นี่',
                                ))
                          else
                            SliverPadding(
                                padding:
                                    const EdgeInsets.fromLTRB(20, 0, 20, 24),
                                sliver: SliverList.builder(
                                    itemCount: visible.length,
                                    itemBuilder: (_, index) =>
                                        _card(visible[index]))),
                        ],
                      )),
        ),
      ]))),
    );
  }

  Widget _card(FriendEntry entry) {
    final busy = _busy.contains(entry.friendshipId);
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
          color: AppColors.cardHi,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppColors.border)),
      child: Column(children: [
        Row(children: [
          ClipOval(
              child: entry.avatarUrl == null || entry.avatarUrl!.isEmpty
                  ? _avatar()
                  : Image.network(entry.avatarUrl!,
                      width: 48,
                      height: 48,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => _avatar())),
          const SizedBox(width: 14),
          Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                Text(entry.name,
                    style: AppText.heading(size: 16),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis),
                Text('UID: ${entry.uid}',
                    style:
                        AppText.body(size: 12, color: AppColors.textSecondary)),
              ])),
          if (_tab == 0)
            const Icon(Icons.check_circle_outline,
                color: AppColors.purple2, size: 20),
        ]),
        if (_tab != 0) ...[
          const SizedBox(height: 12),
          if (busy)
            const LinearProgressIndicator()
          else
            Wrap(spacing: 12, children: [
              if (_tab == 1)
                FilledButton(
                    onPressed: () => _act(entry, accept: true),
                    child: const Text('ตอบรับ')),
              TextButton(
                  onPressed: () => _act(entry, accept: false),
                  child: Text(_tab == 1 ? 'ปฏิเสธ' : 'ยกเลิกคำขอ')),
            ]),
        ],
      ]),
    );
  }

  Widget _avatar() => Container(
      width: 48,
      height: 48,
      color: AppColors.bg2,
      child:
          const Icon(Icons.person_outline_rounded, color: AppColors.purple2));

  Widget _notice(IconData icon, String title, String subtitle,
          {Widget? action}) =>
      Center(
        child: Padding(
            padding: const EdgeInsets.all(28),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Container(
                  padding: const EdgeInsets.all(24),
                  decoration: const BoxDecoration(
                      color: AppColors.cardHi, shape: BoxShape.circle),
                  child: Icon(icon, size: 40, color: AppColors.purple2)),
              const SizedBox(height: 20),
              Text(title, style: AppText.heading(size: 20)),
              const SizedBox(height: 8),
              Text(subtitle,
                  textAlign: TextAlign.center,
                  style: AppText.body(color: AppColors.textSecondary)),
              if (action != null) action,
            ])),
      );
}

String _message(Object error) => error is ApiException
    ? error.message
    : 'เกิดข้อผิดพลาด กรุณาลองใหม่อีกครั้ง';

class _AddFriendSheet extends ConsumerStatefulWidget {
  const _AddFriendSheet();
  @override
  ConsumerState<_AddFriendSheet> createState() => _AddFriendSheetState();
}

class _AddFriendSheetState extends ConsumerState<_AddFriendSheet> {
  final _uid = TextEditingController();
  final _form = GlobalKey<FormState>();
  bool _sending = false;
  String? _error;

  @override
  void dispose() {
    _uid.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    if (_sending || !_form.currentState!.validate()) return;
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      final accepted = await ref.read(friendApiProvider).send(_uid.text);
      if (mounted) Navigator.pop(context, accepted);
    } catch (error) {
      if (mounted) {
        setState(() {
          _error = _message(error);
          _sending = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
        canPop: !_sending,
        child: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(
              24, 20, 24, 24 + MediaQuery.viewInsetsOf(context).bottom),
          child: Form(
              key: _form,
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Center(
                        child: Container(
                            width: 36,
                            height: 4,
                            decoration: BoxDecoration(
                                color: AppColors.borderHi,
                                borderRadius: BorderRadius.circular(4)))),
                    const SizedBox(height: 20),
                    Text('เพิ่มเพื่อน', style: AppText.heading(size: 24)),
                    const SizedBox(height: 6),
                    Text('กรอก UID จากหน้าโปรไฟล์ของเพื่อนเพื่อส่งคำขอ',
                        style: AppText.body(color: AppColors.textSecondary)),
                    const SizedBox(height: 24),
                    TextFormField(
                      key: const Key('friend-uid'),
                      controller: _uid,
                      enabled: !_sending,
                      textCapitalization: TextCapitalization.characters,
                      autocorrect: false,
                      textInputAction: TextInputAction.done,
                      onFieldSubmitted: (_) => _send(),
                      decoration: InputDecoration(
                          labelText: 'UID ของเพื่อน',
                          helperText: 'ตัวอักษรหรือตัวเลข 10 ตัว',
                          border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(16))),
                      validator: (value) =>
                          RegExp(r'^[23456789ABCDEFGHJKLMNPQRSTUVWXYZ]{10}$')
                                  .hasMatch((value ?? '').trim().toUpperCase())
                              ? null
                              : 'กรอก UID 10 ตัวให้ถูกต้อง (ไม่มี 0, 1, I, O)',
                    ),
                    if (_error != null)
                      Padding(
                          padding: const EdgeInsets.only(top: 12),
                          child: Text(_error!,
                              style: const TextStyle(color: AppColors.red2))),
                    const SizedBox(height: 20),
                    FilledButton.icon(
                        onPressed: _sending ? null : _send,
                        style: FilledButton.styleFrom(
                            minimumSize: const Size.fromHeight(52)),
                        icon: _sending
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2))
                            : const Icon(Icons.person_add_alt_1),
                        label: Text(
                            _sending ? 'กำลังส่งคำขอ…' : 'ส่งคำขอเป็นเพื่อน')),
                    const SizedBox(height: 12),
                  ])),
        ),
      );
}
