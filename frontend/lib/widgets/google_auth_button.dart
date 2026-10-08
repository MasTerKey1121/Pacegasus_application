import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/auth_provider.dart';
import '../screens/auth/auth_destination.dart';
import '../services/api_client.dart';
import 'common.dart';

class GoogleAuthButton extends ConsumerStatefulWidget {
  final String label;
  final bool enabled;
  final ValueChanged<bool> onLoadingChanged;

  const GoogleAuthButton({
    super.key,
    required this.label,
    required this.onLoadingChanged,
    this.enabled = true,
  });

  @override
  ConsumerState<GoogleAuthButton> createState() => _GoogleAuthButtonState();
}

class _GoogleAuthButtonState extends ConsumerState<GoogleAuthButton> {
  bool _loading = false;

  Future<void> _signIn() async {
    if (_loading || !widget.enabled) return;
    setState(() => _loading = true);
    widget.onLoadingChanged(true);
    try {
      final signedIn = await ref.read(authProvider.notifier).signInWithGoogle();
      if (!mounted || !signedIn) return;
      final user = ref.read(authProvider).user!;
      final destination = authenticatedDestination(context, user);
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => destination),
        (route) => false,
      );
    } on ApiException catch (error) {
      if (mounted) showAppToast(context, error.message);
    } catch (_) {
      if (mounted) {
        showAppToast(
            context, 'เชื่อมต่อเซิร์ฟเวอร์ไม่ได้ กรุณาลองใหม่อีกครั้ง');
      }
    } finally {
      if (mounted) {
        setState(() => _loading = false);
        widget.onLoadingChanged(false);
      }
    }
  }

  @override
  Widget build(BuildContext context) => OutlineButton(
        label: _loading ? 'กำลังเข้าสู่ระบบด้วย Google...' : widget.label,
        onTap: widget.enabled && !_loading ? _signIn : null,
      );
}
