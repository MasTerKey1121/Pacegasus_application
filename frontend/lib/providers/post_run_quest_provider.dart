import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'auth_provider.dart';
import 'daily_quest_provider.dart';
import 'progress_provider.dart';
import 'run_rewards_provider.dart';
import 'run_setup_provider.dart';
import 'run_provider.dart';

// Keep this association across feedback reset and retry. Losing it would let
// a completed quest with a lost reward response masquerade as feedback-only.
final _questAtFinishProvider = Provider.family<String?, String>((ref, session) {
  ref.watch(authProvider.select((s) => s.user?['id']));
  return ref.read(runSetupProvider).mainQuestAtStart;
});

/// Kept alive across Summary -> Reward. Delayed quests never block a confirmed
/// run or feedback navigation, and missing amounts remain explicitly unknown.
final postRunQuestCheckProvider =
    FutureProvider.family<void, String>((ref, session) async {
  final owner = ref.watch(authProvider.select((s) => s.user?['id']));
  if (owner == null) return;
  final ledger = ref.read(runRewardsProvider);
  final daily = ref.read(dailyQuestProvider);
  final mainAtStart = ref.read(_questAtFinishProvider(session));
  bool alive = true;
  ref.onDispose(() => alive = false);
  final clock = Stopwatch()..start();
  final reference = ref.read(runProvider).finishReference ?? 'post-run';
  debugPrint('[RunFinish] ref=$reference stage=quest_rewards_start');
  await ledger.expectSource(session, 'ตรวจสอบภารกิจ');
  // Do not time out the quest's mutating request and launch a parallel retry.
  // DailyQuestNotifier already shares the in-flight future and checks status.
  await daily.refresh();
  if (!alive || ref.read(authProvider).user?['id'] != owner) return;
  if (daily.error != null) {
    debugPrint(
        '[RunFinish] ref=$reference stage=quest_rewards_pending elapsedMs=${clock.elapsedMilliseconds}');
    throw StateError('ผลวิ่งบันทึกแล้ว รางวัลยังรอตรวจสอบ');
  }
  if (mainAtStart != null &&
      daily.completed &&
      daily.quest?['id']?.toString() == mainAtStart) {
    await ledger.expectSource(session, 'Main Quest');
  }
  await ledger.resolveCheck(session, 'ตรวจสอบภารกิจ');
  if (!alive) return;
  ref.invalidate(progressProvider);
  debugPrint(
      '[RunFinish] ref=$reference stage=quest_rewards_checked elapsedMs=${clock.elapsedMilliseconds}');
});
