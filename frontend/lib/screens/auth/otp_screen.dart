import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../app_theme.dart';
import '../../widgets/common.dart';
import '../../providers/auth_provider.dart';
import '../../services/api_client.dart';

class OtpScreen extends ConsumerStatefulWidget {
  final String email;
  final String otpRef;
  final String purpose; // 'login' | 'register'
  final String? displayName; // ใช้ตอน purpose == 'register'
  final int otpLength;
  final int expiresInMinutes;
  final int maxAttempts;
  final int resendCooldownSeconds;

  /// เรียกเมื่อ verify สำเร็จ — login ไป Home, register ไป Onboarding
  final VoidCallback? onVerified;

  const OtpScreen({
    super.key,
    required this.email,
    required this.otpRef,
    required this.purpose,
    this.displayName,
    this.otpLength = 6,
    this.expiresInMinutes = 5,
    this.maxAttempts = 5,
    this.resendCooldownSeconds = 60,
    this.onVerified,
  });

  @override
  ConsumerState<OtpScreen> createState() => _OtpScreenState();
}

class _OtpScreenState extends ConsumerState<OtpScreen> {
  late final List<TextEditingController> _controllers;
  late final List<FocusNode> _focusNodes;

  late String _otpRef;
  late int _secondsToExpiry;
  late int _resendCooldown;
  Timer? _ticker;

  int _attemptsLeft = 0;
  String? _errorText;
  bool _verifying = false;
  bool _resending = false;

  @override
  void initState() {
    super.initState();
    _otpRef = widget.otpRef;
    _controllers = List.generate(widget.otpLength, (_) => TextEditingController());
    _focusNodes = List.generate(widget.otpLength, (_) => FocusNode());
    _attemptsLeft = widget.maxAttempts;
    _secondsToExpiry = widget.expiresInMinutes * 60;
    _resendCooldown = widget.resendCooldownSeconds;
    _startTicker();
  }

  void _startTicker() {
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      setState(() {
        if (_secondsToExpiry > 0) _secondsToExpiry--;
        if (_resendCooldown > 0) _resendCooldown--;
      });
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    for (final c in _controllers) {
      c.dispose();
    }
    for (final f in _focusNodes) {
      f.dispose();
    }
    super.dispose();
  }

  String get _code => _controllers.map((c) => c.text).join();
  bool get _isComplete => _code.length == widget.otpLength;
  bool get _isExpired => _secondsToExpiry <= 0;

  String _formatTime(int totalSeconds) {
    final m = (totalSeconds ~/ 60).toString().padLeft(2, '0');
    final s = (totalSeconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  void _onDigitChanged(int index, String value) {
    if (value.isNotEmpty && index < widget.otpLength - 1) {
      _focusNodes[index + 1].requestFocus();
    }
    if (value.isEmpty && index > 0) {
      _focusNodes[index - 1].requestFocus();
    }
    setState(() => _errorText = null);
    if (_isComplete) {
      FocusScope.of(context).unfocus();
      _verify();
    }
  }

  Future<void> _verify() async {
    if (_isExpired) {
      setState(() => _errorText = 'รหัสหมดอายุแล้ว กด "ส่งรหัสอีกครั้ง" เพื่อขอรหัสใหม่');
      return;
    }
    if (!_isComplete || _verifying) return;

    setState(() => _verifying = true);

    try {
      final authApi = ref.read(authApiProvider);
      final res = await authApi.verifyOtp(
        email: widget.email,
        otp: _code,
        otpRef: _otpRef,
        displayName: widget.purpose == 'register' ? widget.displayName : null,
      );
      final data = res['data'] as Map<String, dynamic>;

      await ref.read(authProvider.notifier).completeLogin(data);

      if (!mounted) return;
      widget.onVerified?.call();
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _verifying = false;
        _attemptsLeft = (_attemptsLeft - 1).clamp(0, widget.maxAttempts);
        for (final c in _controllers) {
          c.clear();
        }
        _focusNodes.first.requestFocus();
        _errorText = e.statusCode == 400 || e.statusCode == 401
            ? (_attemptsLeft > 0
                ? 'รหัส OTP ไม่ถูกต้อง เหลืออีก $_attemptsLeft ครั้ง'
                : 'กรอกผิดครบจำนวนครั้งแล้ว กรุณาขอรหัสใหม่')
            : e.message;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _verifying = false;
        _errorText = 'เชื่อมต่อเซิร์ฟเวอร์ไม่ได้ ลองใหม่อีกครั้ง';
      });
    }
  }

