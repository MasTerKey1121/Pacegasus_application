import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../app_theme.dart';
import '../../widgets/common.dart';
import '../../providers/auth_provider.dart';
import '../../services/api_client.dart';
import 'otp_screen.dart';
import '../onboarding/onboarding_basic_screen.dart';
import 'login_screen.dart';

/// หน้าข้อกำหนดและการยินยอม — คั่นระหว่าง Register กับ OTP
/// Flow: RegisterScreen -> TermsConsentScreen -> (ยินยอม) -> ยิง OTP -> OtpScreen
///                                            -> (ไม่ยินยอม) -> pop กลับ RegisterScreen
class TermsConsentScreen extends ConsumerStatefulWidget {
  final String email;

  /// จำเป็นเฉพาะตอน register
  final String? displayName;

  /// ถ้าไม่เป็น null = login-mode (user login ผ่าน OTP มาแล้ว มี accessToken)
  /// กด "ยินยอม" แค่บันทึกการยอมรับ policy ไม่ต้องขอ OTP ใหม่
  final VoidCallback? onAcceptedDirectly;

  const TermsConsentScreen({
    super.key,
    required this.email,
    this.displayName,
    this.onAcceptedDirectly,
  });

  @override
  ConsumerState<TermsConsentScreen> createState() => _TermsConsentScreenState();
}

class _TermsConsentScreenState extends ConsumerState<TermsConsentScreen> {
  bool _agreedChecked = false;
  bool _loading = false;

  static const String _policyVersion = '2026-07'; // TODO: ย้ายไป config ถ้ามีการอัปเดตนโยบายบ่อย

