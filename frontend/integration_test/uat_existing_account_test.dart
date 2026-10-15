import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:pacegasus/main.dart' as app;
import 'package:pacegasus/config/api_config.dart';
import 'package:pacegasus/providers/auth_provider.dart';
import 'package:pacegasus/providers/onboarding_provider.dart';
import 'package:pacegasus/providers/wellness_provider.dart';
import 'package:pacegasus/screens/auth/login_screen.dart';

import 'package:pacegasus/screens/auth/otp_screen.dart';
import 'package:pacegasus/screens/onboarding/onboarding_basic_screen.dart';
import 'package:pacegasus/screens/onboarding/onboarding_injury_screen.dart';
import 'package:pacegasus/screens/onboarding/onboarding_goal_screen.dart';
import 'package:pacegasus/screens/onboarding/onboarding_history_screen.dart';
import 'package:pacegasus/screens/home/home_screen.dart';
import 'package:pacegasus/screens/profile/profile_screen.dart';
import 'package:pacegasus/screens/wellness/daily_wellness_screen.dart';
import 'package:pacegasus/widgets/common.dart';

const _email = String.fromEnvironment('UAT_EMAIL',
    defaultValue: 'fortest.najajubjub@gmail.com');
const _name = String.fromEnvironment('UAT_NAME', defaultValue: 'test account');
const _manualOtp = bool.fromEnvironment('UAT_MANUAL_OTP', defaultValue: true);
const _bridge = String.fromEnvironment('UAT_BRIDGE_URL',
    defaultValue: 'http://127.0.0.1:8765');

