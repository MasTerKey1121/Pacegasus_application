import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../app_theme.dart';
import '../../models/run_reward.dart';
import '../../providers/progress_provider.dart';
import '../../providers/run_rewards_provider.dart';
import '../../widgets/common.dart';

class RewardScreen extends ConsumerWidget {
  final String? sessionId;
  final int? coin;
  final int? exp;
  final List<SideQuestRewardReceipt> sideRewards;
  const RewardScreen(
      {super.key,
      required this.coin,
      required this.exp,
      this.sideRewards = const [],
      this.sessionId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sideCoins =
        sideRewards.fold<int>(0, (sum, receipt) => sum + receipt.coins);
    final ledger = ref.watch(runRewardsProvider);
    final receipts =
        sessionId == null ? <RewardReceipt>[] : ledger.receipts(sessionId!);
    final totalCoins = sessionId != null
        ? ledger.total(sessionId!)
        : (coin == null && sideRewards.isEmpty
            ? null
            : (coin ?? 0) + sideCoins);
    final totalExp =
        sessionId != null ? ledger.total(sessionId!, exp: true) : exp;
    final progress = ref.watch(progressProvider);
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
                          ? (totalCoins == null || totalExp == null
                              ? 'ยังยืนยันรางวัลรวมไม่ได้'
                              : 'รางวัลการวิ่งรอบนี้')
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
                      Text('${totalExp == null ? '—' : '+$totalExp'} ⭐',
                          style: AppText.heading(
                              size: 22, color: AppColors.purple2)),
                      const SizedBox(height: 4),
                      Text(
                          sessionId != null || sideRewards.isEmpty
                              ? 'EXP'
                              : 'EXP แบบสอบถาม',
                          textAlign: TextAlign.center,
                          style: AppText.body(
                              size: 11.5, color: AppColors.textSecondary)),
                    ]))),
                  ]),
                  if (sessionId != null) ...[
                    const SizedBox(height: 12),
                    for (final row in receipts)
                      Text(
                          '${row.source}: ${row.coins == null ? 'ยังไม่ทราบเหรียญ' : '+${row.coins} เหรียญ'} · ${row.exp == null ? 'ยังไม่ทราบ EXP' : '+${row.exp} EXP'}',
                          textAlign: TextAlign.center,
                          style: AppText.body(size: 12)),
                    if (totalCoins == null || totalExp == null) ...[
                      const Text(
                          'รายละเอียดรางวัลบางส่วนยังยืนยันไม่ได้ ยอดบัญชีจริงอยู่ด้านล่าง',
                          textAlign: TextAlign.center),
                      TextButton(
                          onPressed: () async {
                            try {
                              await ref.read(rewardReloadProvider)(sessionId!);
                              ref.invalidate(progressProvider);
                            } catch (_) {
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                        content: Text(
                                            'ยังโหลดผลยืนยันรางวัลไม่ได้ กรุณาลองใหม่')));
                              }
                            }
                          },
                          child: const Text('ลองโหลดรายละเอียดรางวัลใหม่')),
                    ],
                  ] else if (sideRewards.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Text(
                        'Side Quest (${sideRewards.length} ภารกิจ): +$sideCoins เหรียญ',
                        style: AppText.body(size: 12)),
                    Text(
                        'แบบสอบถามหลังวิ่ง: ${coin == null ? 'รอยืนยัน' : '+$coin เหรียญ'}'
                        '${exp == null ? '' : ' · +$exp EXP'}',
                        style: AppText.body(size: 12)),
                    const SizedBox(height: 6),
                    Text('EXP ด้านบนเป็นของแบบสอบถาม ดูยอดรวมปัจจุบันด้านล่าง',
                        textAlign: TextAlign.center,
                        style: AppText.body(
                            size: 11, color: AppColors.textSecondary)),
                  ],
                  const SizedBox(height: 18),
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
