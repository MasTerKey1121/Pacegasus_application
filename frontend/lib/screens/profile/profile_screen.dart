import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../app_theme.dart';
import '../../providers/auth_provider.dart';
import '../../providers/user_provider.dart';
import '../../services/api_client.dart';
import '../../services/own_profile_api.dart';
import '../../widgets/common.dart';
import '../home/home_avatar.dart';

class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key});
  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  Map<String, dynamic>? _data;
  bool _loading = true;
  String? _error;
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await ref.read(ownProfileApiProvider).load();
      if (mounted) setState(() => _data = data);
    } catch (e) {
      if (mounted) {
        setState(() =>
            _error = e is ApiException ? e.message : 'โหลดโปรไฟล์ไม่สำเร็จ');
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _edit(String field) async {
    final updated = await showDialog<Map<String, dynamic>>(
        context: context,
        barrierDismissible: false,
        builder: (_) => _EditProfile(
            field: field, value: _data!['user'][field] as String? ?? ''));
    if (updated == null || !mounted) return;
    setState(() => _data!['user'] = updated);
    final account = ref.read(authProvider).user;
    if (account != null) {
      ref.read(authProvider.notifier).updateUser({...account, ...updated});
    }
    final user = ref.read(userProvider);
    user.setDisplayName(updated['displayName'] as String);
  }

  @override
  Widget build(BuildContext context) {
    final user =
        _data?['user'] as Map<String, dynamic>? ?? ref.watch(authProvider).user;
    final uid = user?['uid']?.toString().trim();
    final name = user?['displayName']?.toString().trim();
    final stats = _data?['stats'] as Map<String, dynamic>?;
    final club = _data?['club'] as Map<String, dynamic>?;
    return RefreshIndicator(
        onRefresh: _load,
        child: LayoutBuilder(
            builder: (context, constraints) => ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(24, 8, 24, 28),
                    children: [
                      if (_loading) const LinearProgressIndicator(),
                      SizedBox(
                          height:
                              (constraints.maxHeight * .48).clamp(200.0, 380.0),
                          child: const HomeAvatar()),
                      const SizedBox(height: 20),
                      Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            CircleAvatar(
                                radius: 36,
                                backgroundColor: AppColors.cardHi,
                                child: ClipOval(
                                    child: user?['avatarUrl'] == null
                                        ? const Icon(Icons.person_outline,
                                            size: 42, color: AppColors.purple2)
                                        : Image.network(
                                            user!['avatarUrl'] as String,
                                            width: 72,
                                            height: 72,
                                            fit: BoxFit.cover,
                                            errorBuilder: (_, __, ___) =>
                                                const Icon(Icons.person_outline,
                                                    size: 42,
                                                    color:
                                                        AppColors.purple2)))),
                            const SizedBox(width: 16),
                            Expanded(
                                child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                  Row(children: [
                                    Expanded(
                                        child: Text(
                                            name == null || name.isEmpty
                                                ? 'นักวิ่ง'
                                                : name,
                                            maxLines: 2,
                                            overflow: TextOverflow.ellipsis,
                                            style: AppText.heading(size: 22))),
                                    IconButton(
                                        tooltip: 'แก้ไขชื่อ',
                                        onPressed: _data == null || _loading
                                            ? null
                                            : () => _edit('displayName'),
                                        icon: const Icon(Icons.edit_outlined,
                                            color: AppColors.purple2, size: 20))
                                  ]),
                                  Row(children: [
                                    Expanded(
                                        child: SelectableText(
                                            uid == null || uid.isEmpty
                                                ? 'UID: ยังไม่พร้อมใช้งาน'
                                                : 'UID: $uid',
                                            key: const Key('profile-uid'),
                                            style: AppText.body(
                                                size: 12,
                                                color:
                                                    AppColors.textSecondary))),
                                    if (uid != null && uid.isNotEmpty)
                                      IconButton(
                                          tooltip: 'คัดลอก UID',
                                          icon: const Icon(Icons.copy_outlined,
                                              size: 18),
                                          onPressed: () async {
                                            await Clipboard.setData(
                                                ClipboardData(text: uid));
                                            if (context.mounted) {
                                              showAppToast(
                                                  context, 'คัดลอก UID แล้ว');
                                            }
                                          })
                                  ]),
                                  if (club != null)
                                    Row(children: [
                                      const Icon(Icons.shield_outlined,
                                          size: 16, color: AppColors.purple2),
                                      const SizedBox(width: 6),
                                      Expanded(
                                          child: Text(club['name'] as String,
                                              style: AppText.body(
                                                  size: 13,
                                                  color:
                                                      AppColors.textSecondary)))
                                    ]),
                                ])),
                          ]),
                      if (_error != null)
                        Padding(
                            padding: const EdgeInsets.only(top: 12),
                            child: Column(children: [
                              Text(_error!,
                                  style:
                                      const TextStyle(color: AppColors.red2)),
                              TextButton(
                                  onPressed: _loading ? null : _load,
                                  child: const Text('ลองอีกครั้ง'))
                            ])),
                      const SizedBox(height: 16),
                      const Divider(color: AppColors.border),
                      const SizedBox(height: 16),
                      AppCard(
                          padding: const EdgeInsets.all(16),
                          child: Column(children: [
                            Row(children: [
                              Expanded(
                                  child: _stat(_km(stats?['weeklyDistanceKm']),
                                      'กม. สัปดาห์นี้')),
                              Expanded(
                                  child: _stat(
                                      stats?['weeklyRuns']?.toString() ?? '—',
                                      'ครั้งที่วิ่งสัปดาห์นี้'))
                            ]),
                            const SizedBox(height: 14),
                            const Divider(color: AppColors.border),
                            const SizedBox(height: 14),
                            Row(children: [
                              Expanded(
                                  child: _stat(_km(stats?['totalDistanceKm']),
                                      'กม. ทั้งหมด')),
                              Expanded(
                                  child: _stat(
                                      stats?['totalRuns']?.toString() ?? '—',
                                      'ครั้งที่วิ่งทั้งหมด'))
                            ]),
                          ])),
                    ])));
  }

  String _km(Object? value) => value is num ? value.toStringAsFixed(1) : '—';
  Widget _stat(String value, String label) => Column(children: [
        FittedBox(child: Text(value, style: AppText.heading(size: 28))),
        const SizedBox(height: 6),
        Text(label,
            textAlign: TextAlign.center,
            style: AppText.body(size: 12, color: AppColors.textSecondary))
      ]);
}

