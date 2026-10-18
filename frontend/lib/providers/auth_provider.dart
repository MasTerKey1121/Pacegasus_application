import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../services/api_client.dart';
import '../services/auth_api.dart';
import '../services/google_sign_in_service.dart';
import '../services/profile_avatar_url.dart';

enum AuthStatus { checking, authenticated, unauthenticated, connectionRequired }

class AuthState {
  final AuthStatus status;
  final String? accessToken;
  final String? connectionMessage;
  final Map<String, dynamic>? user;

  const AuthState(
      {required this.status,
      this.accessToken,
      this.user,
      this.connectionMessage});

  AuthState copyWith(
      {AuthStatus? status, String? accessToken, Map<String, dynamic>? user}) {
    return AuthState(
      status: status ?? this.status,
      accessToken: accessToken ?? this.accessToken,
      user: user ?? this.user,
    );
  }

  static const initial = AuthState(status: AuthStatus.checking);
}

final _secureStorage = FlutterSecureStorage();
const _refreshTokenKey = 'refresh_token';

final apiClientProvider = Provider<ApiClient>((ref) => ApiClient());
final authApiProvider =
    Provider<AuthApi>((ref) => AuthApi(ref.read(apiClientProvider)));
final googleSignInServiceProvider =
    Provider<GoogleSignInService>((ref) => GoogleSignInService());

final authProvider = StateNotifierProvider<AuthNotifier, AuthState>((ref) {
  final notifier = AuthNotifier(
      ref.read(authApiProvider), ref.read(apiClientProvider),
      googleSignIn: ref.read(googleSignInServiceProvider));
  return notifier;
});

class AuthNotifier extends StateNotifier<AuthState> {
  final AuthApi _authApi;
  final ApiClient _apiClient;
  final GoogleSignInService _googleSignIn;
  final FlutterSecureStorage _storage;
  Future<bool>? _refreshing;
  Future<void> _storageWrites = Future.value();
  int _epoch = 0;
  Future<void> _store(Future<void> Function() action) {
    final next = _storageWrites.then((_) => action());
    _storageWrites = next.then((_) {}, onError: (Object _, StackTrace __) {});
    return next;
  }

  AuthNotifier(this._authApi, this._apiClient,
      {GoogleSignInService? googleSignIn, FlutterSecureStorage? storage})
      : _googleSignIn = googleSignIn ?? GoogleSignInService(),
        _storage = storage ?? _secureStorage,
        super(AuthState.initial) {
    // ผูก ApiClient เข้ากับ token ปัจจุบัน + ตัว silent-refresh
    _apiClient.getAccessToken = () => mounted ? state.accessToken : null;
    _apiClient.getSessionIdentity = () => _epoch;
    _apiClient.onUnauthorized = _silentRefresh;
  }

  /// เรียกตอนแอปเปิดขึ้นมา (ดู main.dart) — เช็คว่ามี session ค้างอยู่ไหม
  Future<void> init() async {
    if (!mounted) return;
    state = AuthState(
        status: AuthStatus.checking,
        accessToken: state.accessToken,
        user: state.user,
        connectionMessage: 'กำลังเชื่อมต่อและตรวจสอบการเข้าสู่ระบบ…');
    await _silentRefresh();
  }

  void updateUser(Map<String, dynamic> user) {
    state = state.copyWith(user: _userWithAvatar(user));
  }

  Map<String, dynamic> _userWithAvatar(Map<String, dynamic> user) => {
        ...user,
        'avatarUrl': profileAvatarUrl(
            user['avatarUrl'] ?? user['avatar_url'], _apiClient.baseUrl)
      };

  Future<bool> signInWithGoogle() async {
    final idToken = await _googleSignIn.signIn();
    if (idToken == null) return false;
    final response = await _authApi.google(idToken: idToken);
    await completeLogin(response['data'] as Map<String, dynamic>);
    return true;
  }

