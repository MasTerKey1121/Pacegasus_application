import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../app_theme.dart';
import '../../models/run_reward.dart';
import '../../providers/progress_provider.dart';
import '../../providers/run_rewards_provider.dart';
import '../../providers/post_run_quest_provider.dart';
import '../../widgets/common.dart';

class RewardScreen extends ConsumerWidget {
  final String? sessionId;
  final bool checkQuests;
  final int? coin;
  final int? exp;
  final List<SideQuestRewardReceipt> sideRewards;
  const RewardScreen(
      {super.key,
      required this.coin,
      required this.exp,
      this.sideRewards = const [],
      this.sessionId,
      this.checkQuests = false});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sideCoins =
        sideRewards.fold<int>(0, (sum, receipt) => sum + receipt.coins);
    final ledger = ref.watch(runRewardsProvider);
    final totalCoins = sessionId != null
        ? ledger.total(sessionId!)
        : (coin == null && sideRewards.isEmpty
            ? null
            : (coin ?? 0) + sideCoins);
    final totalExp =
        sessionId != null ? ledger.total(sessionId!, exp: true) : exp;
    final partialExp = sessionId != null && totalExp == null;
    final displayedExp = totalExp ??
        (sessionId == null
            ? null
            : ledger.confirmedTotal(sessionId!, exp: true));
    final progress = ref.watch(progressProvider);
    final questCheck = checkQuests && sessionId != null
        ? ref.watch(postRunQuestCheckProvider(sessionId!))
        : null;
    return Scaffold(
      body: AppBackground(
        child: SafeArea(
            child: LayoutBuilder(
          builder: (context, constraints) => SingleChildScrollView(
              child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: Padding(
              padding: const EdgeInsets.all(28),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                      width: 96,
                      height: 96,
                      decoration: const BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: AppColors.goldGradient),
                      alignment: Alignment.center,
                      child: const Text('🏅', style: TextStyle(fontSize: 44))),
                  const SizedBox(height: 22),
                  Text(
                      sessionId != null
                          ? 'รางวัลการวิ่งรอบนี้'
                          : sideRewards.isNotEmpty
                              ? 'รางวัลการวิ่งรอบนี้'
                              : coin == null || exp == null
                                  ? 'บันทึกการวิ่งแล้ว!'
                                  : coin == 0 && exp == 0
                                      ? 'บันทึกข้อมูลแล้ว'
                                      : 'รับรางวัลแล้ว!',
                      style: AppText.heading(size: 22)),
                  const SizedBox(height: 6),
                  Text(
                      sessionId != null
                          ? 'รายการรางวัลที่เซิร์ฟเวอร์ยืนยันสำหรับรอบนี้'
                          : sideRewards.isNotEmpty
                              ? 'รวมเหรียญที่ยืนยันแล้วจาก Side Quest และแบบสอบถาม'
                              : coin == null || exp == null
                                  ? 'ยังไม่มีข้อมูลรางวัลจากเซิร์ฟเวอร์'
                                  : 'จาก feedback หลังวิ่งครั้งนี้ (server ยืนยัน)',
                      textAlign: TextAlign.center,
                      style: AppText.body(
                          size: 13, color: AppColors.textSecondary)),
                  const SizedBox(height: 24),
                  Row(children: [
                    Expanded(
                        child: AppCard(
                            child: Column(children: [
                      Text('${totalCoins == null ? '—' : '+$totalCoins'} 🌙',
                          style: AppText.heading(
                              size: 22, color: AppColors.gold1)),
                      const SizedBox(height: 4),
                      Text('COIN',
                          style: AppText.body(
                              size: 11.5, color: AppColors.textSecondary)),
                    ]))),
                    const SizedBox(width: 12),
                    Expanded(
                        child: AppCard(
                            child: Column(children: [
                      Text('${displayedExp == null ? '—' : '+$displayedExp'} ⭐',
                          style: AppText.heading(
                              size: 22, color: AppColors.purple2)),
                      const SizedBox(height: 4),
                      Text(
                          partialExp
                              ? 'EXP ที่ยืนยันแล้ว'
                              : sessionId != null || sideRewards.isEmpty
                                  ? 'EXP'
                                  : 'EXP แบบสอบถาม',
                          textAlign: TextAlign.center,
                          style: AppText.body(
                              size: 11.5, color: AppColors.textSecondary)),
                      if (partialExp)
                        Text('ยังไม่รวม EXP บางภารกิจ',
                            textAlign: TextAlign.center,
                            style: AppText.body(
                                size: 10, color: AppColors.textSecondary)),
                    ]))),
                  ]),
                  const SizedBox(height: 18),
                  if (questCheck != null)
                    questCheck.when(
                        data: (_) => const SizedBox.shrink(),
                        loading: () => const Text('รางวัลภารกิจรอตรวจสอบ',
                            textAlign: TextAlign.center),
                        error: (_, __) => TextButton(
                            onPressed: () => ref.invalidate(
                                postRunQuestCheckProvider(sessionId!)),
                            child:
                                const Text('รางวัลภารกิจรอตรวจสอบ · ลองใหม่'))),
                  progress.when(
                    loading: () => const Padding(
                        padding: EdgeInsets.all(8),
                        child: CircularProgressIndicator()),
                    error: (_, __) => TextButton(
                        onPressed: () => ref.invalidate(progressProvider),
                        child: const Text('ลองโหลดยอดปัจจุบันอีกครั้ง')),
                    data: (p) => AppCard(
                        child: Column(children: [
                      Text('ยอดปัจจุบัน', style: AppText.heading(size: 14)),
                      Text('${p.coinBalance} เหรียญ · Level ${p.level}',
                          style: AppText.body(size: 13)),
                      const SizedBox(height: 8),
                      LinearProgressIndicator(value: p.fraction),
                      Text('${p.exp} / ${p.expToNext} EXP',
                          style: AppText.body(size: 12)),
                    ])),
                  ),
                  const SizedBox(height: 24),
                  GradientButton(
                      label: 'กลับหน้าหลัก',
                      onTap: () => Navigator.of(context).pop()),
                ],
              ),
            ),
          )),
        )),
      ),
    );
  }
}
