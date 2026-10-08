import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../app_theme.dart';
import '../../models/training_date.dart';
import '../../models/run_result.dart';
import '../../services/api_client.dart';
import '../../services/stats_api.dart';
import '../../widgets/common.dart';
import '../../widgets/run_route_map.dart';

class StatsScreen extends ConsumerStatefulWidget {
  const StatsScreen({super.key});
  @override
  ConsumerState<StatsScreen> createState() => _StatsScreenState();
}

class _StatsScreenState extends ConsumerState<StatsScreen> {
  late Future<List<RunHistoryEntry>> _history;
  int? _days = 7;
  int _visible = 10;
  @override
  void initState() {
    super.initState();
    _history = ref.read(statsApiProvider).history();
  }

  Future<void> _refresh() async {
    final next = ref.read(statsApiProvider).history();
    setState(() {
      _history = next;
    });
    try {
      await next;
    } catch (_) {/* FutureBuilder presents the error. */}
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<List<RunHistoryEntry>>(
      future: _history,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(
              child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    const Icon(Icons.cloud_off,
                        color: AppColors.purple2, size: 40),
                    const SizedBox(height: 12),
                    Text('โหลดสถิติไม่สำเร็จ',
                        style: AppText.heading(size: 20)),
                    Text(
                        snapshot.error is ApiException
                            ? (snapshot.error as ApiException).message
                            : 'กรุณาลองอีกครั้ง',
                        textAlign: TextAlign.center),
                    TextButton.icon(
                        onPressed: _refresh,
                        icon: const Icon(Icons.refresh),
                        label: const Text('ลองอีกครั้ง')),
                  ])));
        }
        final today = trainingToday();
        final stats = RunStats(snapshot.data!, _days, today);
        return RefreshIndicator(
            onRefresh: _refresh,
            child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 30),
                children: [
                  Text('สถิติการวิ่ง', style: AppText.heading(size: 24)),
                  Text('นับเฉพาะการวิ่งที่จบแล้ว • ตามเวลาประเทศไทย',
                      style: AppText.body(
                          size: 12, color: AppColors.textSecondary)),
                  const SizedBox(height: 16),
                  Wrap(spacing: 8, children: [
                    for (final days in <int?>[7, 30, null])
                      ChoiceChip(
                          label: Text(days == null ? 'ทั้งหมด' : '$days วัน'),
                          selected: _days == days,
                          showCheckmark: false,
                          onSelected: (_) => setState(() {
                                _days = days;
                                _visible = 10;
                              }))
                  ]),
                  const SizedBox(height: 16),
                  _pair(
                      'ระยะทางรวม',
                      '${stats.distance.toStringAsFixed(2)} กม.',
                      'จำนวนครั้ง',
                      '${stats.runs.length} ครั้ง'),
                  const SizedBox(height: 10),
                  _pair('เวลารวม', formatRunTime(stats.seconds), 'เพซเฉลี่ย',
                      stats.pace == '—' ? '—' : '${stats.pace} /กม.'),
                  const SizedBox(height: 10),
                  _pair(
                      'วิ่งไกลที่สุด',
                      !stats.runs.any((r) => r.distance != null)
                          ? '—'
                          : '${stats.longest.toStringAsFixed(2)} กม.',
                      'RPE เฉลี่ย',
                      stats.averageRpe?.toStringAsFixed(1) ?? '—'),
                  const SectionLabel(title: 'แนวโน้มระยะทาง'),
                  AppCard(
                      child: _DistanceChart(
                          runs: stats.runs, days: _days, today: today)),
                  if (stats.runs
                      .any((r) => r.distance == null || r.seconds == null))
                    Text(
                        'บางรายการไม่มีระยะทางหรือเวลา ยอดรวมใช้เฉพาะข้อมูลที่บันทึกไว้',
                        style: AppText.body(
                            size: 11, color: AppColors.textSecondary)),
                  const SectionLabel(title: 'ประวัติการวิ่ง'),
                  if (stats.runs.isEmpty)
                    AppCard(
                        child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 24),
                            child: Column(children: [
                              const Icon(Icons.directions_run,
                                  color: AppColors.purple2, size: 36),
                              const SizedBox(height: 12),
                              Text('ยังไม่มีการวิ่งในช่วงนี้',
                                  style: AppText.heading(size: 16)),
                              const Text('เมื่อจบการวิ่ง ข้อมูลจะแสดงที่นี่')
                            ]))),
                  for (final run in stats.runs.take(_visible))
                    Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: AppCard(
                            onTap: () => showDialog<void>(
                                context: context,
                                builder: (_) => _RunDetail(run: run)),
                            child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(children: [
                                    Expanded(
                                        child: Text(_date(run.date),
                                            style: AppText.heading(size: 16))),
                                    const Icon(Icons.chevron_right,
                                        color: AppColors.purple2)
                                  ]),
                                  Text(
                                      '${_environment(run.environment)}${run.type == null ? '' : ' • ${_runType(run.type!)}'}',
                                      style: AppText.body(
                                          size: 12,
                                          color: AppColors.textSecondary)),
                                  const SizedBox(height: 10),
                                  Wrap(spacing: 16, runSpacing: 6, children: [
                                    Text(run.distance == null
                                        ? '— กม.'
                                        : '${run.distance!.toStringAsFixed(2)} กม.'),
                                    Text(run.seconds == null
                                        ? '—'
                                        : formatRunTime(run.seconds!)),
                                    Text('เพซ ${run.pace}'),
                                  ]),
                                ]))),
                  if (_visible < stats.runs.length)
                    TextButton(
                        onPressed: () => setState(() => _visible += 10),
                        child: const Text('ดูเพิ่ม')),
                ]));
      });
  Widget _pair(String a, String av, String b, String bv) => Row(children: [
        Expanded(child: _metric(a, av)),
        const SizedBox(width: 10),
        Expanded(child: _metric(b, bv))
      ]);
}

