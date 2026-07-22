import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../services/api_client.dart';
import '../services/auth_api.dart';

enum AuthStatus { checking, authenticated, unauthenticated }

class AuthState {
  final AuthStatus status;
  final String? accessToken;
  final Map<String, dynamic>? user;

  const AuthState({required this.status, this.accessToken, this.user});

  AuthState copyWith({AuthStatus? status, String? accessToken, Map<String, dynamic>? user}) {
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
final authApiProvider = Provider<AuthApi>((ref) => AuthApi(ref.read(apiClientProvider)));

final authProvider = StateNotifierProvider<AuthNotifier, AuthState>((ref) {
  final notifier = AuthNotifier(ref.read(authApiProvider), ref.read(apiClientProvider));
  return notifier;
});

class AuthNotifier extends StateNotifier<AuthState> {
  final AuthApi _authApi;
  final ApiClient _apiClient;

  AuthNotifier(this._authApi, this._apiClient) : super(AuthState.initial) {
    // ผูก ApiClient เข้ากับ token ปัจจุบัน + ตัว silent-refresh
    _apiClient.getAccessToken = () => state.accessToken;
    _apiClient.onUnauthorized = _silentRefresh;
  }

  /// เรียกตอนแอปเปิดขึ้นมา (ดู main.dart) — เช็คว่ามี session ค้างอยู่ไหม
  Future<void> init() async {
    final refreshToken = await _secureStorage.read(key: _refreshTokenKey);
    if (refreshToken == null || refreshToken.isEmpty) {
      state = state.copyWith(status: AuthStatus.unauthenticated);
      return;
    }
    final ok = await _silentRefresh();
    if (!ok) {
      state = state.copyWith(status: AuthStatus.unauthenticated);
    }
  }

  /// ตอน verify OTP สำเร็จ (login หรือ register)
  Future<void> completeLogin(Map<String, dynamic> verifyResponseData) async {
    final accessToken = verifyResponseData['accessToken'] as String;
    final refreshToken = verifyResponseData['refreshToken'] as String;
    final user = verifyResponseData['user'] as Map<String, dynamic>;

    await _secureStorage.write(key: _refreshTokenKey, value: refreshToken);
    state = AuthState(status: AuthStatus.authenticated, accessToken: accessToken, user: user);
  }

  /// เรียกตอนเจอ 401 กลางทาง หรือตอน init() แอป — ยืด session ถ้ายัง refresh ได้
  Future<bool> _silentRefresh() async {
    final refreshToken = await _secureStorage.read(key: _refreshTokenKey);
    if (refreshToken == null || refreshToken.isEmpty) return false;

    try {
      final res = await _authApi.refresh(refreshToken: refreshToken);
      final data = res['data'] as Map<String, dynamic>;
      final newAccessToken = data['accessToken'] as String;
      // ถ้า backend หมุน refreshToken ใหม่ให้ (rotation) ก็เก็บอันใหม่ทับ
      final newRefreshToken = data['refreshToken'] as String?;
      if (newRefreshToken != null) {
        await _secureStorage.write(key: _refreshTokenKey, value: newRefreshToken);
      }

      Map<String, dynamic>? user = state.user;
      if (user == null) {
        state = state.copyWith(accessToken: newAccessToken);
        final meRes = await _authApi.me();
        user = meRes['data']['user'] as Map<String, dynamic>;
      }

      state = AuthState(status: AuthStatus.authenticated, accessToken: newAccessToken, user: user);
      return true;
    } catch (_) {
      await _secureStorage.delete(key: _refreshTokenKey);
      state = const AuthState(status: AuthStatus.unauthenticated);
      return false;
    }
  }

  Future<void> logout() async {
    final refreshToken = await _secureStorage.read(key: _refreshTokenKey);
    if (refreshToken != null) {
      try {
        await _authApi.logout(refreshToken: refreshToken);
      } catch (_) {
        // ยิง logout ฝั่ง server ไม่ผ่านก็ไม่เป็นไร เคลียร์ฝั่ง client ต่อ
      }
    }
    await _secureStorage.delete(key: _refreshTokenKey);
    state = const AuthState(status: AuthStatus.unauthenticated);
  }
}