import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
// ignore: implementation_imports
import 'package:google_fonts/src/google_fonts_base.dart' as fonts;
import 'package:pacegasus/providers/auth_provider.dart';
import 'package:pacegasus/main.dart';
import 'package:pacegasus/providers/onboarding_provider.dart';
import 'package:pacegasus/providers/program_provider.dart';
import 'package:pacegasus/providers/wellness_provider.dart';
import 'package:pacegasus/screens/auth/login_screen.dart';
import 'package:pacegasus/screens/auth/terms_screen.dart';
import 'package:pacegasus/screens/auth/otp_screen.dart';
import 'package:pacegasus/screens/home/main_shell.dart';
import 'package:pacegasus/screens/onboarding/onboarding_basic_screen.dart';
import 'package:pacegasus/screens/onboarding/onboarding_injury_screen.dart';
import 'package:pacegasus/screens/onboarding/onboarding_goal_screen.dart';
import 'package:pacegasus/screens/onboarding/onboarding_history_screen.dart';
import 'package:pacegasus/services/api_client.dart';
import 'package:pacegasus/services/auth_api.dart';
import 'package:pacegasus/services/google_sign_in_service.dart';
import 'package:pacegasus/services/onboarding_api.dart';
import 'package:pacegasus/services/program_api.dart';
import 'package:pacegasus/services/wellness_api.dart';

class _Fonts extends Fake implements AssetManifest {
  @override
  List<String> listAssets() => [
        for (final family in ['Kanit', 'Sarabun'])
          for (final weight in ['Regular', 'Medium', 'SemiBold', 'Bold'])
            'test-fonts/$family-$weight.ttf',
      ];
}

class _Google extends GoogleSignInService {
  @override
  Future<String?> signIn() async => 'verified-google-token';
}

class _Api extends AuthApi {
  _Api({required bool existing})
      : super(ApiClient(baseUrl: 'http://localhost')) {
    user = {
      'id': 'user-1',
      'email': 'runner@example.com',
      'displayName': 'Runner',
      'policyAccepted': existing,
      'onboardingCompleted': existing
    };
  }
  late Map<String, dynamic> user;
  int googleCalls = 0, policyCalls = 0, otpCalls = 0, logoutCalls = 0;
  final onboardingSteps = <int>[];
  @override
  Future<Map<String, dynamic>> google({required String idToken}) async {
    expect(idToken, 'verified-google-token');
    googleCalls++;
    return {
      'data': {
        'user': Map<String, dynamic>.from(user),
        'accessToken': 'access',
        'refreshToken': 'refresh'
      }
    };
  }

  @override
  Future<Map<String, dynamic>> acceptPolicy(
      {required String policyVersion}) async {
    expect(policyVersion, '2026-07');
    policyCalls++;
    user = {...user, 'policyAccepted': true};
    return {
      'data': {'user': user}
    };
  }

  @override
  Future<Map<String, dynamic>> requestOtp(
      {required String email,
      required String purpose,
      bool? policyAccepted,
      String? policyVersion}) async {
    otpCalls++;
    throw StateError('Google authentication must never request OTP');
  }

  @override
  Future<void> logout({required String refreshToken}) async {
    logoutCalls++;
  }
}

// Home's data restoration is independent of authentication routing.
class _Onboarding extends OnboardingApi {
  _Onboarding(this.auth) : super(ApiClient());
  final _Api auth;
  Future<Map<String, dynamic>> save(int step) async {
    auth.onboardingSteps.add(step);
    return {
      'data': {
        'step': step,
        if (step == 4) ...{
          'runningExperienceLevel': 'beginner',
          'onboardingCompleted': true,
        }
      }
    };
  }

  @override
  Future<Map<String, dynamic>> step1(Map<String, dynamic> body) => save(1);
  @override
  Future<Map<String, dynamic>> step2(Map<String, dynamic> body) => save(2);
  @override
  Future<Map<String, dynamic>> step3(Map<String, dynamic> body) => save(3);
  @override
  Future<Map<String, dynamic>> step4(Map<String, dynamic> body) => save(4);
}

class _Program extends ProgramNotifier {
  _Program() : super(ProgramApi(ApiClient()), OnboardingApi(ApiClient()));
  @override
  Future<void> restore({bool force = false}) async {}
}

class _Wellness extends WellnessNotifier {
  _Wellness() : super(WellnessApi(ApiClient()));
  @override
  Future<bool> loadToday() async => false;
}