  /// Save the session returned by either OTP or Google authentication.
  Future<void> completeLogin(Map<String, dynamic> verifyResponseData) async {
    final accessToken = verifyResponseData['accessToken'] as String;
    final refreshToken = verifyResponseData['refreshToken'] as String;
    final user = verifyResponseData['user'] as Map<String, dynamic>;

    final epoch = ++_epoch;
    _refreshing = null;
    await _store(
        () => _storage.write(key: _refreshTokenKey, value: refreshToken));
    if (!mounted || epoch != _epoch) return;
    state = AuthState(
        status: AuthStatus.authenticated,
        accessToken: accessToken,
        user: _userWithAvatar(user));
  }

  /// เรียกตอนเจอ 401 กลางทาง หรือตอน init() แอป — ยืด session ถ้ายัง refresh ได้
  Future<bool> _silentRefresh() {
    if (_refreshing != null) return _refreshing!;
    final future = _refreshOnce();
    _refreshing = future;
    future.whenComplete(() {
      if (identical(_refreshing, future)) _refreshing = null;
    });
    return future;
  }

  Future<bool> _refreshOnce() async {
    final epoch = _epoch;
    var refreshed = false;
    try {
      await _storageWrites;
      final refreshToken = await _storage.read(key: _refreshTokenKey);
      if (!mounted || epoch != _epoch) return false;
      if (refreshToken == null || refreshToken.isEmpty) {
        state = const AuthState(status: AuthStatus.unauthenticated);
        return false;
      }
      final res = await _authApi.refresh(refreshToken: refreshToken);
      if (!mounted || epoch != _epoch) return false;
      final data = res['data'] as Map;
      final token = data['accessToken'] as String;
      final rotated = data['refreshToken'] as String?;
      refreshed = true;
      if (rotated != null) {
        await _store(
            () => _storage.write(key: _refreshTokenKey, value: rotated));
      }
      if (!mounted || epoch != _epoch) return false;
      state =
          AuthState(status: state.status, user: state.user, accessToken: token);
      _apiClient.refreshingProfile = true;
      final me = await _authApi.me();
      if (!mounted || epoch != _epoch) return false;
      final user = Map<String, dynamic>.from(me['data']['user'] as Map);
      if (user['id'] == null) {
        throw const FormatException('Missing user identity');
      }
      state = AuthState(
          status: AuthStatus.authenticated,
          accessToken: token,
          user: _userWithAvatar(user));
      return true;
    } catch (error) {
      if (!mounted || epoch != _epoch) return false;
      // Only an explicit refresh rejection proves that the stored credential
      // is invalid. A missing response may have followed token rotation.
      if (!refreshed &&
          error is ApiException &&
          [401, 403].contains(error.statusCode)) {
        await _store(() => _storage.delete(key: _refreshTokenKey));
        if (mounted && epoch == _epoch) {
          state = const AuthState(status: AuthStatus.unauthenticated);
        }
      } else {
        state = AuthState(
            status: AuthStatus.connectionRequired,
            accessToken: state.accessToken,
            user: state.user,
            connectionMessage:
                'ยังเชื่อมต่อเพื่อตรวจสอบการเข้าสู่ระบบไม่ได้ ข้อมูลเข้าสู่ระบบยังเก็บไว้ กรุณาลองใหม่');
      }
      return false;
    } finally {
      _apiClient.refreshingProfile = false;
    }
  }

  Future<void> logout() async {
    _epoch++;
    _refreshing = null;
    await _storageWrites;
    final token = await _storage.read(key: _refreshTokenKey);
    await _store(() => _storage.delete(key: _refreshTokenKey));
    if (mounted) state = const AuthState(status: AuthStatus.unauthenticated);
    if (token != null) {
      try {
        await _authApi.logout(refreshToken: token);
      } catch (_) {}
    }
  }

  @override
  void dispose() {
    _epoch++;
    super.dispose();
  }
}
