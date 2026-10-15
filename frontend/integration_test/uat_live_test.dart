// Real-app guided UAT. Human actions use the app UI; assertions read the real
// authenticated API. No mocked providers, OTP interception or account deletion.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:pacegasus/main.dart' as app;
import 'package:pacegasus/config/api_config.dart';
import 'package:pacegasus/providers/auth_provider.dart';
import 'package:pacegasus/providers/program_provider.dart';
import 'package:pacegasus/screens/auth/otp_screen.dart';
import 'package:pacegasus/screens/home/home_screen.dart';
import 'package:pacegasus/screens/profile/profile_screen.dart';
import 'package:pacegasus/screens/stats/stats_screen.dart';
import 'package:pacegasus/screens/leaderboard/leaderboard_screen.dart';
import 'package:pacegasus/services/api_client.dart';
import 'package:pacegasus/services/stats_api.dart';
import 'package:pacegasus/screens/auth/login_screen.dart';
import 'package:pacegasus/screens/training/training_registration_screen.dart';
import 'package:pacegasus/screens/training/training_schedule_screen.dart';
import 'package:pacegasus/providers/training_plan_provider.dart';
import 'package:pacegasus/models/training_models.dart';
import 'package:pacegasus/widgets/common.dart';

const phase = String.fromEnvironment('UAT_PHASE', defaultValue: 'profile');
const email = String.fromEnvironment('UAT_EMAIL');
const manualOtp = bool.fromEnvironment('UAT_MANUAL_OTP', defaultValue: true);
const clubName =
    String.fromEnvironment('UAT_CLUB_NAME', defaultValue: 'Pacegasus UAT');
const listingId = String.fromEnvironment('UAT_SHOP_LISTING');
const bridgeUrl = String.fromEnvironment('UAT_BRIDGE_URL',
    defaultValue: 'http://127.0.0.1:8765');