  Future<void> _onAgree() async {
  if (!_agreedChecked || _loading) return;

  setState(() => _loading = true);
  try {
    final authApi = ref.read(authApiProvider);

    if (widget.onAcceptedDirectly != null) {
      // Login-mode: ผ่าน OTP login มาแล้ว แค่บันทึกการยอมรับ policy
      final res = await authApi.acceptPolicy(policyVersion: _policyVersion);
      final updatedUser = res['data']['user'] as Map<String, dynamic>;
      ref.read(authProvider.notifier).updateUser(updatedUser);

      if (!mounted) return;
      widget.onAcceptedDirectly!.call();
      return;
    }

    // Register-mode (flow เดิม)
    final res = await authApi.requestOtp(
      email: widget.email,
      purpose: 'register',
      policyAccepted: true,
      policyVersion: _policyVersion,
    );
    final otpRef = res['data']['otpRef'] as String;

    if (!mounted) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => OtpScreen(
          email: widget.email,
          otpRef: otpRef,
          purpose: 'register',
          displayName: widget.displayName,
          onVerified: (_) {
            Navigator.of(context).pushAndRemoveUntil(
              MaterialPageRoute(builder: (_) => const OnboardingBasicScreen()),
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

  void _onDisagree() {
  if (widget.onAcceptedDirectly != null) {
    // Login-mode: มี session ค้างอยู่แต่ไม่ยินยอม -> logout แล้วกลับไป LoginScreen
    // (pop() ใช้ไม่ได้ เพราะ route เดิมถูก pushAndRemoveUntil ทิ้งไปแล้ว)
    ref.read(authProvider.notifier).logout();
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (route) => false,
    );
    return;
  }
  // Register-mode: ไม่ยินยอม -> ย้อนกลับไปหน้า register
  Navigator.of(context).pop();
}

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: AppBackground(
        child: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
                child: Row(
                  children: [
                    RoundIconButton(icon: Icons.arrow_back, onTap: _onDisagree),
                  ],
                ),
              ),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Center(child: const PacegasusLogo(size: 48)),
                      const SizedBox(height: 16),
                      Center(
                        child: Text('ข้อกำหนดและการยินยอม',
                            textAlign: TextAlign.center,
                            style: AppText.heading(size: 20)),
                      ),
                      const SizedBox(height: 6),
                      Center(
                        child: Text(
                          'กรุณาอ่านและยืนยันก่อนสร้างบัญชีของคุณ',
                          textAlign: TextAlign.center,
                          style: AppText.body(size: 13, color: AppColors.textSecondary),
                        ),
                      ),
                      const SizedBox(height: 24),
                      AppCard(
                        padding: const EdgeInsets.all(18),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _termSection(
                              icon: Icons.description_outlined,
                              title: 'ข้อตกลงการใช้บริการ',
                              body:
                                  'เมื่อสมัครสมาชิก Pacegasus คุณตกลงที่จะใช้งานแอปตามวัตถุประสงค์ที่กำหนด '
                                  'ไม่ละเมิดสิทธิ์ผู้อื่น และรับผิดชอบต่อความถูกต้องของข้อมูลที่กรอกเข้าสู่ระบบ',
                            ),
                            const SizedBox(height: 18),
                            _divider(),
                            const SizedBox(height: 18),
                            _termSection(
                              icon: Icons.privacy_tip_outlined,
                              title: 'นโยบายความเป็นส่วนตัว',
                              body:
                                  'เราจะเก็บและใช้ข้อมูล เช่น อีเมล ชื่อที่แสดง และข้อมูลการฝึกซ้อม '
                                  'เพื่อให้บริการวางแผนการฝึกและวิเคราะห์ผลการวิ่งของคุณเท่านั้น '
                                  'โดยไม่นำไปเปิดเผยแก่บุคคลที่สามโดยไม่ได้รับอนุญาต',
                            ),
                            const SizedBox(height: 18),
                            _divider(),
                            const SizedBox(height: 18),
                            _termSection(
                              icon: Icons.mark_email_read_outlined,
                              title: 'การยืนยันตัวตนผ่าน OTP',
                              body:
                                  'เมื่อกดยินยอม ระบบจะส่งรหัส OTP ไปยังอีเมลที่คุณระบุ '
                                  'เพื่อใช้ยืนยันตัวตนและเปิดใช้งานบัญชีให้เสร็จสมบูรณ์',
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 18),
                      GestureDetector(
                        onTap: () => setState(() => _agreedChecked = !_agreedChecked),
                        behavior: HitTestBehavior.opaque,
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            AnimatedContainer(
                              duration: const Duration(milliseconds: 150),
                              width: 22,
                              height: 22,
                              margin: const EdgeInsets.only(top: 1),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(6),
                                gradient: _agreedChecked ? AppColors.purpleGradient : null,
                                color: _agreedChecked ? null : Colors.white.withOpacity(.03),
                                border: Border.all(
                                  color: _agreedChecked ? Colors.transparent : AppColors.border,
                                ),
                              ),
                              child: _agreedChecked
                                  ? const Icon(Icons.check, size: 16, color: Colors.white)
                                  : null,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                'ฉันได้อ่านและยินยอมตามข้อตกลงการใช้บริการและนโยบายความเป็นส่วนตัวข้างต้น',
                                style: AppText.body(size: 13, color: AppColors.textSecondary),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
                child: Column(
                  children: [
                    GradientButton(
                      label: _loading ? 'กำลังส่งรหัส...' : 'ยินยอมและดำเนินการต่อ',
                      onTap: (_agreedChecked && !_loading) ? _onAgree : null,
                    ),
                    const SizedBox(height: 12),
                    OutlineButton(
                      label: 'ไม่ยินยอม',
                      onTap: _loading ? null : _onDisagree,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _termSection({required IconData icon, required String title, required String body}) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 34,
          height: 34,
          margin: const EdgeInsets.only(top: 2),
          decoration: BoxDecoration(
            color: AppColors.purple1.withOpacity(.15),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, size: 17, color: AppColors.purple2),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: AppText.heading(size: 14)),
              const SizedBox(height: 6),
              Text(body, style: AppText.body(size: 12.5, color: AppColors.textSecondary)),
            ],
          ),
        ),
      ],
    );
  }

  Widget _divider() => Divider(color: AppColors.border, height: 1);
}
