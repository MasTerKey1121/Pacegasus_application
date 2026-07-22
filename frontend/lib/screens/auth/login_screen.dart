import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../app_theme.dart';
import '../../widgets/common.dart';
import '../../providers/auth_provider.dart';
import '../../services/api_client.dart';
import 'register_screen.dart';
import 'otp_screen.dart';
import '../home/main_shell.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _emailController = TextEditingController();
  bool _loading = false;

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    final email = _emailController.text.trim();
    if (email.isEmpty || !email.contains('@')) {
      showAppToast(context, 'กรุณากรอกอีเมลให้ถูกต้อง');
      return;
    }

    setState(() => _loading = true);
    try {
      final authApi = ref.read(authApiProvider);
      final res = await authApi.requestOtp(email: email, purpose: 'login');
      final otpRef = res['data']['otpRef'] as String;

      if (!mounted) return;
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => OtpScreen(
            email: email,
            otpRef: otpRef,
            purpose: 'login',
            onVerified: () {
              Navigator.of(context).pushAndRemoveUntil(
                MaterialPageRoute(builder: (_) => const MainShell()),
                (route) => false,
              );
            },
          ),
        ),
      );
    } on ApiException catch (e) {
      showAppToast(context, e.message);
    } catch (_) {
      showAppToast(context, 'เชื่อมต่อเซิร์ฟเวอร์ไม่ได้ ลองใหม่อีกครั้ง');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

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
                AppTextField(
                  label: 'Email',
                  hint: 'you@email.com',
                  controller: _emailController,
                  keyboardType: TextInputType.emailAddress,
                ),
                const SizedBox(height: 22),
                GradientButton(
                  label: _loading ? 'กำลังส่งรหัส...' : 'เข้าสู่ระบบ',
                  onTap: _loading ? null : _login,
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
                    // TODO: ยังไม่ต่อจริง — รอ google_sign_in + POST /api/auth/google
                    Navigator.of(context).pushAndRemoveUntil(
                      MaterialPageRoute(builder: (_) => const MainShell()),
                      (route) => false,
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