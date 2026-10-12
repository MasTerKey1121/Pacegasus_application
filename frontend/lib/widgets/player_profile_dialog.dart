import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../app_theme.dart';
import '../providers/auth_provider.dart';
import '../services/api_client.dart';
import '../services/club_api.dart';
import '../services/friend_api.dart';
import '../screens/home/home_avatar.dart';

Future<bool?> showPlayerProfile(BuildContext context, String identifier) =>
    showDialog<bool>(
        context: context,
        builder: (_) => PlayerProfileDialog(identifier: identifier));

class PlayerProfileDialog extends ConsumerStatefulWidget {
  final String identifier;
  const PlayerProfileDialog({super.key, required this.identifier});
  @override
  ConsumerState<PlayerProfileDialog> createState() =>
      _PlayerProfileDialogState();
}

class _PlayerProfileDialogState extends ConsumerState<PlayerProfileDialog> {
  Map<String, dynamic>? _data;
  String? _error;
  bool _busy = false, _changed = false;
  static const _roles = {
    'leader': 'หัวหน้าคลับ',
    'sub_leader': 'รองหัวหน้าคลับ',
    'member': 'สมาชิก'
  };
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final result = await ref.read(apiClientProvider).get(
          '/api/users/${Uri.encodeComponent(widget.identifier)}/profile',
          auth: true);
      if (mounted) {
        setState(() {
          _data = result['data'] as Map<String, dynamic>;
          _error = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = _message(e));
    }
  }