Future<Map<String, dynamic>> bridge(String route,
    [Map<String, dynamic>? body]) async {
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 5);
  try {
    final req = await client.openUrl(
        body == null ? 'GET' : 'POST', Uri.parse('$bridgeUrl$route'));
    if (body != null) {
      req.headers.contentType = ContentType.json;
      req.write(jsonEncode(body));
    }
    final res = await req.close().timeout(const Duration(seconds: 15));
    final text = await utf8.decoder
        .bind(res)
        .join()
        .timeout(const Duration(seconds: 15));
    if (res.statusCode != 200) {
      throw StateError('Evidence bridge rejected request');
    }
    return jsonDecode(text) as Map<String, dynamic>;
  } finally {
    client.close(force: true);
  }
}

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  // Flutter tests otherwise discard touches from the physical device.
  binding.shouldPropagateDevicePointerEvents = true;
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;
  testWidgets('guided real-app UAT: $phase', (tester) async {
    late ProviderContainer container;
    late ApiClient api;
    var step = 'startup';
    Future<void> state(String detail, {String status = 'waiting_action'}) =>
        bridge('/state', {'state': status, 'detail': detail});
    Future<void> waitUntil(Future<bool> Function() ready, String description,
        {int seconds = 600}) async {
      final deadline = DateTime.now().add(Duration(seconds: seconds));
      while (!await ready()) {
        if (DateTime.now().isAfter(deadline)) {
          throw TestFailure('Timed out: $description');
        }
        await tester.pump(const Duration(seconds: 2));
        expect(tester.takeException(), isNull, reason: description);
      }
      await tester.pump(const Duration(milliseconds: 500));
    }

    Future<dynamic> read(String path) async =>
        (await api.get(path, auth: true))['data'];
    Future<void> remember(Map<String, String> values) async {
      await bridge(
          '/context', {'environment': ApiConfig.baseUrl, 'values': values});
    }

    Future<void> capture(String name, String description) async {
      expect(find.byType(OtpScreen), findsNothing,
          reason: 'Never capture OTP input');
      expect(tester.takeException(), isNull);
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pump(const Duration(milliseconds: 500));
      if (find.byType(HomeScreen).evaluate().isNotEmpty) {
        await tester.pump(const Duration(seconds: 3));
      }
      await bridge('/checkpoint', {
        'name': name,
        'description': description,
        'status': 'passed',
        'png': base64Encode(await binding.takeScreenshot(name))
      });
    }

    Future<void> onScreen(Type type, String instruction) async {
      await state(instruction);
      await waitUntil(
          () async => find.byType(type).evaluate().isNotEmpty, instruction);
    }

    Future<void> tap(Finder target) async {
      expect(target, findsOneWidget);
      await tester.ensureVisible(target);
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(target);
      await tester.pump(const Duration(milliseconds: 500));
      expect(tester.takeException(), isNull);
    }

    try {
      expect(email, isNotEmpty,
          reason: 'Select the expected account explicitly');
      await bridge('/scope', {
        'description':
            'Guided phase $phase. Human operates real UI (including OTP); automatic API/state assertions and screenshots. '
                'Only checkpoint assertions are checked. Negative cases and other parts of the 88-case plan remain Not Run. No account deletion.'
      });
      app.main();
      await waitUntil(
          () async => find.byType(app.PacegasusApp).evaluate().isNotEmpty,
          'App opens',
          seconds: 60);
      container = ProviderScope.containerOf(
          tester.element(find.byType(app.PacegasusApp)));
      await waitUntil(
          () async =>
              container.read(authProvider).status != AuthStatus.checking,
          'Saved session check finishes',
          seconds: 60);
      if (container.read(authProvider).status == AuthStatus.unauthenticated) {
        await waitUntil(
            () async => find.byType(LoginScreen).evaluate().isNotEmpty,
            'Login opens');
        final emailField = find.descendant(
            of: find.byWidgetPredicate(
                (w) => w is AppTextField && w.label == 'Email'),
            matching: find.byType(TextField));
        await tester.enterText(emailField, email);
        await tap(find.widgetWithText(GradientButton, 'เข้าสู่ระบบ'));
        await waitUntil(
            () async => find.byType(OtpScreen).evaluate().isNotEmpty,
            'Login OTP requested',
            seconds: 45);
        await state(
            'ส่ง OTP ล่าสุดของ $email ให้ผู้ช่วยกรอก รอรหัสรอบนี้เท่านั้น',
            status: 'waiting_otp');
        if (!manualOtp) {
          String? code;
          await waitUntil(() async {
            code = (await bridge('/otp'))['code'] as String?;
            return code != null;
          }, 'OTP supplied by user', seconds: 240);
          expect(code, matches(RegExp(r'^\d{6}$')));
          for (var i = 0; i < 6; i++) {
            await tester.enterText(find.byType(TextField).at(i), code![i]);
            await tester.pump(const Duration(milliseconds: 100));
          }
          code = null;
        }
      }
      await state(
          'ใช้บัญชี $email ถ้าเป็นบัญชีอื่นให้ออกจากระบบผ่านเมนู จากนั้นเข้า/สมัครและกรอก OTP เองในแอป');
      await waitUntil(() async {
        final auth = container.read(authProvider);
        return auth.status == AuthStatus.authenticated &&
            auth.user?['email']?.toString().toLowerCase() ==
                email.toLowerCase();
      }, 'Expected account authenticates');
      api = container.read(apiClientProvider);
      await state(
          'ถ้า Onboarding ยังไม่ครบ ให้กรอกข้อมูลทดสอบและจบทั้ง 4 ขั้นตอนจนถึงหน้าหลัก');
      await waitUntil(
          () async =>
              container.read(authProvider).user?['onboardingCompleted'] ==
                  true &&
              find.byType(HomeScreen).evaluate().isNotEmpty,
          'Onboarding complete and Home visible');
      final me = (await read('/api/auth/me'))['user'] as Map;
      expect(me['email']?.toString().toLowerCase(), email.toLowerCase());
      final uid = me['uid'] as String;
      expect(uid, matches(RegExp(r'^[23456789ABCDEFGHJKLMNPQRSTUVWXYZ]{10}$')));
      const secondary = phase == 'setup-secondary' ||
          phase == 'secondary-social' ||
          phase == 'verify-secondary';
      await remember({secondary ? 'secondaryUid' : 'primaryUid': uid});
      await binding.convertFlutterSurfaceToImage();
      await tester.pump();
      await capture('identity',
          'Expected account authenticated, onboarding complete, real public UID verified');
      final context = await bridge(
          '/context?environment=${Uri.encodeComponent(ApiConfig.baseUrl)}');

      switch (phase) {
        case 'setup-secondary':
          await capture('secondary-ready',
              'Secondary account UID saved for later two-account steps; no social request sent');
          break;
        case 'program':
          step = 'wellness-program';
          final today = await read('/api/wellness-checkin/today');
          expect(today['status'], 'done',
              reason: 'Run registration/wellness phase first');
          final before = container.read(programProvider);
          expect(before.isScheduleSaved, isFalse,
              reason:
                  'This scenario requires an unsaved week; never overwrite a saved schedule automatically');
          final hadProgram = before.isRegistered;
          await state('ทดสอบลงทะเบียน 5K และจัดตารางผ่านหน้าจออัตโนมัติ',
              status: 'running');
          await waitUntil(
              () async => !container.read(programProvider).isLoading,
              'Home program restoration finishes',
              seconds: 60);
          await tap(find.byKey(const Key('home-primary')));
          if (!hadProgram) {
            await waitUntil(
                () async => find
                    .byType(TrainingRegistrationScreen)
                    .evaluate()
                    .isNotEmpty,
                'Program registration screen opens');
            await waitUntil(
                () async =>
                    !container.read(programProvider).isLoadingTemplates &&
                    !container.read(programProvider).isLoading,
                'Program templates load',
                seconds: 60);
            await tap(find.widgetWithText(SelectChip, '5K'));
            expect(container.read(programProvider).selectedTemplateLevel,
                'beginner');
            await capture('program-preview',
                'Beginner 5K selected on registration screen');
            await tap(find.widgetWithText(
                GradientButton, 'บันทึกและลงทะเบียนตารางซ้อม'));
          }
          await waitUntil(
              () async =>
                  find.byType(TrainingScheduleScreen).evaluate().isNotEmpty &&
                  !container.read(programProvider).isLoadingTemplates,
              'Registered program opens schedule builder');
          await tester.pump(const Duration(seconds: 2));
          final plan = container.read(trainingPlanProvider);
          expect(plan.currentWeek, 0);
          expect(plan.currentWeekData.every((day) => day == null), isTrue,
              reason: 'Resumed unsaved program must have an empty week');
          expect(plan.getCaps(0).easy, 3);
          expect(plan.getCaps(0).long, 1);
          final save =
              find.widgetWithText(GradientButton, 'บันทึกตารางสัปดาห์');
          await tester.ensureVisible(save);
          expect(tester.widget<GradientButton>(save).onTap, isNull);
          await capture('schedule-incomplete',
              'New week cannot save before required workouts are placed');
          for (final day in [0, 2, 4]) {
            if (plan.selectedType != SessionType.easy) {
              await tap(find.byKey(const Key('training-workout-easy')));
            }
            await tap(find.byKey(Key('training-day-$day')));
            expect(plan.currentWeekData[day], SessionType.easy,
                reason: 'UI must place Easy Run on day $day before proceeding');
          }
          expect(
              plan.currentWeekData
                  .where((day) => day == SessionType.easy)
                  .length,
              3);
          expect(find.byKey(const Key('training-workout-easy')), findsNothing,
              reason: 'UI removes Easy Run choice once its quota is filled');
          expect(plan.selectedType, isNull);
          await tap(find.byKey(const Key('training-day-1')));
          expect(plan.currentWeekData[1], isNull,
              reason: 'Fourth Easy Run must be rejected by quota');
          await capture('schedule-quota',
              'Three Easy Runs placed; Easy choice is removed at quota and an empty-day tap adds no fourth Easy');
          await tap(find.byKey(const Key('training-workout-long')));
          await tap(find.byKey(const Key('training-day-6')));
          expect(plan.isWeekComplete(0), isTrue);
          final expectedDays = List<SessionType?>.of(plan.currentWeekData);
          await tester.ensureVisible(save);
          expect(tester.widget<GradientButton>(save).onTap, isNotNull);
          await capture('schedule-ready',
              'Week contains Easy on days 1/3/5 and Long Run on day 7; Save enabled');
          await tap(save);
          await waitUntil(() async {
            final current = container.read(programProvider);
            return current.isRegistered &&
                current.isScheduleSaved &&
                find.byType(HomeScreen).evaluate().isNotEmpty;
          }, 'New program and saved schedule');
          final week = await read('/api/programs/current/week');
          expect(week['scheduleSaved'], isTrue);
          expect(week['quests'], isA<List>());
          expect((week['quests'] as List), isNotEmpty);
          expect((week['quests'] as List).length, 4);
          expect(
              (week['quests'] as List)
                  .where((q) => q['session_type'] == 'easy')
                  .length,
              3);
          expect(
              (week['quests'] as List)
                  .where((q) => q['session_type'] == 'long_run')
                  .length,
              1);
          await capture('program-saved',
              '${hadProgram ? 'Resumed unsaved' : 'New'} active program has four saved weekly quests: three Easy and one Long (partial UAT-02-008/010)');
          await tester.drag(find.byKey(const Key('home-sheet-handle')),
              const Offset(0, -450));
          await tester.pump(const Duration(milliseconds: 600));
          await tap(find.text('จัดตารางซ้อม'));
          await waitUntil(
              () async =>
                  find.byType(TrainingScheduleScreen).evaluate().isNotEmpty,
              'Saved schedule reopens');
          await waitUntil(
              () async => plan.hasSavedWeeks, 'Saved weeks restored from API');
          expect(plan.weekSchedules[0], expectedDays);
          final reread = await read('/api/programs/current/week');
          expect((reread['quests'] as List).length, 4,
              reason: 'Reopening must not create duplicate quests');
          await capture('schedule-restored',
              'Reopened schedule matches saved day placement; API still has four quests');
          break;
        case 'run':
          step = 'run';
          final baseline = await StatsApi(api).history();
          final oldIds = baseline.map((r) => r.id).toSet();
          await state(
              'เริ่มวิ่งจากแผนวันนี้ ใช้ GPS จริงหรือลู่วิ่ง พัก/วิ่งต่อ แล้วจบและบันทึก RPE; ไม่จำลอง GPS ให้เอง');
          List<RunHistoryEntry> newRuns = [];
          await waitUntil(() async {
            newRuns = (await StatsApi(api).history())
                .where((r) => !oldIds.contains(r.id))
                .toList();
            return newRuns.any((r) => r.feedback != null);
          }, 'New completed run with feedback', seconds: 1800);
          expect(newRuns.length, 1,
              reason: 'Exactly one new completed run in this phase');
          final run = newRuns.single;
          expect(run.distance, greaterThan(0));
          expect(run.seconds, greaterThan(0));
          final detail = await StatsApi(api).detail(run.id);
          expect(detail['status'], 'completed');
          expect(double.parse('${detail['distance_km']}'),
              closeTo(run.distance!, .001));
          await onScreen(StatsScreen,
              'เปิดหน้าสถิติ ตรวจรายการวิ่งที่เพิ่งจบและช่วงวันที่ให้ครอบคลุมรายการนั้น');
          await capture('run-stats',
              'Exactly one new completed run with positive distance/time and stored feedback; Stats screen opened (partial UAT-03-016/018)');
          await onScreen(
              LeaderboardScreen, 'กลับหน้าหลักแล้วเปิดดูอันดับบุคคล');
          final ranks = await read('/api/leaderboard?scope=individual');
          expect(ranks['period']['timezone'], 'Asia/Bangkok');
          final entries = ranks['entries'] as List;
          expect(entries.length, lessThanOrEqualTo(50));
          for (var i = 1; i < entries.length; i++) {
            expect(
                (entries[i - 1]['distanceKm'] as num).toDouble(),
                greaterThanOrEqualTo(
                    (entries[i]['distanceKm'] as num).toDouble()));
          }
          expect(ranks['myEntry'], isNotNull);
          expect(ranks['myEntry']['uid'], uid);
          expect((ranks['myEntry']['distanceKm'] as num).toDouble(),
              greaterThanOrEqualTo(run.distance!));
          await capture('run-ranking',
              'Ranking API returns Thai weekly period, descending Top 50 and own distance including new run; screen opened (partial UAT-03-020)');
          break;
        case 'profile':
          step = 'profile';
          final original = await read('/api/users/me/profile');
          final oldName = original['user']['displayName'];
          await onScreen(
              ProfileScreen, 'เปิดโปรไฟล์ แก้ชื่อให้ต่างจากเดิมแล้วกดบันทึก');
          Map? profile;
          await waitUntil(() async {
            profile = await read('/api/users/me/profile') as Map;
            return profile!['user']['displayName'] != oldName;
          }, 'Profile name changed through UI');
          expect(profile!['user']['uid'], uid);
          expect(find.text(profile!['user']['displayName'] as String),
              findsWidgets);
          await capture('profile-name',
              'Changed profile name persists in real API and visible UI; UID unchanged (partial UAT-04-002)');
          break;
        case 'primary-social':
          step = 'primary-social';
          final targetUid = context['secondaryUid'] as String?;
          expect(targetUid, isNotNull, reason: 'Run setup-secondary first');
          final relation = await read('/api/friends/lookup/$targetUid');
          expect(relation['relationship']['status'], 'none',
              reason:
                  'Fresh request only; existing friendship must be handled separately');
          expect(await read('/api/clubs/me'), isNull,
              reason: 'Main account must not already have a club');
          await state(
              'เปิดเพื่อน ส่งคำขอไป UID $targetUid แล้วกลับหน้าหลัก สร้างคลับชื่อ $clubName');
          await waitUntil(() async {
            final r = await read('/api/friends/lookup/$targetUid');
            return r['relationship']['status'] == 'pending';
          }, 'Outgoing friend request becomes pending');
          final outgoing =
              await read('/api/friends/requests?direction=outgoing&limit=100');
          final matches = (outgoing['requests'] as List)
              .where((r) => r['user']['uid'] == targetUid)
              .toList();
          expect(matches.length, 1);
          await remember(
              {'friendshipId': matches.single['friendshipId'] as String});
          await capture('friend-sent',
              'Main account has exactly one outgoing pending request to secondary account (partial UAT-05-003)');
          Map? mine;
          await waitUntil(() async {
            mine = await read('/api/clubs/me') as Map?;
            return mine != null;
          }, 'New club created');
          expect(mine!['club']['name'], clubName);
          expect(mine!['myMembership']['role'], 'leader');
          expect(mine!['club']['memberCount'], 1);
          await remember(
              {'clubId': mine!['club']['id'] as String, 'clubName': clubName});
          await capture('club-created',
              'Main account created expected club as sole leader (partial UAT-06-001)');
          break;
        case 'secondary-social':
          step = 'secondary-social';
          final mainUid = context['primaryUid'] as String?;
          final clubId = context['clubId'] as String?;
          expect(mainUid, isNotNull, reason: 'Run primary-social first');
          expect(clubId, isNotNull);
          final incoming =
              await read('/api/friends/requests?direction=incoming&limit=100');
          expect(
              (incoming['requests'] as List)
                  .where((r) => r['user']['uid'] == mainUid)
                  .length,
              1);
          expect(await read('/api/clubs/me'), isNull,
              reason: 'Secondary account must not already belong to a club');
          await state(
              'เปิดเพื่อน ตอบรับคำขอจาก UID $mainUid จากนั้นค้นคลับ ${context['clubName']} แล้วกดขอเข้าคลับ (ไม่ใช่รับคำเชิญ)');
          await waitUntil(
              () async =>
                  (await read('/api/friends/lookup/$mainUid'))['relationship']
                      ['status'] ==
                  'accepted',
              'Incoming friend request accepted');
          final friends = await read('/api/friends?limit=100');
          expect(
              (friends['friends'] as List)
                  .where((r) => r['user']['uid'] == mainUid)
                  .length,
              1);
          await capture('friend-accepted',
              'Secondary accepted primary friend request and sees one friendship (partial UAT-05-003)');
          await waitUntil(() async {
            final club = await read('/api/clubs/$clubId');
            return club['myPendingRequest']?['kind'] == 'request';
          }, 'Secondary join request pending');
          expect(await read('/api/clubs/me'), isNull);
          await capture('club-requested',
              'Secondary has pending request to expected club and is not a member yet (partial UAT-06-004)');
          break;
        case 'approve-club':
          step = 'approve-club';
          final clubId = context['clubId'] as String?;
          final targetUid = context['secondaryUid'] as String?;
          expect(clubId, isNotNull);
          expect(targetUid, isNotNull);
          final beforeClub = await read('/api/clubs/$clubId');
          expect(beforeClub['myMembership']['role'], 'leader');
          expect(
              (beforeClub['members'] as List)
                  .any((r) => r['user']['uid'] == targetUid),
              isFalse);
          final startCount = beforeClub['club']['memberCount'] as num;
          final friends = await read('/api/friends?limit=100');
          expect(
              (friends['friends'] as List)
                  .where((r) => r['user']['uid'] == targetUid)
                  .length,
              1);
          await state(
              'ใช้บัญชีหลัก เปิดคลับของฉัน แล้วอนุมัติคำขอของ UID $targetUid');
          Map? club;
          await waitUntil(() async {
            club = await read('/api/clubs/$clubId') as Map;
            return (club!['members'] as List)
                .any((r) => r['user']['uid'] == targetUid);
          }, 'Secondary admitted to club');
          expect(club!['club']['memberCount'], startCount + 1);
          final member = (club!['members'] as List)
              .singleWhere((r) => r['user']['uid'] == targetUid);
          expect(member['role'], 'member');
          await capture('club-approved',
              'Main sees accepted friendship and approval added exactly one secondary member (partial UAT-05-003/UAT-06-004)');
          break;
        case 'verify-secondary':
          step = 'verify-secondary';
          final mine = await read('/api/clubs/me');
          expect(mine, isNotNull);
          expect(mine['club']['id'], context['clubId']);
          expect(mine['myMembership']['role'], 'member');
          await state(
              'เปิดคลับของฉัน ตรวจชื่อคลับและบทบาทสมาชิก แล้วกลับหน้าหลัก');
          // Require a new visible round trip, not just a preexisting Home.
          await waitUntil(
              () async => find.byType(HomeScreen).evaluate().isEmpty,
              'Open own club UI');
          await waitUntil(
              () async => find.byType(HomeScreen).evaluate().isNotEmpty,
              'Return from own club');
          await capture('secondary-membership',
              'Secondary real API confirms same club and member role after approval; UI round trip completed (partial UAT-06-004)');
          break;
        case 'shop':
          step = 'shop';
          expect(listingId, isNotEmpty,
              reason: 'Choose an explicit listing before this phase');
          final listing = await read('/api/shop/items/$listingId');
          expect(listing['owned'], isFalse,
              reason: 'Purchase scenario requires unowned item');
          final price = listing['priceCoins'] as num;
          final itemId = listing['item']['id'];
          final slot = listing['item']['slot'];
          final startBalance =
              (await read('/api/users/me/progress'))['coinBalance'] as num;
          expect(startBalance, greaterThanOrEqualTo(price),
              reason: 'Prepare coins; this suite never credits coins itself');
          await state(
              'เปิดร้าน ซื้อ ${listing['item']['name']} ราคา $price เหรียญ จากนั้นสวมใส่และบันทึกชุด; ระหว่างนี้อย่าทำกิจกรรมรับ/ใช้เหรียญอื่น');
          await waitUntil(
              () async =>
                  (await read('/api/shop/items/$listingId'))['owned'] == true,
              'Selected item purchased');
          expect((await read('/api/users/me/progress'))['coinBalance'],
              startBalance - price);
          await capture('shop-purchased',
              'Selected item ownership granted and exact price deducted (partial UAT-07-002)');
          await waitUntil(() async {
            final avatar = await read('/api/avatar/me');
            return (avatar['equipment'] as List)
                .any((e) => e['slot'] == slot && e['item']['id'] == itemId);
          }, 'Purchased item equipped and saved');
          await capture('shop-equipped',
              'Purchased item is saved in the matching avatar slot (partial UAT-07-008)');
          break;
        default:
          throw TestFailure('Unknown phase $phase');
      }
      await state(
          'Phase $phase completed: only listed assertions passed. Other UAT cases remain Not Run.',
          status: 'passed');
    } catch (error) {
      // No screenshot on OTP screens and no raw API response/token in failure logs.
      if (find.byType(OtpScreen).evaluate().isEmpty) {
        try {
          await bridge('/checkpoint', {
            'name': 'failed-$step',
            'description': 'Failure at $step; see assertion output',
            'status': 'failed',
            'png': base64Encode(await binding.takeScreenshot('failed-$step')),
          });
        } catch (_) {/* Preserve original failure if screenshot fails. */}
      }
      await state(
          'Phase $phase failed at $step. See test assertion output; remaining steps were not run.',
          status: 'failed');
      rethrow;
    }
  }, timeout: const Timeout(Duration(minutes: 60)));
}