Widget _metric(String label, String value) => AppCard(
    padding: const EdgeInsets.all(14),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label,
          style: AppText.body(size: 12, color: AppColors.textSecondary)),
      const SizedBox(height: 6),
      FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(value,
              style: AppText.heading(size: 21, color: AppColors.purple2))),
    ]));
String _date(DateTime date) => '${date.day}/${date.month}/${date.year + 543}';
String _environment(String? value) => value == 'treadmill'
    ? 'ลู่วิ่ง'
    : value == 'outdoor'
        ? 'กลางแจ้ง'
        : 'การวิ่ง';

String _runType(String value) =>
    const {
      'easy': 'วิ่งเบา',
      'tempo': 'เทมโป',
      'vo2max': 'อินเทอร์วัล',
      'interval': 'อินเทอร์วัล',
      'long_run': 'วิ่งระยะไกล',
    }[value] ??
    value;

String _mood(Object? value) =>
    const {
      'exhausted': '😩 เหนื่อยมาก',
      'bad': '🙁 ไม่ค่อยดี',
      'neutral': '🙂 ปกติ',
      'good': '😃 ดี',
      'great': '🤩 ดีมาก',
    }[value] ??
    '—';

class _DistanceChart extends StatelessWidget {
  final List<RunHistoryEntry> runs;
  final int? days;
  final DateTime today;
  const _DistanceChart(
      {required this.runs, required this.days, required this.today});
  @override
  Widget build(BuildContext context) {
    final dates = days == null
        ? [for (var i = 11; i >= 0; i--) DateTime(today.year, today.month - i)]
        : [
            for (var i = days! - 1; i >= 0; i--)
              today.subtract(Duration(days: i))
          ];
    final values = dates
        .map((d) => runs
            .where((r) => days == null
                ? r.date.year == d.year && r.date.month == d.month
                : r.date == d)
            .fold<double>(0, (s, r) => s + (r.distance ?? 0)))
        .toList();
    final maxValue = values.fold<double>(0, math.max);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text(days == null ? 'รายเดือน • 12 เดือนล่าสุด' : 'ระยะทางรายวัน',
          style: AppText.body(size: 12)),
      const SizedBox(height: 8),
      Text('สูงสุด ${maxValue.toStringAsFixed(2)} กม.',
          style: AppText.body(size: 11, color: AppColors.textSecondary)),
      if (maxValue == 0)
        const Padding(
            padding: EdgeInsets.all(20),
            child: Center(child: Text('ยังไม่มีระยะทางในช่วงกราฟ')))
      else
        SizedBox(
            height: 150,
            child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child:
                    Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                  for (var i = 0; i < dates.length; i++)
                    Tooltip(
                        message:
                            '${days == null ? '${dates[i].month}/${dates[i].year + 543}' : _date(dates[i])}: ${values[i].toStringAsFixed(2)} กม.',
                        triggerMode: TooltipTriggerMode.tap,
                        child: SizedBox(
                            width: 38,
                            child: Column(
                                mainAxisAlignment: MainAxisAlignment.end,
                                children: [
                                  Container(
                                      width: 20,
                                      height: math.max(
                                          2, 110 * values[i] / maxValue),
                                      decoration: BoxDecoration(
                                          gradient: values[i] > 0
                                              ? AppColors.purpleGradient
                                              : null,
                                          color: values[i] == 0
                                              ? AppColors.border
                                              : null,
                                          borderRadius:
                                              BorderRadius.circular(5))),
                                  const SizedBox(height: 8),
                                  Text(
                                      days == null
                                          ? '${dates[i].month}'
                                          : '${dates[i].day}/${dates[i].month}',
                                      style: AppText.body(size: 10)),
                                ]))),
                ]))),
    ]);
  }
}

