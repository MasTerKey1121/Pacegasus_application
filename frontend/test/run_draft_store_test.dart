import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pacegasus/services/run_draft_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
  });

  test('returns a run draft to its owner', () async {
    final store = RunDraftStore();
    await store.save({
      'ownerUserId': 'user-a',
      'sessionId': 'session-a',
    });

    final draft = await store.loadForUser('user-a');

    expect(draft?['sessionId'], 'session-a');
  });

  test('clears a run draft when the authenticated user changes', () async {
    final store = RunDraftStore();
    await store.save({
      'ownerUserId': 'user-a',
      'sessionId': 'session-a',
    });

    expect(await store.loadForUser('user-b'), isNull);
    expect(await store.load(), isNull);
  });

  test('clears a legacy draft that has no owner', () async {
    final store = RunDraftStore();
    await store.save({'sessionId': 'legacy-session'});

    expect(await store.loadForUser('user-a'), isNull);
    expect(await store.load(), isNull);
  });
}
