import 'package:flutter/material.dart';
import '../../app_theme.dart';
import '../../widgets/common.dart';
import '../auth/login_screen.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 30),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('ตั้งค่า', style: AppText.heading(size: 20)),
          const SectionLabel(title: 'บัญชีและโปรไฟล์'),
          _MenuTile(icon: Icons.person_outline, label: 'แก้ไขโปรไฟล์', onTap: () {}),
          const SizedBox(height: 10),
          _MenuTile(icon: Icons.menu_book_outlined, label: 'ประวัติการวิ่ง', onTap: () {}),
          const SizedBox(height: 10),
          _MenuTile(icon: Icons.flag_outlined, label: 'เป้าหมายการวิ่ง', onTap: () {}),
          const SectionLabel(title: 'การเชื่อมต่อ'),
          _MenuTile(icon: Icons.link_rounded, label: 'เชื่อมต่อ API ภายนอก', onTap: () {}),
          const SectionLabel(title: 'อื่นๆ'),
          _MenuTile(
            icon: Icons.logout_rounded,
            label: 'ออกจากระบบ',
            danger: true,
            onTap: () {
              Navigator.of(context)
                  .pushAndRemoveUntil(MaterialPageRoute(builder: (_) => const LoginScreen()), (route) => false);
            },
          ),
        ],
      ),
    );
  }
}

class _MenuTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool danger;
  const _MenuTile({required this.icon, required this.label, required this.onTap, this.danger = false});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AppCard(
        borderColor: danger ? AppColors.red1.withOpacity(.4) : AppColors.border,
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(.05),
                borderRadius: BorderRadius.circular(10),
              ),
              alignment: Alignment.center,
              child: Icon(icon, size: 18, color: danger ? AppColors.red1 : AppColors.textPrimary),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(label,
                  style: AppText.body(size: 14, weight: FontWeight.w600, color: danger ? AppColors.red1 : AppColors.textPrimary)),
            ),
            Icon(Icons.chevron_right_rounded, color: AppColors.textSecondary),
          ],
        ),
      ),
    );
  }
}