class _RunDetail extends ConsumerStatefulWidget {
  final RunHistoryEntry run;
  const _RunDetail({required this.run});
  @override
  ConsumerState<_RunDetail> createState() => _RunDetailState();
}

class _RunDetailState extends ConsumerState<_RunDetail> {
  late Future<Map<String, dynamic>> _detail;
  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    _detail = ref.read(statsApiProvider).detail(widget.run.id);
  }

  @override
  Widget build(BuildContext context) {
    final run = widget.run, feedback = widget.run.feedback;
    return Dialog(
        backgroundColor: AppColors.bg2,
        child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(children: [
                        Expanded(
                            child: Text(_date(run.date),
                                style: AppText.heading(size: 20))),
                        IconButton(
                            tooltip: 'ปิด',
                            onPressed: () => Navigator.pop(context),
                            icon: const Icon(Icons.close))
                      ]),
                      FutureBuilder<Map<String, dynamic>>(
                          future: _detail,
                          builder: (_, snap) => RunRouteMap(
                              points: RunRoutePoint.parse(
                                  snap.data?['route_points']),
                              loading:
                                  snap.connectionState != ConnectionState.done,
                              treadmill: run.environment == 'treadmill',
                              loadFailed: snap.hasError,
                              onRetry: () => setState(_load))),
                      const SizedBox(height: 16),
                      Text(
                          '${_environment(run.environment)} • ${run.distance?.toStringAsFixed(2) ?? '—'} กม.'),
                      Text(
                          'เวลา ${run.seconds == null ? '—' : formatRunTime(run.seconds!)} • เพซ ${run.pace} /กม.'),
                      const SizedBox(height: 16),
                      Text('ชีพจร', style: AppText.heading(size: 16)),
                      Text(
                          'เฉลี่ย ${run.heartRate?.round() ?? '—'} • สูงสุด ${run.maxHeartRate?.round() ?? '—'} BPM'),
                      const SizedBox(height: 16),
                      Text('ความรู้สึกหลังวิ่ง',
                          style: AppText.heading(size: 16)),
                      if (feedback == null)
                        const Text('ยังไม่ได้บันทึกความรู้สึกหลังวิ่ง')
                      else ...[
                        Text('ความหนัก RPE ${feedback['rpeScore'] ?? '—'} /10'),
                        Text(
                            'ความเครียด ${feedback['stressLevel'] ?? '—'} /10'),
                        Text('อารมณ์ ${_mood(feedback['mood'])}'),
                        Text(
                            'อาการบาดเจ็บ: ${feedback['hasPain'] == null ? '—' : feedback['hasPain'] == true ? 'มีอาการ' : 'ไม่มี'}'),
                      ],
                    ]))));
  }
}
