import 'package:flutter_test/flutter_test.dart';
import 'package:pacegasus/providers/program_provider.dart';
import 'package:pacegasus/services/api_client.dart';
import 'package:pacegasus/services/onboarding_api.dart';
import 'package:pacegasus/services/program_api.dart';

const activePlan = <String, dynamic>{
  'data': {
    'userProgramId': 'plan-1',
    'templateLevel': 'beginner',
    'startDate': '2026-09-19',
    'scheduleSaved': false,
    'quests': <dynamic>[],
  },
};

class TestApi extends ProgramApi {
  TestApi(this.reads) : super(ApiClient(baseUrl: 'http://localhost'));
  final List<Object> reads;
  int starts = 0;
  ApiException? startError;
  @override
  Future<Map<String, dynamic>> getCurrentWeek() async {
    final result = reads.removeAt(0);
    if (result is Map<String, dynamic>) return result;
    throw result;
  }

  @override
  Future<Map<String, dynamic>> start({required String level}) async {
    starts++;
    if (startError != null) throw startError!;
    return activePlan;
  }
}

class TestOnboarding extends OnboardingApi {
  TestOnboarding() : super(ApiClient(baseUrl: 'http://localhost'));
  @override
  Future<Map<String, dynamic>> status() async => {
        'data': {'runningExperienceLevel': 'beginner'},
      };
}

void main() {
  ProgramNotifier notifier(TestApi api) {
    final program = ProgramNotifier(api, TestOnboarding());
    addTearDown(program.dispose);
    return program;
  }

  test('new registration creates once and loads the schedule', () async {
    final api = TestApi([ApiException(404, 'no plan'), activePlan]);
    final program = notifier(api);
    expect(await program.registerPlan(level: 'beginner'), isTrue);
    expect(api.starts, 1);
    expect(program.isRegistered, isTrue);
    expect(program.programStartDate, DateTime(2026, 9, 19));
    expect(program.errorMessage, isNull);
  });

  test('existing program resumes without creating or cancelling a plan',
      () async {
    final api = TestApi([activePlan]);
    final program = notifier(api);
    expect(await program.registerPlan(level: 'upper_intermediate'), isTrue);
    expect(api.starts, 0);
    expect(program.selectedTemplateLevel, 'beginner');
    expect(program.isRegistered, isTrue);
  });

  test('failed refresh after creation preserves registration and retries reads',
      () async {
    final api = TestApi([
      ApiException(404, 'no plan'),
      ApiException(500, 'read failed'),
      activePlan,
    ]);
    final program = notifier(api);
    expect(await program.registerPlan(level: 'beginner'), isTrue);
    expect(program.isRegistered, isTrue);
    expect(program.programStartDate, DateTime(2026, 9, 19));
    expect(program.currentWeekErrorMessage, 'read failed');
    await program.restore(force: true);
    expect(api.starts, 1);
    expect(program.currentWeekErrorMessage, isNull);
  });

  test('unavailable current program does not cause a duplicate registration',
      () async {
    final api = TestApi([ApiException(500, 'server error')]);
    final program = notifier(api);
    expect(await program.registerPlan(level: 'beginner'), isFalse);
    expect(api.starts, 0);
    expect(program.isRegistering, isFalse);
  });

  test('concurrent registration conflict recovers the existing program',
      () async {
    final api = TestApi([ApiException(404, 'no plan'), activePlan])
      ..startError = ApiException(400,
          'คุณมีโปรแกรมที่กำลังดำเนินการอยู่แล้ว ต้องจบ/หยุดโปรแกรมเดิมก่อน');
    final program = notifier(api);
    expect(await program.registerPlan(level: 'beginner'), isTrue);
    expect(program.isRegistered, isTrue);
    expect(program.errorMessage, isNull);
  });
}
