import 'dart:convert';
import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pacegasus/providers/auth_provider.dart';
import 'package:pacegasus/services/api_client.dart';
import 'package:pacegasus/services/auth_api.dart';
import 'package:pacegasus/services/google_sign_in_service.dart';

class FakeGoogleSignIn extends GoogleSignInService {
  final String? token;
  FakeGoogleSignIn(this.token);

  @override
  Future<String?> signIn() async => token;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  // These unit tests exercise real loopback HTTP, not widget network stubs.
  setUpAll(() => HttpOverrides.global = null);
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  Future<AuthNotifier> createAuth(
      {String? token = 'google-id-token', int status = 200}) async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    server.listen((request) async {
      expect(request.method, 'POST');
      expect(request.uri.path, '/api/auth/google');
      expect(jsonDecode(await utf8.decoder.bind(request).join()),
          {'idToken': token});
      request.response
        ..statusCode = status
        ..headers.contentType = ContentType.json
        ..write(jsonEncode(status == 200
            ? {
                'success': true,
                'data': {
                  'accessToken': 'app-access-token',
                  'refreshToken': 'app-refresh-token',
                  'user': {
                    'id': 'user-1',
                    'email': 'runner@example.com',
                    'policyAccepted': false,
                    'onboardingCompleted': false
                  },
                },
              }
            : {
                'success': false,
                'message': 'Google idToken ไม่ถูกต้องหรือหมดอายุ'
              }));
      await request.response.close();
    });
    final client = ApiClient(baseUrl: 'http://127.0.0.1:${server.port}');
    final auth = AuthNotifier(AuthApi(client), client,
        googleSignIn: FakeGoogleSignIn(token));
    addTearDown(auth.dispose);
    await auth.init();
    return auth;
  }

  test('Google token is exchanged for an app session and persisted for restart',
      () async {
    final auth = await createAuth();
    expect(await auth.signInWithGoogle(), isTrue);
    expect(auth.state.status, AuthStatus.authenticated);
    expect(auth.state.accessToken, 'app-access-token');
    expect(auth.state.user!['policyAccepted'], isFalse);
    expect(await const FlutterSecureStorage().read(key: 'refresh_token'),
        'app-refresh-token');
  });

  test('canceling Google does not authenticate or store a session', () async {
    final auth = await createAuth(token: null);
    expect(await auth.signInWithGoogle(), isFalse);
    expect(auth.state.status, AuthStatus.unauthenticated);
    expect(
        await const FlutterSecureStorage().read(key: 'refresh_token'), isNull);
  });

  test('backend rejection does not authenticate or store a session', () async {
    final auth = await createAuth(status: 401);
    await expectLater(
        auth.signInWithGoogle(),
        throwsA(
            isA<ApiException>().having((e) => e.statusCode, 'status', 401)));
    expect(auth.state.status, AuthStatus.unauthenticated);
    expect(
        await const FlutterSecureStorage().read(key: 'refresh_token'), isNull);
  });
}
