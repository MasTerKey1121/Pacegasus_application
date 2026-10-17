import 'package:flutter/material.dart';
import '../../app_theme.dart';
import '../../widgets/common.dart';

class RewardScreen extends StatelessWidget {
  final int? coin;
  final int? exp;
  const RewardScreen({super.key, required this.coin, required this.exp});

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
                  decoration: BoxDecoration(
                      shape: BoxShape.circle, gradient: AppColors.goldGradient),
                  alignment: Alignment.center,
                  child: const Text('🏅', style: TextStyle(fontSize: 44)),
                ),
                const SizedBox(height: 22),
                Text(
                    coin == null || exp == null
                        ? 'บันทึกการวิ่งแล้ว!'
                        : coin == 0 && exp == 0
                            ? 'บันทึกข้อมูลแล้ว'
                            : 'รับรางวัลแล้ว!',
                    style: AppText.heading(size: 22)),
                const SizedBox(height: 6),
                Text(
                    coin == null || exp == null
                        ? 'ยังไม่มีข้อมูลรางวัลจากเซิร์ฟเวอร์'
                        : 'จาก feedback หลังวิ่งครั้งนี้ (server ยืนยัน)',
                    style:
                        AppText.body(size: 13, color: AppColors.textSecondary)),
                const SizedBox(height: 30),
                Row(children: [
                  Expanded(
                    child: AppCard(
                      child: Column(children: [
                        Text('${coin == null ? '—' : '+$coin'} 🌙',
                            style: AppText.heading(
                                size: 22, color: AppColors.gold1)),
                        const SizedBox(height: 4),
                        Text('COIN',
                            style: AppText.body(
                                size: 11.5, color: AppColors.textSecondary)),
                      ]),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: AppCard(
                      child: Column(children: [
                        Text('${exp == null ? '—' : '+$exp'} ⭐',
                            style: AppText.heading(
                                size: 22, color: AppColors.purple2)),
                        const SizedBox(height: 4),
                        Text('EXP',
                            style: AppText.body(
                                size: 11.5, color: AppColors.textSecondary)),
                      ]),
                    ),
                  ),
                ]),
                const SizedBox(height: 30),
                GradientButton(
                    label: 'กลับหน้าหลัก',
                    onTap: () => Navigator.of(context).pop()),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
