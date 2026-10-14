import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../app_theme.dart';
import '../../widgets/common.dart';
import '../../widgets/google_auth_button.dart';
import '../../providers/auth_provider.dart';
import '../../services/api_client.dart';
import 'terms_screen.dart';

class RegisterScreen extends ConsumerStatefulWidget {
  const RegisterScreen({super.key});

  @override
  ConsumerState<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends ConsumerState<RegisterScreen> {
  final _emailController = TextEditingController();
  final _nameController = TextEditingController();
  bool _googleLoading = false;
  bool _checkingEmail = false;

  @override
  void dispose() {
    _emailController.dispose();
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _goToTerms() async {
    if (_checkingEmail || _googleLoading) return;
    final email = _emailController.text.trim();
    final name = _nameController.text.trim();
    if (email.isEmpty || !email.contains('@')) {
      showAppToast(context, 'กรุณากรอกอีเมลให้ถูกต้อง');
      return;
    }
    if (name.isEmpty) {
      showAppToast(context, 'กรุณากรอกชื่อที่ใช้แสดง');
      return;
    }

    setState(() => _checkingEmail = true);
    try {
      await ref.read(authApiProvider).checkRegistration(email: email);
      if (!mounted) return;
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => TermsConsentScreen(
            email: email,
            displayName: name,
          ),
        ),
      );
    } on ApiException catch (e) {
      if (mounted) showAppToast(context, e.message);
    } catch (_) {
      if (mounted) {
        showAppToast(context, 'เชื่อมต่อเซิร์ฟเวอร์ไม่ได้ ลองใหม่อีกครั้ง');
      }
    } finally {
      if (mounted) setState(() => _checkingEmail = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: AppBackground(
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 50, 24, 24),
            child: Column(
              children: [
                PacegasusLogo(),
                const SizedBox(height: 18),
                Text('Pacegasus',
                    style: AppText.heading(
                        size: 26,
                        color: AppColors.gold1,
                        weight: FontWeight.w700)),
                const SizedBox(height: 6),
                Text('สมัครสมาชิก', style: AppText.heading(size: 18)),
                const SizedBox(height: 32),
                AppTextField(
                    label: 'ชื่อที่แสดง',
                    hint: 'ชื่อของคุณ',
                    controller: _nameController),
                const SizedBox(height: 16),
                AppTextField(
                  label: 'Email',
                  hint: 'you@email.com',
                  controller: _emailController,
                  keyboardType: TextInputType.emailAddress,
                ),
                const SizedBox(height: 16),
                GradientButton(
                  label:
                      _checkingEmail ? 'กำลังตรวจสอบอีเมล...' : 'สมัครสมาชิก',
                  onTap: _googleLoading || _checkingEmail ? null : _goToTerms,
                ),
                const SizedBox(height: 22),
                Row(children: [
                  Expanded(child: Divider(color: AppColors.border)),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Text('หรือ',
                        style: AppText.body(
                            size: 12.5, color: AppColors.textTertiary)),
                  ),
                  Expanded(child: Divider(color: AppColors.border)),
                ]),
                const SizedBox(height: 22),
                GoogleAuthButton(
                  label: 'สมัครสมาชิกด้วย Google',
                  enabled: !_checkingEmail,
                  onLoadingChanged: (value) =>
                      setState(() => _googleLoading = value),
                ),
                const SizedBox(height: 26),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text('มีบัญชีแล้ว? ',
                        style: AppText.body(
                            size: 13, color: AppColors.textSecondary)),
                    GestureDetector(
                      onTap: _googleLoading || _checkingEmail
                          ? null
                          : () => Navigator.of(context).pop(),
                      child: Text('เข้าสู่ระบบ',
                          style: AppText.body(
                              size: 13,
                              color: AppColors.purple2,
                              weight: FontWeight.w600)),
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
