import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/training_date.dart';
import '../services/program_api.dart';
import '../services/api_client.dart';
import '../services/running_session_api.dart';
import 'auth_provider.dart';
import 'program_provider.dart';
import 'run_setup_provider.dart';
import 'progress_provider.dart';
import 'training_day_provider.dart';
import 'run_rewards_provider.dart';

double? questNumber(Object? value) {
  final n = double.tryParse('$value');
  return n != null && n.isFinite && n >= 0 ? n : null;
}

/// No session/quest association exists for free runs in the current API.
/// Fallback: matching session type, completed on the quest's Bangkok date.
/// A run crossing midnight belongs entirely to its completion date.
double savedQuestValue(Map quest, Iterable<Map> sessions, String day) {
  final seen = <String>{};
  double total = 0;
  for (final session in sessions) {
    final id = session['id']?.toString();
    if (id == null ||
        !seen.add(id) ||
        session['status'] != 'completed' ||
        trainingDateKey(session['ended_at']) != day) {
      continue;
    }
    final linked = quest['running_session_id']?.toString();
    if (linked != null
        ? linked != id
        : session['session_type'] != quest['session_type']) {
      continue;
    }
    final seconds = questNumber(session['duration_seconds']);
    final value = switch (quest['unit']) {
      'km' => questNumber(session['distance_km']),
      'minutes' => seconds == null ? null : seconds / 60,
      _ => null,
    };
    if (value != null) total += value;
  }
  return total;
}

class DailyQuestNotifier extends ChangeNotifier {
  DailyQuestNotifier(this.api, this.sessions, this.owner, this.day,
      {this.onConfirmed, this.onRewardReceipt, String Function()? currentDay})
      : _currentDay = currentDay;
  final ProgramApi api;
  final RunningSessionApi sessions;
  final String owner, day;
  final VoidCallback? onConfirmed;
  final Future<void> Function(RewardReceipt receipt)? onRewardReceipt;
  Future<void>? _refreshing;
  final String Function()? _currentDay;
  Map<String, dynamic>? quest;
  Map? reward;
  double saved = 0;
  bool loading = false;
  String? error;
  bool _alive = true;
  bool get completed => quest?['status'] == 'completed';
  double? get target => questNumber(quest?['planned_value']);
  bool get supported => ['km', 'minutes'].contains(quest?['unit']);
  double get fraction =>
      target != null && target! > 0 ? (saved / target!).clamp(0.0, 1.0) : 0;

  Future<Map<String, dynamic>> _loadDay() {
    // Explicit dates avoid the backend current-week query's CURRENT_DATE
    // timezone. The range API requires to > from; filter the inclusive result
    // back to the exact Bangkok date below.
    final tomorrow =
        trainingDateKey(DateTime.parse(day).add(const Duration(days: 1)))!;
    return api.getQuestsInRange(from: day, to: tomorrow);
  }

  Future<void> refresh() {
    if (_refreshing != null) return _refreshing!;
    final future = _refresh();
    _refreshing = future;
    future.whenComplete(() {
      if (identical(_refreshing, future)) _refreshing = null;
    });
    return future;
  }

