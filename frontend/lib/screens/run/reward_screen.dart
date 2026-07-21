import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../app_theme.dart';
import '../../providers/user_provider.dart';
import '../../widgets/common.dart';

class RewardScreen extends ConsumerStatefulWidget {
  final int coin;
  final int exp;
  const RewardScreen({super.key, required this.coin, required this.exp});

  @override
  ConsumerState<RewardScreen> createState() => _RewardScreenState();
}

class _RewardScreenState extends ConsumerState<RewardScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance
        .addPostFrameCallback((_) => ref.read(userProvider).addReward(coin: widget.coin, exp: widget.exp));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: AppBackground(
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 96,
                  height: 96,
                  decoration: BoxDecoration(shape: BoxShape.circle, gradient: AppColors.goldGradient),
                  alignment: Alignment.center,
                  child: const Text('🏅', style: TextStyle(fontSize: 44)),
                ),
                const SizedBox(height: 22),
                Text('รับรางวัลแล้ว!', style: AppText.heading(size: 22)),
                const SizedBox(height: 6),
                Text('จากการวิ่งครั้งนี้', style: AppText.body(size: 13, color: AppColors.textSecondary)),
                const SizedBox(height: 30),
                Row(children: [
                  Expanded(
                    child: AppCard(
                      child: Column(children: [
                        Text('+${widget.coin} 🌙', style: AppText.heading(size: 22, color: AppColors.gold1)),
                        const SizedBox(height: 4),
                        Text('COIN', style: AppText.body(size: 11.5, color: AppColors.textSecondary)),
                      ]),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: AppCard(
                      child: Column(children: [
                        Text('+${widget.exp} ⭐', style: AppText.heading(size: 22, color: AppColors.purple2)),
                        const SizedBox(height: 4),
                        Text('EXP', style: AppText.body(size: 11.5, color: AppColors.textSecondary)),
                      ]),
                    ),
                  ),
                ]),
                const SizedBox(height: 30),
                GradientButton(label: 'กลับหน้าหลัก', onTap: () => Navigator.of(context).pop()),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