class _EditProfile extends ConsumerStatefulWidget {
  final String field, value;
  const _EditProfile({required this.field, required this.value});
  @override
  ConsumerState<_EditProfile> createState() => _EditProfileState();
}

class _EditProfileState extends ConsumerState<_EditProfile> {
  late final TextEditingController _input =
      TextEditingController(text: widget.value);
  final _form = GlobalKey<FormState>();
  bool _busy = false;
  String? _error;
  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_busy || !_form.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final user = await ref
          .read(ownProfileApiProvider)
          .save(widget.field, _input.text.trim());
      if (!mounted) return;
      setState(() => _busy = false);
      await WidgetsBinding.instance.endOfFrame;
      if (mounted) Navigator.pop(context, user);
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = e is ApiException
              ? e.message
              : 'บันทึกไม่สำเร็จ กรุณาลองอีกครั้ง';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
        canPop: !_busy,
        child: AlertDialog(
            title: const Text('แก้ไขชื่อ'),
            content: SingleChildScrollView(
                child: Form(
                    key: _form,
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      TextFormField(
                          controller: _input,
                          enabled: !_busy,
                          maxLength: 80,
                          maxLines: 1,
                          decoration: InputDecoration(
                              labelText: 'ชื่อ',
                              border: const OutlineInputBorder()),
                          validator: (value) => (value ?? '').trim().isEmpty
                              ? 'กรุณากรอกชื่อ'
                              : null),
                      if (_error != null)
                        Text(_error!,
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
}
