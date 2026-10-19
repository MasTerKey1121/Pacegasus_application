import 'api_client.dart';

class AuthApi {
  final ApiClient client;
  AuthApi(this.client);

  Future<Map<String, dynamic>> google({required String idToken}) {
    return client.post('/api/auth/google', body: {'idToken': idToken});
  }

  Future<Map<String, dynamic>> requestOtp({
    required String email,
    required String purpose, // 'login' | 'register'
    bool? policyAccepted, // จำเป็นตอน purpose = register
    String? policyVersion, // จำเป็นตอน purpose = register
  }) {
    return client.post('/api/auth/otp/request', body: {
      'email': email,
      'purpose': purpose,
      if (policyAccepted != null) 'policyAccepted': policyAccepted,
      if (policyVersion != null) 'policyVersion': policyVersion,
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
      if (displayName != null && displayName.isNotEmpty)
        'displayName': displayName,
    });
  }

  Future<Map<String, dynamic>> refresh({required String refreshToken}) {
    return client
        .post('/api/auth/refresh', body: {'refreshToken': refreshToken});
  }

  Future<Map<String, dynamic>> me() => client.get('/api/auth/me', auth: true);

  Future<void> logout({required String refreshToken}) {
    return client
        .post('/api/auth/logout', body: {'refreshToken': refreshToken});
  }

  Future<Map<String, dynamic>> acceptPolicy({required String policyVersion}) {
    return client.post(
      '/api/auth/accept-policy',
      body: {'policyVersion': policyVersion},
      auth: true,
    );
  }

  Future<void>? _accountDeletion;

  // These existing endpoints require the account's credentials, so club
  // cleanup must finish before DELETE /api/users/me revokes the session.
  Future<void> deleteAccount() => _accountDeletion ??=
      _deleteAccount().whenComplete(() => _accountDeletion = null);

  Future<void> _deleteAccount() async {
    Object? identity() => client.getSessionIdentity != null
        ? client.getSessionIdentity!()
        : client.getAccessToken?.call();
    final originalIdentity = identity();
    void checkAccount() {
      if (identity() != originalIdentity) {
        throw ApiException(0, 'บัญชีเปลี่ยนระหว่างลบบัญชี กรุณาลองใหม่');
      }
    }

    final response = await client.get('/api/clubs/me', auth: true);
    checkAccount();
    final data = response['data'];
    if (response['success'] != true ||
        !response.containsKey('data') ||
        (data != null && data is! Map)) {
      throw ApiException(0, 'ยังยืนยันสถานะคลับไม่ได้ กรุณาลองใหม่');
    }
    var clubRemoved = false;
    if (data is Map) {
      final club = data['club'];
      final membership = data['myMembership'];
      final id = club is Map ? club['id'] : null;
      final role = membership is Map ? membership['role'] : null;
      if (id is! String ||
          id.isEmpty ||
          !const ['leader', 'sub_leader', 'member'].contains(role)) {
        throw ApiException(
            0, 'ยังยืนยันสมาชิกและตำแหน่งในคลับไม่ได้ กรุณาลองใหม่');
      }
      final path = '/api/clubs/${Uri.encodeComponent(id)}';
      final result = role == 'leader'
          ? await client.delete(path, auth: true)
          : await client.post('$path/leave', auth: true);
      checkAccount();
      final action = result['data'];
      if (result['success'] != true ||
          action is! Map ||
          action['clubId'] != id ||
          action['action'] != (role == 'leader' ? 'disbanded' : 'left')) {
        throw ApiException(
            0, 'ยังยืนยันผลการออกจากคลับหรือยุบคลับไม่ได้ กรุณาลองใหม่');
      }
      clubRemoved = true;
    }

    try {
      checkAccount();
      final deleted = await client.delete('/api/users/me', auth: true);
      checkAccount();
      if (deleted['success'] != true ||
          deleted['data'] is! Map ||
          deleted['data']['status'] != 'deleted') {
        throw ApiException(0, 'ยังยืนยันผลการลบบัญชีไม่ได้ กรุณาลองใหม่');
      }
    } catch (error) {
      if (clubRemoved && identity() == originalIdentity) {
        final reason =
            error is ApiException ? error.message : 'การเชื่อมต่อขัดข้อง';
        throw ApiException(error is ApiException ? error.statusCode : 0,
            'ออกจากคลับหรือยุบคลับแล้ว แต่ยังยืนยันผลการลบบัญชีไม่ได้: $reason');
      }
      rethrow;
    }
  }
}
