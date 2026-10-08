import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/auth_provider.dart';
import '../models/training_date.dart';
import 'api_client.dart';

final statsApiProvider =
    Provider((ref) => StatsApi(ref.watch(apiClientProvider)));
double? _number(Object? value) {
  final n = double.tryParse('$value');
  return n != null && n.isFinite && n >= 0 ? n : null;
}

class RunHistoryEntry {
  final String id;
  final DateTime date;
  final double? distance, seconds, heartRate, maxHeartRate;
  final String? environment, type;
  final Map<String, dynamic>? feedback;
  RunHistoryEntry(Map<String, dynamic> json)
      : id = json['id'] as String,
        date = trainingDate(
            json['session_date'] ?? json['ended_at'] ?? json['started_at'])!,
        distance = _number(json['distance_km']),
        seconds = _number(json['duration_seconds']),
        heartRate = _number(json['avg_heart_rate_bpm']),
        maxHeartRate = _number(json['max_heart_rate_bpm']),
        environment = json['environment'] as String?,
        type = json['session_type'] as String?,
        feedback = (json['rpe_logs'] as List?)?.isNotEmpty == true
            ? Map<String, dynamic>.from((json['rpe_logs'] as List).first as Map)
            : null;
  String get pace => formatPace(seconds, distance);
}

String formatPace(double? seconds, double? km) {
  if (seconds == null || km == null || km <= 0 || seconds <= 0) return '—';
  final value = (seconds / km).round();
  return '${value ~/ 60}:${(value % 60).toString().padLeft(2, '0')}';
}

String formatRunTime(double seconds) {
  final value = seconds.round();
  return '${value ~/ 3600}:${((value % 3600) ~/ 60).toString().padLeft(2, '0')}:${(value % 60).toString().padLeft(2, '0')}';
}

class RunStats {
  final List<RunHistoryEntry> runs;
  RunStats(List<RunHistoryEntry> history, int? days, DateTime today)
      : runs = history
            .where((r) =>
                !r.date.isAfter(today) &&
                (days == null ||
                    !r.date.isBefore(today.subtract(Duration(days: days - 1)))))
            .toList();
  double get distance => runs.fold(0, (sum, r) => sum + (r.distance ?? 0));
  double get seconds => runs.fold(0, (sum, r) => sum + (r.seconds ?? 0));
  double get longest =>
      runs.fold(0, (best, r) => (r.distance ?? 0) > best ? r.distance! : best);
  String get pace {
    final paired =
        runs.where((r) => (r.distance ?? 0) > 0 && (r.seconds ?? 0) > 0);
    return formatPace(paired.fold<double>(0, (sum, r) => sum + r.seconds!),
        paired.fold<double>(0, (sum, r) => sum + r.distance!));
  }

  double? get averageRpe {
    final values = runs
        .map((r) => _number(r.feedback?['rpeScore']))
        .whereType<double>()
        .toList();
    return values.isEmpty
        ? null
        : values.reduce((a, b) => a + b) / values.length;
  }
}

class StatsApi {
  final ApiClient client;
  StatsApi(this.client);
  Future<List<RunHistoryEntry>> history() async {
    final response = await client.get(
        '/api/running-sessions/history?sortBy=date&order=desc',
        auth: true);
    return (response['data']['sessions'] as List)
        .cast<Map<String, dynamic>>()
        .where((r) =>
            r['status'] == 'completed' &&
            trainingDate(
                    r['session_date'] ?? r['ended_at'] ?? r['started_at']) !=
                null)
        .map(RunHistoryEntry.new)
        .toList()
      ..sort((a, b) => b.date.compareTo(a.date));
  }

  Future<Map<String, dynamic>> detail(String id) async =>
      (await client.get('/api/running-sessions/${Uri.encodeComponent(id)}',
          auth: true))['data'] as Map<String, dynamic>;
}
