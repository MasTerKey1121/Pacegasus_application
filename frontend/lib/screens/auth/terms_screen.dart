import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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

  /// ถ้าไม่เป็น null = ยืนยันตัวตนผ่าน Google หรือ OTP แล้ว มี accessToken
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

  static const String _policyVersion = '1.0.0.1';

  void _showTerms() => showDialog<void>(
        context: context,
        builder: (_) => const _TermsDocumentDialog(),
      );

  Future<void> _onAgree() async {
    if (!_agreedChecked || _loading) return;

    setState(() => _loading = true);
    try {
      final authApi = ref.read(authApiProvider);

      if (widget.onAcceptedDirectly != null) {
        // ยืนยันตัวตนแล้ว: บันทึกการยอมรับ policy โดยไม่ขอ OTP อีก
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
                MaterialPageRoute(
                    builder: (_) => const OnboardingBasicScreen()),
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
                          style: AppText.body(
                              size: 13, color: AppColors.textSecondary),
                        ),
                      ),
                      const SizedBox(height: 24),
                      Semantics(
                        button: true,
                        child: InkWell(
                          onTap: _showTerms,
                          borderRadius: BorderRadius.circular(20),
                          child: AppCard(
                            padding: const EdgeInsets.all(18),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                _termSection(
                                  icon: Icons.description_outlined,
                                  title: 'ข้อกำหนดและเงื่อนไขการใช้งาน',
                                  body:
                                      'กดเพื่ออ่านข้อกำหนดและเงื่อนไขการใช้งาน',
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 18),
                      GestureDetector(
                        onTap: () =>
                            setState(() => _agreedChecked = !_agreedChecked),
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
                                gradient: _agreedChecked
                                    ? AppColors.purpleGradient
                                    : null,
                                color: _agreedChecked
                                    ? null
                                    : Colors.white.withValues(alpha: .03),
                                border: Border.all(
                                  color: _agreedChecked
                                      ? Colors.transparent
                                      : AppColors.border,
                                ),
                              ),
                              child: _agreedChecked
                                  ? const Icon(Icons.check,
                                      size: 16, color: Colors.white)
                                  : null,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                'ฉันได้อ่านและยอมรับข้อกำหนดและเงื่อนไขการใช้งาน',
                                style: AppText.body(
                                    size: 13, color: AppColors.textSecondary),
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
                      label: _loading
                          ? 'กำลังดำเนินการ...'
                          : 'ยินยอมและดำเนินการต่อ',
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

  Widget _termSection(
      {required IconData icon, required String title, required String body}) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 34,
          height: 34,
          margin: const EdgeInsets.only(top: 2),
          decoration: BoxDecoration(
            color: AppColors.purple1.withValues(alpha: .15),
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
              Text(body,
                  style:
                      AppText.body(size: 12.5, color: AppColors.textSecondary)),
            ],
          ),
        ),
      ],
    );
  }
}

class _TermsDocumentDialog extends StatefulWidget {
  const _TermsDocumentDialog();
  @override
  State<_TermsDocumentDialog> createState() => _TermsDocumentDialogState();
}

class _TermsDocumentDialogState extends State<_TermsDocumentDialog> {
  final _scroll = ScrollController();
  late Future<String> _document = _load();
  Future<String> _load() =>
      rootBundle.loadString('assets/terms/terms_1.0.0.1.md', cache: false);

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Dialog(
        backgroundColor: AppColors.bg2,
        insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
        child: SizedBox(
          width: 640,
          height: MediaQuery.sizeOf(context).height * .78,
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('ข้อกำหนดและเงื่อนไข', style: AppText.heading(size: 18)),
                const SizedBox(height: 16),
                Expanded(
                  child: FutureBuilder<String>(
                    future: _document,
                    builder: (context, snapshot) {
                      if (snapshot.hasError) {
                        return Center(
                            child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Text('โหลดข้อกำหนดไม่สำเร็จ'),
                            TextButton(
                              onPressed: () => setState(() {
                                _document = _load();
                              }),
                              child: const Text('ลองใหม่'),
                            ),
                          ],
                        ));
                      }
                      if (!snapshot.hasData) {
                        return const Center(child: CircularProgressIndicator());
                      }
                      final paragraphs =
                          snapshot.data!.trim().split(RegExp(r'\r?\n\s*\r?\n'));
                      return Scrollbar(
                        controller: _scroll,
                        thumbVisibility: true,
                        child: ListView.builder(
                          key: const Key('terms-document-scroll'),
                          controller: _scroll,
                          padding: const EdgeInsets.only(right: 12),
                          itemCount: paragraphs.length,
                          itemBuilder: (_, index) {
                            final paragraph = paragraphs[index].trim();
                            final title = paragraph.startsWith('# ');
                            final heading = paragraph.startsWith('**') &&
                                paragraph.endsWith('**');
                            final text = title
                                ? paragraph.substring(2)
                                : heading
                                    ? paragraph.substring(
                                        2, paragraph.length - 2)
                                    : paragraph;
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 16),
                              child: SelectableText(
                                text,
                                style: title || heading
                                    ? AppText.heading(size: title ? 18 : 15)
                                    : AppText.body(
                                            size: 13,
                                            color: AppColors.textSecondary)
                                        .copyWith(height: 1.65),
                              ),
                            );
                          },
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 12),
                TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('ปิด')),
              ],
            ),
          ),
        ),
      );
}
