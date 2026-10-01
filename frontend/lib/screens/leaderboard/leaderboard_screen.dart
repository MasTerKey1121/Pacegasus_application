import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../app_theme.dart';
import '../../services/api_client.dart';
import '../../services/leaderboard_api.dart';

const _accent = Color(0xFFC5A2FF);
const _diamond = Color(0xFF7BDFFF);
const _gold = Color(0xFFFFD873);
const _silver = Color(0xFFD4D5E5);
const _panel = Color(0xFF201A32);

class LeaderboardScreen extends ConsumerStatefulWidget {
  const LeaderboardScreen({super.key});
  @override
  ConsumerState<LeaderboardScreen> createState() => _LeaderboardScreenState();
}

class _LeaderboardScreenState extends ConsumerState<LeaderboardScreen> {
  String _scope = 'individual';
  late Future<RankingData> _data;
  final _scroll = ScrollController();
  @override
  void initState() {
    super.initState();
    _reload();
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _reload() {
    _data = ref.read(leaderboardApiProvider).load(_scope);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: const Color(0xFF110E20),
        appBar: AppBar(
            title: const Text('จัดอันดับ'), backgroundColor: AppColors.bg2),
        body: AppBackground(
            child: SafeArea(
                top: false,
                child: Column(children: [
                  Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                      child: Column(children: [
                        Text('50 อันดับแรก',
                            style:
                                AppText.body(color: AppColors.textSecondary)),
                        const SizedBox(height: 12),
                        Row(children: [
                          Expanded(
                              child: Text('ประเภทการจัดอันดับ',
                                  style: AppText.body(size: 12))),
                          const SizedBox(width: 8),
                          DropdownButton<String>(
                              value: _scope,
                              underline: const SizedBox(),
                              items: const [
                                DropdownMenuItem(
                                    value: 'individual',
                                    child: Text('รายบุคคล')),
                                DropdownMenuItem(
                                    value: 'guild', child: Text('กิลด์')),
                              ],
                              onChanged: (value) {
                                if (value == null || value == _scope) return;
                                setState(() {
                                  _scope = value;
                                  _reload();
                                });
                                if (_scroll.hasClients) _scroll.jumpTo(0);
                              }),
                        ]),
                        SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: Row(children: [
                              Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 16, vertical: 10),
                                  decoration: BoxDecoration(
                                      gradient: AppColors.purpleGradient,
                                      borderRadius: BorderRadius.circular(20)),
                                  child: Text('ระยะทางต่อสัปดาห์',
                                      style: AppText.heading(size: 13))),
                              for (var i = 0; i < 3; i++)
                                Padding(
                                    padding: const EdgeInsets.only(left: 10),
                                    child: Tooltip(
                                        message:
                                            'หมวดจัดอันดับเพิ่มเติมเร็ว ๆ นี้',
                                        child: Container(
                                            width: 76,
                                            padding: const EdgeInsets.symmetric(
                                                vertical: 10),
                                            alignment: Alignment.center,
                                            decoration: BoxDecoration(
                                                border: Border.all(
                                                    color: AppColors.borderHi),
                                                borderRadius:
                                                    BorderRadius.circular(20)),
                                            child: const Text('—',
                                                style: TextStyle(
                                                    color: AppColors
                                                        .textTertiary))))),
                            ])),
                        const SizedBox(height: 12),
                      ])),
                  Expanded(
                      child: FutureBuilder<RankingData>(
                          future: _data,
                          builder: (_, snapshot) {
                            if (snapshot.connectionState !=
                                ConnectionState.done) {
                              return const Center(
                                  child: CircularProgressIndicator());
                            }
                            if (snapshot.hasError) {
                              return Center(
                                  child: Padding(
                                      padding: const EdgeInsets.all(24),
                                      child: Column(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Text(
                                                snapshot.error is ApiException
                                                    ? (snapshot.error
                                                            as ApiException)
                                                        .message
                                                    : 'โหลดอันดับไม่สำเร็จ',
                                                textAlign: TextAlign.center),
                                            TextButton(
                                                onPressed: () =>
                                                    setState(_reload),
                                                child:
                                                    const Text('ลองอีกครั้ง')),
                                          ])));
                            }
                            if (!snapshot.hasData) {
                              return const Center(
                                  child: CircularProgressIndicator());
                            }
                            final data = snapshot.data!;
                            final top = data.entries
                                .where((e) => e.rank! <= 3)
                                .toList();
                            final special = data.entries
                                .where((e) => e.rank! >= 4 && e.rank! <= 10)
                                .toList();
                            final normal = data.entries
                                .where((e) => e.rank! >= 11)
                                .toList();
                            final start = data.startsAt
                                .toUtc()
                                .add(const Duration(hours: 7));
                            final end = data.endsAt
                                .toUtc()
                                .add(const Duration(hours: 7))
                                .subtract(const Duration(days: 1));
                            return Column(children: [
                              Expanded(
                                  child: RefreshIndicator(
                                      onRefresh: () async {
                                        setState(_reload);
                                        await _data;
                                      },
                                      child: ListView(
                                          controller: _scroll,
                                          physics:
                                              const AlwaysScrollableScrollPhysics(),
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 16),
                                          children: [
                                            Text(
                                                '${start.day}/${start.month} – ${end.day}/${end.month} · เวลาไทย',
                                                textAlign: TextAlign.center,
                                                style: AppText.body(
                                                    size: 11,
                                                    color: AppColors
                                                        .textSecondary)),
                                            const SizedBox(height: 18),
                                            if (top.isNotEmpty) _podium(top),
                                            if (data.entries.isEmpty)
                                              const Padding(
                                                  padding: EdgeInsets.symmetric(
                                                      vertical: 56),
                                                  child: Text(
                                                      'ยังไม่มีระยะวิ่งที่บันทึกในสัปดาห์นี้',
                                                      textAlign:
                                                          TextAlign.center)),
                                            if (special.isNotEmpty) ...[
                                              _heading('อันดับ 4–10'),
                                              for (final entry in special)
                                                _row(entry,
                                                    special: true,
                                                    mine: entry.id ==
                                                        data.mine?.id)
                                            ],
                                            if (normal.isNotEmpty) ...[
                                              _heading('อันดับ 11–50'),
                                              for (final entry in normal)
                                                _row(entry,
                                                    mine: entry.id ==
                                                        data.mine?.id)
                                            ],
                                            const SizedBox(height: 24),
                                          ]))),
                              // Always pinned outside the scrollable list; never replaced by rank 50.
                              Container(
                                  key: const Key('my-ranking'),
                                  padding:
                                      const EdgeInsets.fromLTRB(16, 12, 16, 12),
                                  decoration: const BoxDecoration(
                                      color: AppColors.bg2,
                                      border: Border(
                                          top: BorderSide(
                                              color: AppColors.borderHi))),
                                  child: Column(children: [
                                    Text(
                                        _scope == 'guild'
                                            ? 'อันดับกิลด์ของคุณ'
                                            : 'อันดับของคุณ',
                                        style: AppText.heading(
                                            size: 14, color: _accent)),
                                    const SizedBox(height: 8),
                                    if (data.mine != null)
                                      _row(data.mine!,
                                          mine: true, current: true)
                                    else
                                      Padding(
                                          padding: const EdgeInsets.all(10),
                                          child: Text(
                                              _scope == 'guild'
                                                  ? 'ไม่มีอันดับ · คุณยังไม่ได้เข้าร่วมกิลด์'
                                                  : 'ไม่มีอันดับ',
                                              textAlign: TextAlign.center)),
                                  ])),
                            ]);
                          })),
                ]))),
      );

  Widget _heading(String title) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Row(children: [
        const Expanded(child: Divider(color: AppColors.borderHi)),
        const SizedBox(width: 12),
        Text(title, style: AppText.heading(size: 17, color: _accent)),
        const SizedBox(width: 12),
        const Expanded(child: Divider(color: AppColors.borderHi))
      ]));

  Widget _podium(List<RankingEntry> entries) {
    RankingEntry? at(int rank) {
      for (final e in entries) {
        if (e.rank == rank) return e;
      }
      return null;
    }

    return Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
      for (final rank in [2, 1, 3])
        Expanded(
            child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: at(rank) == null
                    ? const SizedBox()
                    : _podiumEntry(at(rank)!))),
    ]);
  }

  Widget _podiumEntry(RankingEntry entry) {
    final color = entry.rank == 1
        ? _diamond
        : entry.rank == 2
            ? _gold
            : _silver;
    return Column(children: [
      Icon(
          entry.rank == 1
              ? Icons.diamond_outlined
              : Icons.workspace_premium_outlined,
          color: color,
          size: entry.rank == 1 ? 30 : 24),
      const SizedBox(height: 6),
      Container(
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: color, width: 3),
              boxShadow: [
                BoxShadow(color: color.withValues(alpha: .22), blurRadius: 18)
              ]),
          child: _avatar(entry, 54)),
      const SizedBox(height: 8),
      Text(entry.name,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: AppText.body(size: 11)),
      const SizedBox(height: 4),
      Text('${entry.distance.toStringAsFixed(1)} กม.',
          textAlign: TextAlign.center,
          style: AppText.heading(size: 13, color: color)),
      const SizedBox(height: 12),
      Container(
          height: entry.rank == 1
              ? 104
              : entry.rank == 2
                  ? 82
                  : 65,
          width: double.infinity,
          alignment: Alignment.center,
          decoration: BoxDecoration(
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(12)),
              gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    color.withValues(alpha: .65),
                    color.withValues(alpha: .1)
                  ]),
              border: Border.all(color: color, width: 2)),
          child: Text('${entry.rank}',
              style: AppText.heading(size: 38, color: color))),
    ]);
  }

  Widget _avatar(RankingEntry entry, double size) => ClipOval(
      child: Container(
          width: size,
          height: size,
          color: _panel,
          child: entry.imageUrl == null || entry.imageUrl!.isEmpty
              ? Icon(_scope == 'guild' ? Icons.groups : Icons.person,
                  color: _accent)
              : Image.network(entry.imageUrl!,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => Icon(
                      _scope == 'guild' ? Icons.groups : Icons.person,
                      color: _accent))));

  Widget _row(RankingEntry entry,
          {bool special = false, bool mine = false, bool current = false}) =>
      Container(
          margin: EdgeInsets.only(bottom: current ? 0 : 10),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
          decoration: BoxDecoration(
              color: _panel,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                  color: special || mine ? _accent : AppColors.borderHi,
                  width: special ? 1.5 : 1),
              boxShadow: special
                  ? [
                      BoxShadow(
                          color: _accent.withValues(alpha: .16), blurRadius: 10)
                    ]
                  : null),
          child: Row(children: [
            SizedBox(
                width: entry.rank == null ? 80 : 30,
                child: Text(entry.rank?.toString() ?? 'ไม่มีอันดับ',
                    style: AppText.heading(
                        size: entry.rank == null ? 12 : 20,
                        color: mine || special
                            ? _accent
                            : AppColors.textPrimary))),
            const SizedBox(width: 6),
            _avatar(entry, 32),
            const SizedBox(width: 8),
            Expanded(
                child: Text(
                    current && _scope == 'individual' ? 'คุณ' : entry.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: AppText.body(size: 12))),
            const SizedBox(width: 6),
            Text('${entry.distance.toStringAsFixed(1)} กม.',
                style: AppText.heading(size: 12)),
          ]));
}