  String _message(Object e) =>
      e is ApiException ? e.message : 'เกิดข้อผิดพลาด กรุณาลองอีกครั้ง';
  Future<void> _act(Future<void> Function() action) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
      _changed = true;
      await _load();
    } catch (e) {
      if (mounted) setState(() => _error = _message(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<bool> _confirm(String title, String body) async =>
      await showDialog<bool>(
          context: context,
          builder: (context) =>
              AlertDialog(title: Text(title), content: Text(body), actions: [
                TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: const Text('ยกเลิก')),
                FilledButton(
                    onPressed: () => Navigator.pop(context, true),
                    child: const Text('ยืนยัน')),
              ])) ??
      false;

  Future<void> _kick() async {
    if (!await _confirm('นำออกจากคลับ',
            'ต้องการนำ ${_data!['user']['displayName'] ?? 'สมาชิก'} ออกจากคลับหรือไม่?') ||
        !mounted) {
      return;
    }
    await _act(() => ref
        .read(clubApiProvider)
        .kick(_data!['club']['id'] as String, _data!['user']['id'] as String));
  }

  Future<void> _role(String role) async {
    if (role == _data!['club']['role']) return;
    if (!await _confirm(
            'เปลี่ยนบทบาท', 'เปลี่ยนสมาชิกคนนี้เป็น${_roles[role]}หรือไม่?') ||
        !mounted) {
      return;
    }
    await _act(() => ref.read(clubApiProvider).role(
        _data!['club']['id'] as String, _data!['user']['id'] as String, role));
  }

  @override
  Widget build(BuildContext context) {
    final data = _data;
    return PopScope(
        canPop: !_busy,
        child: Dialog(
            backgroundColor: AppColors.bg2,
            insetPadding:
                const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(24),
                side: const BorderSide(color: AppColors.purple2)),
            child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 440),
                child: SingleChildScrollView(
                    padding: const EdgeInsets.all(20),
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      Row(children: [
                        Expanded(
                            child: Text('โปรไฟล์ผู้เล่น',
                                style: AppText.heading(size: 22))),
                        IconButton(
                            tooltip: 'ปิด',
                            onPressed: _busy
                                ? null
                                : () => Navigator.pop(context, _changed),
                            icon: const Icon(Icons.close))
                      ]),
                      if (data == null && _error == null)
                        const Padding(
                            padding: EdgeInsets.all(40),
                            child: CircularProgressIndicator()),
                      if (_error != null) ...[
                        Text(_error!,
                            style: const TextStyle(color: AppColors.red2)),
                        if (data == null)
                          TextButton(
                              onPressed: _load,
                              child: const Text('ลองอีกครั้ง'))
                      ],
                      if (data != null) ...[
                        Row(children: [
                          CircleAvatar(
                              radius: 32,
                              backgroundColor: AppColors.cardHi,
                              child: ClipOval(
                                  child: data['user']['avatarUrl'] == null
                                      ? const Icon(Icons.person,
                                          size: 38, color: AppColors.purple2)
                                      : Image.network(
                                          data['user']['avatarUrl'] as String,
                                          width: 64,
                                          height: 64,
                                          fit: BoxFit.cover,
                                          errorBuilder: (_, __, ___) =>
                                              const Icon(Icons.person,
                                                  size: 38)))),
                          const SizedBox(width: 12),
                          Expanded(
                              child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                Text(
                                    data['user']['displayName'] as String? ??
                                        'นักวิ่ง',
                                    style: AppText.heading(size: 18)),
                                Row(children: [
                                  Expanded(
                                      child: Text('UID ${data['user']['uid']}',
                                          style: AppText.body(size: 12))),
                                  IconButton(
                                      tooltip: 'คัดลอก UID',
                                      onPressed: () async {
                                        await Clipboard.setData(ClipboardData(
                                            text:
                                                data['user']['uid'] as String));
                                        if (context.mounted) {
                                          ScaffoldMessenger.of(context)
                                              .showSnackBar(const SnackBar(
                                                  content:
                                                      Text('คัดลอก UID แล้ว')));
                                        }
                                      },
                                      icon: const Icon(Icons.copy, size: 18))
                                ]),
                                Text(
                                    'คลับ ${data['club']?['name'] ?? 'ไม่มีคลับ'}',
                                    style: AppText.body(size: 12)),
                                Wrap(spacing: 8, children: [
                                  Chip(
                                      label:
                                          Text('Lv. ${data['user']['level']}')),
                                  if (data['club'] != null)
                                    Chip(
                                        label: Text(
                                            _roles[data['club']['role']] ??
                                                'สมาชิก'))
                                ]),
                              ]))
                        ]),
                        const SizedBox(height: 12),
                        const SizedBox(height: 220, child: HomeAvatar()),
                        Text('ตัวละครตัวอย่าง • ของที่สวมแสดงด้านล่าง',
                            style: AppText.body(
                                size: 11, color: AppColors.textSecondary)),
                        const SizedBox(height: 12),
                        if ((data['avatar']['equipment'] as List).isEmpty)
                          const Text('ยังไม่มีของที่สวม')
                        else
                          Wrap(spacing: 8, runSpacing: 8, children: [
                            for (final entry
                                in data['avatar']['equipment'] as List)
                              SizedBox(
                                  width: 84,
                                  child: Column(children: [
                                    Container(
                                        height: 68,
                                        width: 68,
                                        decoration: BoxDecoration(
                                            color: AppColors.cardHi,
                                            borderRadius:
                                                BorderRadius.circular(12),
                                            border: Border.all(
                                                color: AppColors.purple2)),
                                        child: entry['item']['thumbnailUrl'] ==
                                                null
                                            ? const Icon(Icons.checkroom,
                                                color: AppColors.purple2)
                                            : ClipRRect(
                                                borderRadius:
                                                    BorderRadius.circular(12),
                                                child: Image.network(
                                                    entry['item']
                                                            ['thumbnailUrl']
                                                        as String,
                                                    fit: BoxFit.contain,
                                                    errorBuilder: (_, __,
                                                            ___) =>
                                                        const Icon(
                                                            Icons.checkroom)))),
                                    Text(entry['item']['name'] as String,
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                        textAlign: TextAlign.center,
                                        style: AppText.body(size: 11))
                                  ]))
                          ]),
                        const SizedBox(height: 16),
                        Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                                color: AppColors.cardHi,
                                borderRadius: BorderRadius.circular(16)),
                            child: Column(children: [
                              const Text('ระยะทางสะสม'),
                              Text(
                                  '${(data['distanceKm'] as num).toStringAsFixed(1)} กม.',
                                  style: AppText.heading(size: 24))
                            ])),
                        const SizedBox(height: 16),
                        if (_busy) const LinearProgressIndicator(),
                        if (data['canManageMember'] == true) ...[
                          Row(children: [
                            Expanded(
                                child: PopupMenuButton<String>(
                                    enabled: !_busy,
                                    onSelected: _role,
                                    itemBuilder: (_) => [
                                          const PopupMenuItem<String>(
                                              enabled: false,
                                              child: Text(
                                                  'หัวหน้าคลับ\nการโอนสิทธิ์จะเพิ่มภายหลัง')),
                                          for (final role in [
                                            'sub_leader',
                                            'member'
                                          ])
                                            CheckedPopupMenuItem(
                                                value: role,
                                                checked: data['club']['role'] ==
                                                    role,
                                                child: Text(_roles[role]!))
                                        ],
                                    child: Container(
                                        padding: const EdgeInsets.all(12),
                                        decoration: BoxDecoration(
                                            borderRadius:
                                                BorderRadius.circular(12),
                                            border: Border.all(
                                                color: AppColors.purple2)),
                                        child: const Text('จัดการสมาชิก',
                                            textAlign: TextAlign.center)))),
                            const SizedBox(width: 8),
                            Expanded(
                                child: OutlinedButton(
                                    onPressed: _busy ? null : _kick,
                                    style: OutlinedButton.styleFrom(
                                        foregroundColor: AppColors.red2),
                                    child: const Text('นำออกจากคลับ')))
                          ]),
                          const SizedBox(height: 8)
                        ],
                        if (data['relationship']['status'] != 'self')
                          Row(children: [
                            Expanded(
                                child: FilledButton(
                                    onPressed: _busy ||
                                            data['relationship']['status'] ==
                                                'accepted' ||
                                            (data['relationship']['status'] ==
                                                    'pending' &&
                                                data['relationship']
                                                        ['direction'] ==
                                                    'outgoing')
                                        ? null
                                        : () => _act(() async {
                                              await FriendApi(ref
                                                      .read(apiClientProvider))
                                                  .send(data['user']['uid']
                                                      as String);
                                            }),
                                    child: Text(data['relationship']
                                                ['status'] ==
                                            'accepted'
                                        ? 'เป็นเพื่อนแล้ว'
                                        : data['relationship']['status'] ==
                                                'pending'
                                            ? data['relationship']
                                                        ['direction'] ==
                                                    'incoming'
                                                ? 'ตอบรับเพื่อน'
                                                : 'ส่งคำขอแล้ว'
                                            : 'เพิ่มเพื่อน'))),
                            const SizedBox(width: 8),
                            Expanded(
                                child: PopupMenuButton<String>(
                                    enabled: !_busy,
                                    itemBuilder: (_) => [
                                          const PopupMenuItem(
                                              enabled: false,
                                              child: Text(
                                                  'บล็อก • ยังไม่เปิดใช้งาน'))
                                        ],
                                    child: const Padding(
                                        padding: EdgeInsets.all(12),
                                        child: Text('••• เพิ่มเติม',
                                            textAlign: TextAlign.center))))
                          ]),
                      ],
                    ])))));
  }
}