  Future<void> _resend() async {
    if (_resendCooldown > 0 || _resending) return;
    setState(() => _resending = true);
    try {
      final authApi = ref.read(authApiProvider);
      final res = await authApi.requestOtp(email: widget.email, purpose: widget.purpose);
      final newOtpRef = res['data']['otpRef'] as String;

      if (!mounted) return;
      setState(() {
        _otpRef = newOtpRef;
        for (final c in _controllers) {
          c.clear();
        }
        _errorText = null;
        _attemptsLeft = widget.maxAttempts;
        _secondsToExpiry = widget.expiresInMinutes * 60;
        _resendCooldown = widget.resendCooldownSeconds;
      });
      _focusNodes.first.requestFocus();
      if (!mounted) return;
      showAppToast(context, 'ส่งรหัส OTP ใหม่ไปที่ ${widget.email} แล้ว', isError: false);
    } on ApiException catch (e) {
      if (!mounted) return;
      showAppToast(context, e.message);
    } catch (_) {
      if (!mounted) return;
      showAppToast(context, 'ส่งรหัสใหม่ไม่สำเร็จ ลองอีกครั้ง');
    } finally {
      if (mounted) setState(() => _resending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final blocked = _attemptsLeft <= 0 || _isExpired;

    return Scaffold(
      body: AppBackground(
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 40, 24, 24),
            child: Column(
              children: [
                Row(children: [
                  RoundIconButton(icon: Icons.arrow_back, onTap: () => Navigator.of(context).pop()),
                ]),
                const SizedBox(height: 20),
                const PacegasusLogo(size: 56),
                const SizedBox(height: 20),
                Text('ยืนยันรหัส OTP', style: AppText.heading(size: 22)),
                const SizedBox(height: 8),
                Text(
                  'เราส่งรหัส ${widget.otpLength} หลักไปที่',
                  textAlign: TextAlign.center,
                  style: AppText.body(size: 13, color: AppColors.textSecondary),
                ),
                const SizedBox(height: 2),
                Text(widget.email, style: AppText.heading(size: 14.5, color: AppColors.gold1)),
                const SizedBox(height: 32),
                Text('Ref: $_otpRef', style: AppText.body(size: 12, color: AppColors.textTertiary)),
                const SizedBox(height: 32),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(widget.otpLength, (i) {
                    final filled = _controllers[i].text.isNotEmpty;
                    return Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 5),
                      child: SizedBox(
                        width: 44,
                        height: 54,
                        child: TextField(
                          controller: _controllers[i],
                          focusNode: _focusNodes[i],
                          enabled: !blocked && !_verifying,
                          textAlign: TextAlign.center,
                          keyboardType: TextInputType.number,
                          maxLength: 1,
                          style: AppText.heading(size: 20),
                          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                          decoration: InputDecoration(
                            counterText: '',
                            filled: true,
                            fillColor: Colors.white.withOpacity(.03),
                            contentPadding: const EdgeInsets.symmetric(vertical: 14),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(14),
                              borderSide: BorderSide(color: AppColors.border),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(14),
                              borderSide: BorderSide(
                                color: _errorText != null
                                    ? AppColors.red1.withOpacity(.6)
                                    : (filled ? AppColors.purple2.withOpacity(.6) : AppColors.border),
                              ),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(14),
                              borderSide: BorderSide(color: AppColors.purple2, width: 1.6),
                            ),
                          ),
                          onChanged: (v) => _onDigitChanged(i, v),
                        ),
                      ),
                    );
                  }),
                ),
                const SizedBox(height: 16),
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 150),
                  child: _errorText != null
                      ? Padding(
                          key: const ValueKey('err'),
                          padding: const EdgeInsets.only(top: 2),
                          child: Text(
                            _errorText!,
                            textAlign: TextAlign.center,
                            style: AppText.body(size: 12.5, color: AppColors.red1, weight: FontWeight.w500),
                          ),
                        )
                      : const SizedBox(key: ValueKey('noerr'), height: 0),
                ),
                const SizedBox(height: 18),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: AppColors.card,
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.timer_outlined,
                          size: 15, color: _isExpired ? AppColors.red1 : AppColors.textSecondary),
                      const SizedBox(width: 6),
                      Text(
                        _isExpired ? 'รหัสหมดอายุแล้ว' : 'รหัสหมดอายุใน ${_formatTime(_secondsToExpiry)}',
                        style: AppText.body(
                          size: 12.5,
                          weight: FontWeight.w600,
                          color: _isExpired ? AppColors.red1 : AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 26),
                GradientButton(
                  label: _verifying ? 'กำลังตรวจสอบ...' : 'ยืนยันรหัส OTP',
                  onTap: (_isComplete && !blocked && !_verifying) ? _verify : null,
                ),
                const SizedBox(height: 22),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text('ไม่ได้รับรหัส? ', style: AppText.body(size: 13, color: AppColors.textSecondary)),
                    GestureDetector(
                      onTap: _resendCooldown == 0 && !_resending ? _resend : null,
                      child: Text(
                        _resending
                            ? 'กำลังส่ง...'
                            : (_resendCooldown > 0 ? 'ส่งใหม่ได้ใน ${_resendCooldown}s' : 'ส่งรหัสอีกครั้ง'),
                        style: AppText.body(
                          size: 13,
                          weight: FontWeight.w600,
                          color: _resendCooldown > 0 ? AppColors.textTertiary : AppColors.purple2,
                        ),
                      ),
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