  Future<void> _refresh() async {
    if (loading || !_alive) return;
    loading = true;
    error = null;
    notifyListeners();
    try {
      // Read status first, including after a response is lost. Never repeat a
      // complete PATCH for a quest already reported completed by the server.
      final response = await _loadDay();
      if (!_alive) return;
      final list =
          ((response['data'] as Map)['quests'] as List).whereType<Map>();
      final previousQuestId = quest?['id'];
      quest = null;
      for (final item in list) {
        if (trainingDateKey(item['scheduled_date']) == day) {
          quest = Map<String, dynamic>.from(item);
          break;
        }
      }
      if (quest?['id'] != previousQuestId) reward = null;
      saved = 0;
      if (quest == null) return;
      if (!supported || target == null || target! <= 0) {
        if (!completed) error = 'ยังประเมินหน่วยหรือเป้าหมายของภารกิจนี้ไม่ได้';
        return;
      }
      final history = await sessions.history();
      if (!_alive) return;
      final rows =
          ((history['data'] as Map)['sessions'] as List).whereType<Map>();
      final details = <Map>[];
      final seen = <String>{};
      for (final row in rows) {
        final id = row['id']?.toString();
        if (id == null ||
            row['status'] != 'completed' ||
            trainingDateKey(row['ended_at']) != day ||
            !seen.add(id)) {
          continue;
        }
        final response = await sessions.getDetail(sessionId: id);
        if (!_alive) return;
        final detail = response['data'] as Map;
        if (detail['id'] != id || detail['user_id']?.toString() != owner) {
          throw StateError('ไม่สามารถยืนยันเจ้าของผลวิ่ง');
        }
        details.add(detail);
      }
      saved = savedQuestValue(quest!, details, day);
      if (completed || saved + 0.0000001 < target!) return;
      if (!['pending', 'in_progress', 'partial'].contains(quest!['status'])) {
        error = 'สถานะภารกิจนี้ยังไม่รองรับการขอรับรางวัล';
        return;
      }
      if (_currentDay != null && _currentDay!() != day) return;
      try {
        final latest = await _loadDay();
        if (!_alive || (_currentDay != null && _currentDay!() != day)) return;
        final matches = ((latest['data'] as Map)['quests'] as List)
            .whereType<Map>()
            .where((q) => q['id'] == quest!['id']);
        if (matches.isEmpty) {
          throw StateError('ภารกิจเปลี่ยนแล้ว กรุณาโหลดใหม่');
        }
        if (matches.first['status'] == 'completed') {
          quest = Map<String, dynamic>.from(matches.first);
          onConfirmed?.call();
          return;
        }
        if (!['pending', 'in_progress', 'partial']
            .contains(matches.first['status'])) {
          throw StateError('สถานะภารกิจเปลี่ยนแล้ว');
        }
        if (matches.first['planned_value'].toString() !=
                quest!['planned_value'].toString() ||
            matches.first['unit'] != quest!['unit']) {
          throw StateError('เป้าหมายเปลี่ยนแล้ว กรุณาโหลดใหม่');
        }
        final result = await api.completeQuest(quest!['id'].toString());
        if (!_alive) return;
        final data = result['data'] as Map;
        final confirmed = data['quest'] as Map;
        if (confirmed['id'] != quest!['id'] ||
            confirmed['status'] != 'completed') {
          throw StateError('ยังไม่ได้รับการยืนยัน');
        }
        quest = Map<String, dynamic>.from(confirmed);
        reward = data['reward'] is Map ? data['reward'] as Map : null;
        if (reward?['awarded'] == true && onRewardReceipt != null) {
          final eligible = details
              .where((r) => savedQuestValue(quest!, [r], day) > 0)
              .toList()
            ..sort((a, b) => '${b['ended_at']}'.compareTo('${a['ended_at']}'));
          final session = quest!['running_session_id']?.toString() ??
              (eligible.isEmpty ? null : eligible.first['id']?.toString());
          if (session != null) {
            try {
              await onRewardReceipt!(RewardReceipt(
                  'Main Quest',
                  quest!['id'].toString(),
                  session,
                  RewardReceipt.amount(reward!['coins']),
                  RewardReceipt.amount(reward!['exp'])));
            } catch (_) {
              error =
                  'server ยืนยันภารกิจแล้ว แต่เก็บใบยืนยันรางวัลในเครื่องไม่สำเร็จ';
            }
          }
        }
        onConfirmed?.call();
        // Keep confirmed state even if a subsequent read is unavailable.
        try {
          await _loadDay();
        } catch (_) {}
      } catch (e) {
        if (_alive) error = 'ครบเป้าหมายแล้ว แต่ยังบันทึกภารกิจไม่สำเร็จ: $e';
      }
    } catch (e) {
      if (_alive && e is ApiException && e.statusCode == 404) {
        quest = null;
      } else if (_alive) {
        error = 'โหลดสถานะภารกิจไม่สำเร็จ: $e';
      }
    } finally {
      if (_alive) {
        loading = false;
        notifyListeners();
      }
    }
  }

  @override
  void dispose() {
    _alive = false;
    super.dispose();
  }
}

final dailyQuestProvider = ChangeNotifierProvider<DailyQuestNotifier>((ref) {
  final owner =
      ref.watch(authProvider.select((s) => s.user?['id']))?.toString() ?? '';
  final day = ref.watch(trainingDayProvider);
  final notifier = DailyQuestNotifier(ref.read(programApiProvider),
      ref.read(runningSessionApiProvider), owner, day,
      currentDay: () => trainingDateKey(trainingToday())!,
      onRewardReceipt: (receipt) =>
          ref.read(runRewardsProvider).record(receipt),
      onConfirmed: () {
        ref.invalidate(progressProvider);
      });
  if (owner.isNotEmpty) scheduleMicrotask(notifier.refresh);
  return notifier;
});
