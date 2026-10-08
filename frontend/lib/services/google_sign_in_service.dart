import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'api_client.dart';

class GoogleSignInService {
  Future<void>? _initialization;

  Future<void> _initialize() async {
    final clientId = dotenv.isInitialized
        ? dotenv.env['GOOGLE_CLIENT_ID']?.trim() ?? ''
        : '';
    if (clientId.isEmpty) {
      throw ApiException(0, 'ยังไม่ได้ตั้งค่า Google login กรุณาติดต่อผู้ดูแล');
    }
    try {
      await (_initialization ??= GoogleSignIn.instance.initialize(
        serverClientId: clientId,
        clientId: dotenv.env['GOOGLE_IOS_CLIENT_ID'],
      ));
    } catch (_) {
      _initialization = null;
      rethrow;
    }
  }

  /// A canceled account picker leaves the current app session unchanged.
  Future<String?> signIn() async {
    // Check before initialize(): the plugin has no Windows/Linux implementation.
    if (kIsWeb ||
        (defaultTargetPlatform != TargetPlatform.android &&
            defaultTargetPlatform != TargetPlatform.iOS &&
            defaultTargetPlatform != TargetPlatform.macOS)) {
      throw ApiException(0,
          'Google login ในแอปนี้รองรับ Android และ iOS กรุณาทดสอบบนมือถือหรือ Android emulator');
    }
    try {
      await _initialize();
      if (!GoogleSignIn.instance.supportsAuthenticate()) {
        throw ApiException(0, 'Google login ยังไม่รองรับบนอุปกรณ์นี้');
      }
      final account = await GoogleSignIn.instance.authenticate();
      final idToken = account.authentication.idToken;
      if (idToken == null || idToken.isEmpty) {
        throw ApiException(
            0, 'ไม่ได้รับข้อมูลยืนยันตัวตนจาก Google กรุณาลองใหม่');
      }
      return idToken;
    } on GoogleSignInException catch (error) {
      if (error.code == GoogleSignInExceptionCode.canceled) return null;
      if (error.code == GoogleSignInExceptionCode.clientConfigurationError) {
        throw ApiException(
            0, 'ตั้งค่า Google login ไม่ถูกต้อง กรุณาติดต่อผู้ดูแล');
      }
      throw ApiException(0, 'เข้าสู่ระบบด้วย Google ไม่สำเร็จ กรุณาลองใหม่');
    } on MissingPluginException {
      throw ApiException(
          0, 'ยังไม่ได้โหลดส่วน Google login กรุณาปิดแอปแล้วรันใหม่ทั้งแอป');
    } on PlatformException catch (error) {
      debugPrint('Google sign-in platform error: ${error.code}');
      throw ApiException(0,
          'เปิด Google login ไม่สำเร็จ (${error.code}) กรุณาปิดแอปแล้วรันใหม่');
    }
  }
}