Future<Map<String, dynamic>> _request(String route,
    [Map<String, dynamic>? body]) async {
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 5);
  try {
    final request = await client.openUrl(
        body == null ? 'GET' : 'POST', Uri.parse('$_bridge$route'));
    if (body != null) {
      request.headers.contentType = ContentType.json;
      request.write(jsonEncode(body));
    }
    final response = await request.close().timeout(const Duration(seconds: 15));
    final data = await utf8.decoder.bind(response).join();
    if (response.statusCode != 200) {
      throw StateError('UAT bridge failed: $data');
    }
    return jsonDecode(data) as Map<String, dynamic>;
  } finally {
    client.close(force: true);
  }
}

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.shouldPropagateDevicePointerEvents = _manualOtp;
  testWidgets(
      'existing account, health-only onboarding and screenshot evidence',
      (tester) async {
    var step = 'startup';
    Future<void> waitFor(bool Function() ready, String description,
        {int seconds = 45}) async {
      final end = DateTime.now().add(Duration(seconds: seconds));
      while (!ready()) {
        // Catch transient error toasts before they disappear, rather than
        // reporting only a generic navigation timeout several seconds later.
        final toast = find.descendant(
          of: find.byWidgetPredicate((w) =>
              w is Positioned &&
              w.left == 24 &&
              w.right == 24 &&
              w.bottom == 110),
          matching: find.byType(Text),
        );
        if (toast.evaluate().isNotEmpty) {
          final message = tester.widget<Text>(toast.first).data;
          throw TestFailure('$description: app reported "$message"');
        }
        if (DateTime.now().isAfter(end)) {
          throw TestFailure('Timed out: $description');
        }
        await tester.pump(const Duration(milliseconds: 250));
      }
      await tester.pump(const Duration(milliseconds: 500));
      expect(tester.takeException(), isNull, reason: description);
    }

    Future<void> page(Type type) => waitFor(
        () => find.byType(type).evaluate().isNotEmpty, '$type must open');
    Future<void> tap(Finder finder) async {
      expect(finder, findsOneWidget);
      await tester.ensureVisible(finder);
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(finder);
      await tester.pump(const Duration(milliseconds: 500));
    }

    Future<void> enter(Finder finder, String value) async {
      expect(finder, findsOneWidget);
      await tester.ensureVisible(finder);
      await tester.enterText(finder, value);
      await tester.pump(const Duration(milliseconds: 200));
    }

    Future<void> capture(String id, String description,
        {bool failed = false}) async {
      if (!failed) expect(tester.takeException(), isNull, reason: description);
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pump(const Duration(milliseconds: 600));
      if (find.byType(HomeScreen).evaluate().isNotEmpty) {
        await tester.pump(const Duration(seconds: 3));
      }
      final bytes = await binding.takeScreenshot(id);
      await _request('/checkpoint', {
        'name': id,
        'description': description,
        'status': failed ? 'failed' : 'passed',
        'png': base64Encode(bytes)
      });
    }

    Finder field(String label) => find.descendant(
        of: find
            .byWidgetPredicate((w) => w is AppTextField && w.label == label),
        matching: find.byType(TextField));
    Future<void> noLoading() => waitFor(
        () =>
            find.byType(CircularProgressIndicator).evaluate().isEmpty &&
            find
                .byWidgetPredicate(
                    (w) => w is LinearProgressIndicator && w.value == null)
                .evaluate()
                .isEmpty,
        'page finishes loading');
    try {
      await _request('/state', {
        'state': 'running',
        'detail': 'Starting existing-account UAT against ${ApiConfig.baseUrl}'
      });
      app.main();
      await waitFor(
          () =>
              find.byType(LoginScreen).evaluate().isNotEmpty ||
              find.byType(OnboardingBasicScreen).evaluate().isNotEmpty ||
              find.byType(HomeScreen).evaluate().isNotEmpty,
          'Existing account startup must show Login, onboarding or Home');
      await binding.convertFlutterSurfaceToImage();
      await tester.pump();
      if (find.byType(LoginScreen).evaluate().isNotEmpty) {
        step = 'login-existing';
        await enter(field('Email'), _email);
        expect(
            tester.widget<TextField>(field('Email')).controller!.text, _email);
        await capture(
            '01-existing-login', 'Existing account email entered on Login');
        await tap(find.widgetWithText(GradientButton, 'เข้าสู่ระบบ'));
        await page(OtpScreen);
        expect(
            tester.widget<OtpScreen>(find.byType(OtpScreen)).purpose, 'login');
        expect(find.text(_email), findsOneWidget);
        await capture(
            '02-login-otp', 'Login OTP requested for existing account');
        await _request('/state', {
          'state': 'waiting_otp',
          'detail': _manualOtp
              ? 'กรอก OTP เองในแอป'
              : 'Waiting for existing-account login OTP in .uat-runtime/otp.txt'
        });
        step = 'verify-login-otp';
        if (_manualOtp) {
          await waitFor(
              () =>
                  find.byType(OnboardingBasicScreen).evaluate().isNotEmpty ||
                  find.byType(HomeScreen).evaluate().isNotEmpty,
              'Waiting for manual OTP verification',
              seconds: 600);
        } else {
          String? code;
          final otpDeadline = DateTime.now().add(const Duration(minutes: 4));
          while (code == null) {
            if (DateTime.now().isAfter(otpDeadline)) {
              throw TestFailure('Login OTP not supplied within four minutes');
            }
            code = (await _request('/otp'))['code'] as String?;
            await tester.pump(const Duration(seconds: 1));
          }
          expect(code, matches(RegExp(r'^\d{6}$')));
          for (var i = 0; i < code.length; i++) {
            await tester.enterText(find.byType(TextField).at(i), code[i]);
            await tester.pump(const Duration(milliseconds: 100));
          }
          code = null;
        }
        await waitFor(
            () =>
                find.byType(OnboardingBasicScreen).evaluate().isNotEmpty ||
                find.byType(HomeScreen).evaluate().isNotEmpty,
            'Login routes existing account according to onboarding completion');
      }
      final account = ProviderScope.containerOf(
              tester.element(find.byType(app.PacegasusApp)))
          .read(authProvider);
      expect(account.status, AuthStatus.authenticated);
      expect(account.user?['email'], _email);
      expect(account.user?['displayName'], _name);
      await _request('/state', {
        'state': 'running',
        'detail':
            'Existing account authenticated; using health-only goal for incomplete onboarding'
      });
      await capture('03-existing-authenticated',
          'Existing account restored or authenticated with correct email and name');
      if (account.user?['onboardingCompleted'] != true) {
        await page(OnboardingBasicScreen);
        step = 'onboarding-basic';
        for (final entry in {'DD': '01', 'MM': '01', 'YYYY': '1995'}.entries) {
          await enter(
              find.byWidgetPredicate(
                  (w) => w is TextField && w.decoration?.hintText == entry.key),
              entry.value);
        }
        await tap(find.text('ชาย'));
        await enter(field('น้ำหนัก (kg)'), '65');
        await enter(field('ส่วนสูง (cm)'), '170');
        await enter(field('จำนวนวันที่วิ่ง/สัปดาห์'), '3');
        final basicNext = find.widgetWithText(GradientButton, 'ต่อไป');
        expect(tester.widget<GradientButton>(basicNext).onTap, isNotNull);
        await capture('07-basic-valid',
            'Synthetic birth date, gender, weight, height and training days validate');
        await tap(basicNext);
        await page(OnboardingInjuryScreen);

        step = 'onboarding-health';
        for (var i = 0; i < 3; i++) {
          await tap(find.text('ไม่มี').at(i));
        }
        await capture('08-health',
            'Synthetic no-condition and no-injury answers selected');
        await tap(find.widgetWithText(GradientButton, 'ถัดไป'));
        await page(OnboardingGoalScreen);
        step = 'onboarding-goal';
        await tap(find.text('เพิ่มความอึด'));
        final selectedGoal = ProviderScope.containerOf(
                tester.element(find.byType(OnboardingGoalScreen)))
            .read(onboardingProvider)
            .data;
        expect(selectedGoal.healthGoal, 'เพิ่มความอึด');
        expect(selectedGoal.distanceGoal, isNull);
        await capture('09-goal',
            'Only increased-endurance health goal selected; no distance goal');
        await tap(find.widgetWithText(GradientButton, 'ถัดไป'));
        await page(OnboardingHistoryScreen);
        step = 'onboarding-history';
        await tap(find.widgetWithText(MultiChip, 'ไม่เคย'));
        await tap(find.widgetWithText(MultiChip, 'น้อยกว่า 5 km'));
        final historyData = ProviderScope.containerOf(
                tester.element(find.byType(OnboardingHistoryScreen)))
            .read(onboardingProvider)
            .data;
        expect(historyData.hasRunningExperience, isFalse);
        expect(historyData.longestDistance, 'น้อยกว่า 5 km');
        expect(
            tester
                .widget<GradientButton>(
                    find.widgetWithText(GradientButton, 'เริ่มใช้งาน ✓'))
                .onTap,
            isNotNull);
        await capture(
            '10-history', 'Synthetic beginner running history selected');
        await tap(find.widgetWithText(GradientButton, 'เริ่มใช้งาน ✓'));
        await page(HomeScreen);
      }
      await noLoading();
      final container =
          ProviderScope.containerOf(tester.element(find.byType(HomeScreen)));
      expect(container.read(authProvider).user?['onboardingCompleted'], isTrue);
      expect(find.text(_name), findsOneWidget);
      await capture(
          '11-home', 'Onboarding completes and Home shows test account');

      step = 'wellness';
      if (!container.read(wellnessProvider).completedToday) {
        expect(container.read(wellnessProvider).completedToday, isFalse,
            reason: 'Fresh account must have no check-in today');
        await tap(find.byKey(const Key('home-primary')));
        await page(DailyWellnessScreen);
        expect(tester.widget<GradientButton>(find.byType(GradientButton)).onTap,
            isNull);
        for (final label in [
          'คุณภาพการนอน',
          'ความเมื่อยล้ากล้ามเนื้อ',
          'ระดับพลังกล้ามเนื้อ',
          'ระดับความเครียด',
          'แรงจูงใจในการออกกำลังกาย'
        ]) {
          final slider = find.descendant(
              of: find.byWidgetPredicate(
                  (w) => w is LabeledSlider && w.label == label),
              matching: find.byType(Slider));
          await tester.ensureVisible(slider);
          await tester.pump(const Duration(milliseconds: 300));
          await tester.tapAt(tester.getCenter(slider));
          await tester.pump(const Duration(milliseconds: 200));
        }
        expect(tester.widget<GradientButton>(find.byType(GradientButton)).onTap,
            isNotNull);
        await capture(
            '12-wellness-valid', 'Five required wellness scores enable Save');
        await tap(find.widgetWithText(GradientButton, 'บันทึก'));
        await waitFor(() => find.byType(DailyWellnessScreen).evaluate().isEmpty,
            'wellness save returns Home');
        expect(container.read(wellnessProvider).completedToday, isTrue);
        await capture(
            '13-wellness-saved', 'Real API accepts wellness and Home updates');
      } else {
        await capture('13-wellness-restored',
            'Existing completed wellness restored without a duplicate submission');
      }
      step = 'profile';
      await tap(find.byKey(const Key('home-profile')));
      await page(ProfileScreen);
      await noLoading();
      expect(find.text(_name), findsWidgets);
      expect(find.text('UID: ยังไม่พร้อมใช้งาน'), findsNothing);
      expect(find.byTooltip('คัดลอก UID'), findsOneWidget);
      expect(find.text('ลองอีกครั้ง'), findsNothing);
      await capture('14-profile',
          'Profile loads test account and public UID without a retry error');
      await tester.pageBack();
      await page(HomeScreen);
      await _request('/state', {
        'state': 'passed',
        'detail':
            'Existing account login or session restore, applicable health-only onboarding, Home, wellness and Profile passed. Other features are not covered by this suite.'
      });
    } catch (error) {
      try {
        if (find.byType(OtpScreen).evaluate().isEmpty) {
          await capture('failed-$step', 'Failure at $step', failed: true);
        }
      } catch (_) {/* Preserve the original test failure. */}
      await _request(
          '/state', {'state': 'failed', 'detail': 'Failed at $step: $error'});
      rethrow;
    }
  }, timeout: const Timeout(Duration(minutes: 25)));
}