void main() {
  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    GoogleFonts.config.allowRuntimeFetching = false;
    fonts.assetManifest = _Fonts();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMessageHandler('flutter/assets', (message) async {
      if (message == null) return null;
      final asset = utf8.decode(message.buffer.asUint8List());
      if (asset.startsWith('test-fonts/')) return ByteData(0);
      if (asset == 'AssetManifest.bin') {
        return const StandardMessageCodec().encodeMessage(<String, Object>{});
      }
      if (asset.startsWith('assets/images/')) {
        return ByteData.sublistView(await File(asset).readAsBytes());
      }
      return null;
    });
  });

  Future<void> open(WidgetTester tester, _Api api,
      {bool register = false}) async {
    tester.view.physicalSize = const Size(500, 1100);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(ProviderScope(
        overrides: [
          authApiProvider.overrideWithValue(api),
          onboardingApiProvider.overrideWithValue(_Onboarding(api)),
          googleSignInServiceProvider.overrideWithValue(_Google()),
          programProvider.overrideWith((ref) => _Program()),
          wellnessProvider.overrideWith((ref) => _Wellness()),
        ],
        child: const MaterialApp(home: AuthGate())));
    await tester.pumpAndSettle();
    if (register) {
      await tester.tap(find.text('สมัครสมาชิก'));
      await tester.pumpAndSettle();
    }
    await tester.tap(find
        .text(register ? 'สมัครสมาชิกด้วย Google' : 'เข้าสู่ระบบด้วย Google'));
    await tester.pumpAndSettle();
  }

  for (final register in [false, true]) {
    final button = register ? 'register' : 'login';
    testWidgets(
        '$button Google button opens Home for a completed existing account without OTP',
        (tester) async {
      final api = _Api(existing: true);
      await open(tester, api, register: register);
      expect(find.byType(MainShell), findsOneWidget);
      expect(find.byType(TermsConsentScreen), findsNothing);
      expect(find.byType(OtpScreen), findsNothing);
      expect(api.googleCalls, 1);
      expect(api.otpCalls, 0);
      expect(api.policyCalls, 0);
      expect(tester.takeException(), isNull);
    });

    testWidgets(
        '$button Google button requires terms then onboarding for a new account without OTP',
        (tester) async {
      final api = _Api(existing: false);
      await open(tester, api, register: register);
      expect(find.byType(TermsConsentScreen), findsOneWidget);
      expect(find.byType(OtpScreen), findsNothing);
      await tester.tap(find.text('ยินยอมและดำเนินการต่อ'));
      await tester.pumpAndSettle();
      expect(api.policyCalls, 0);
      final consent = find.text(
          'ฉันได้อ่านและยินยอมตามข้อตกลงการใช้บริการและนโยบายความเป็นส่วนตัวข้างต้น');
      await tester.ensureVisible(consent);
      await tester.tap(consent);
      await tester.pumpAndSettle();
      await tester.tap(find.text('ยินยอมและดำเนินการต่อ'));
      await tester.pumpAndSettle();
      expect(api.policyCalls, 1);
      expect(api.otpCalls, 0);
      expect(find.byType(OnboardingBasicScreen), findsOneWidget);
      expect(find.byType(OtpScreen), findsNothing);
      expect(find.byType(MainShell), findsNothing);
      final container = ProviderScope.containerOf(
        tester.element(find.byType(OnboardingBasicScreen)),
      );
      expect(container.read(authProvider).user!['policyAccepted'], isTrue);
      // Supply valid registration details, then exercise all four real screens.
      container.read(onboardingProvider).update((data) {
        data.day = '1';
        data.month = '1';
        data.year = '2000';
        data.gender = 'ชาย';
        data.weightKg = '65';
        data.heightCm = '175';
        data.runningDaysPerWeek = '3';
        data.hasChronicCondition = false;
        data.hasPastInjuries = false;
        data.hasCurrentInjuries = false;
        data.healthGoal = 'เพิ่มความอึด';
        data.hasRunningExperience = false;
        data.longestDistance = 'น้อยกว่า 5 km';
      });
      await tester.pumpAndSettle();
      await tester.tap(find.text('ต่อไป'));
      await tester.pumpAndSettle();
      expect(find.byType(OnboardingInjuryScreen), findsOneWidget);
      await tester.tap(find.text('ถัดไป'));
      await tester.pumpAndSettle();
      expect(find.byType(OnboardingGoalScreen), findsOneWidget);
      await tester.tap(find.text('ถัดไป'));
      await tester.pumpAndSettle();
      expect(find.byType(OnboardingHistoryScreen), findsOneWidget);
      await tester.tap(find.text('เริ่มใช้งาน ✓'));
      await tester.pumpAndSettle();
      expect(api.onboardingSteps, [1, 2, 3, 4]);
      expect(find.byType(MainShell), findsOneWidget);
      expect(find.byType(OtpScreen), findsNothing);
      expect(api.otpCalls, 0);
      expect(container.read(authProvider).user!['onboardingCompleted'], isTrue);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
      'declining Google registration terms clears the session and returns to login',
      (tester) async {
    final api = _Api(existing: false);
    await open(tester, api);
    await tester.tap(find.text('ไม่ยินยอม'));
    await tester.pumpAndSettle();
    expect(find.byType(LoginScreen), findsOneWidget);
    expect(api.logoutCalls, 1);
    expect(api.otpCalls, 0);
    expect(
        await const FlutterSecureStorage().read(key: 'refresh_token'), isNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'returning unfinished Google account continues onboarding without OTP',
      (tester) async {
    final api = _Api(existing: true)..user['onboardingCompleted'] = false;
    await open(tester, api);
    expect(find.byType(OnboardingBasicScreen), findsOneWidget);
    expect(find.byType(TermsConsentScreen), findsNothing);
    expect(api.otpCalls, 0);
    expect(tester.takeException(), isNull);
  });
}
