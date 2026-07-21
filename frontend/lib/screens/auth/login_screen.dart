import 'package:flutter/material.dart';
import '../../app_theme.dart';
import '../../widgets/common.dart';
import 'register_screen.dart';
import '../home/daily_missions_screen.dart';
import '../onboarding/onboarding_basic_screen.dart';
import '../home/home_screen.dart';

class LoginScreen extends StatelessWidget {
  const LoginScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: AppBackground(
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 60, 24, 24),
            child: Column(
              children: [
                PacegasusLogo(),
                const SizedBox(height: 18),
                Text('Pacegasus', style: AppText.heading(size: 26, color: AppColors.gold1, weight: FontWeight.w700)),
                const SizedBox(height: 6),
                Text('เข้าสู่ระบบ', style: AppText.heading(size: 18)),
                const SizedBox(height: 32),
                const AppTextField(label: 'Username', hint: 'ชื่อผู้ใช้ของคุณ'),
                const SizedBox(height: 16),
                Align(
                  alignment: Alignment.centerRight,
                  child: Text('ลืมรหัสผ่าน?', style: AppText.body(size: 12.5, color: AppColors.textSecondary)),
                ),
                const SizedBox(height: 22),
                GradientButton(
                  label: 'เข้าสู่ระบบ',
                  onTap: () {
                    Navigator.of(context).pushReplacement(
                      MaterialPageRoute(builder: (_) => const HomeScreen()),
                    );
                  },
                ),
                const SizedBox(height: 22),
                Row(children: [
                  Expanded(child: Divider(color: AppColors.border)),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Text('หรือ', style: AppText.body(size: 12.5, color: AppColors.textTertiary)),
                  ),
                  Expanded(child: Divider(color: AppColors.border)),
                ]),
                const SizedBox(height: 22),
                OutlineButton(
                  label: 'เข้าสู่ระบบด้วย Google',
                  onTap: () {
                    Navigator.of(context).pushReplacement(
                      MaterialPageRoute(builder: (_) => const HomeScreen()),
                    );
                  },
                ),
                const SizedBox(height: 26),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text('ยังไม่มีบัญชี? ', style: AppText.body(size: 13, color: AppColors.textSecondary)),
                    GestureDetector(
                      onTap: () => Navigator.of(context)
                          .push(MaterialPageRoute(builder: (_) => const RegisterScreen())),
                      child: Text('สมัครสมาชิก',
                          style: AppText.body(size: 13, color: AppColors.purple2, weight: FontWeight.w600)),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
