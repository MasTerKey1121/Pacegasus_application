import 'package:flutter/material.dart';
import '../../app_theme.dart';
import '../../widgets/common.dart';
import '../onboarding/onboarding_basic_screen.dart';

class RegisterScreen extends StatelessWidget {
  const RegisterScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: AppBackground(
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 50, 24, 24),
            child: Column(
              children: [
                const PacegasusLogo(),
                const SizedBox(height: 18),
                Text('Pacegasus', style: AppText.heading(size: 26, color: AppColors.gold1, weight: FontWeight.w700)),
                const SizedBox(height: 6),
                Text('สมัครสมาชิก', style: AppText.heading(size: 18)),
                const SizedBox(height: 32),
                const AppTextField(label: 'Email', hint: 'you@email.com'),
                const SizedBox(height: 16),
                const AppTextField(label: 'Password', hint: '••••••••', obscure: true),
                const SizedBox(height: 16),
                const AppTextField(label: 'Confirm Password', hint: '••••••••', obscure: true),
                const SizedBox(height: 26),
                GradientButton(
                  label: 'สมัครสมาชิก',
                  onTap: () {
                    Navigator.of(context).pushReplacement(
                      MaterialPageRoute(builder: (_) => const OnboardingBasicScreen()),
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
                  label: 'สมัครสมาชิกด้วย Google',
                  onTap: () {
                    Navigator.of(context).pushReplacement(
                      MaterialPageRoute(builder: (_) => const OnboardingBasicScreen()),
                    );
                  },
                ),
                const SizedBox(height: 26),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text('มีบัญชีแล้ว? ', style: AppText.body(size: 13, color: AppColors.textSecondary)),
                    GestureDetector(
                      onTap: () => Navigator.of(context).pop(),
                      child: Text('เข้าสู่ระบบ',
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
