import 'api_client.dart';

class AuthApi {
  final ApiClient client;
  AuthApi(this.client);

  Future<Map<String, dynamic>> requestOtp({
    required String email,
    required String purpose, // 'login' | 'register'
  }) {
    return client.post('/api/auth/otp/request', body: {
      'email': email,
      'purpose': purpose,
    });
  }

  Future<Map<String, dynamic>> verifyOtp({
    required String email,
    required String otp,
    required String otpRef,
    String? displayName, // จำเป็นตอน purpose = register
  }) {
    return client.post('/api/auth/otp/verify', body: {
      'email': email,
      'otp': otp,
      'otpRef': otpRef,
      if (displayName != null && displayName.isNotEmpty) 'displayName': displayName,
    });
  }

  Future<Map<String, dynamic>> refresh({required String refreshToken}) {
    return client.post('/api/auth/refresh', body: {'refreshToken': refreshToken});
  }

  Future<Map<String, dynamic>> me() => client.get('/api/auth/me', auth: true);

  Future<void> logout({required String refreshToken}) {
    return client.post('/api/auth/logout', body: {'refreshToken': refreshToken});
  }

  // ⚠️ TODO: path นี้เดาจาก REST convention (DELETE /api/users/me) เพราะใน Postman
  // collection ที่ให้มายังไม่มี endpoint สำหรับลบบัญชี — ต้องขอ path/response จริงจากทีม backend
  // แล้วมาแก้ตรงนี้อีกที
  Future<void> deleteAccount() {
    return client.delete('/api/users/me', auth: true);
  }
}