import 'dart:convert';
import 'package:http/http.dart' as http;
import '../config/api_config.dart';

class ApiException implements Exception {
  final int statusCode;
  final String message;
  ApiException(this.statusCode, this.message);
  @override
  String toString() => message;
}

/// ตัวกลางยิง HTTP ทั้งหมดของแอป
/// - แนบ Authorization header อัตโนมัติเมื่อ auth: true
/// - ถ้าเจอ 401 จะพยายาม refresh token แล้ว retry ให้ 1 ครั้ง
class ApiClient {
  final String baseUrl;

  /// เอา accessToken ปัจจุบันจาก AuthProvider (set ตอน app start)
  String? Function()? getAccessToken;

  /// เรียกตอนเจอ 401 — คืน true ถ้า refresh สำเร็จ (ให้ retry request เดิม)
  Future<bool> Function()? onUnauthorized;

  ApiClient({this.baseUrl = ApiConfig.baseUrl});

  Future<Map<String, dynamic>> get(String path, {bool auth = false}) =>
      _request('GET', path, auth: auth);

  Future<Map<String, dynamic>> post(String path, {Map<String, dynamic>? body, bool auth = false}) =>
      _request('POST', path, body: body, auth: auth);

  Future<Map<String, dynamic>> put(String path, {Map<String, dynamic>? body, bool auth = false}) =>
      _request('PUT', path, body: body, auth: auth);

  Future<Map<String, dynamic>> delete(String path, {Map<String, dynamic>? body, bool auth = false}) =>
      _request('DELETE', path, body: body, auth: auth);

  Future<http.Response> _sendRaw(String method, String path, Map<String, dynamic>? body, bool auth) {
    final uri = Uri.parse('$baseUrl$path');
    final headers = <String, String>{'Content-Type': 'application/json'};
    if (auth) {
      final token = getAccessToken?.call();
      if (token != null && token.isNotEmpty) {
        headers['Authorization'] = 'Bearer $token';
      }
    }
    final encodedBody = body != null ? jsonEncode(body) : null;
    switch (method) {
      case 'GET':
        return http.get(uri, headers: headers);
      case 'POST':
        return http.post(uri, headers: headers, body: encodedBody);
      case 'PUT':
        return http.put(uri, headers: headers, body: encodedBody);
      case 'DELETE':
        return http.delete(uri, headers: headers, body: encodedBody);
      default:
        throw UnimplementedError(method);
    }
  }

  Future<Map<String, dynamic>> _request(
    String method,
    String path, {
    Map<String, dynamic>? body,
    bool auth = false,
  }) async {
    var res = await _sendRaw(method, path, body, auth);

    if (res.statusCode == 401 && auth && onUnauthorized != null) {
      final refreshed = await onUnauthorized!();
      if (refreshed) {
        res = await _sendRaw(method, path, body, auth); // retry ครั้งเดียว
      }
    }

    return _handle(res);
  }

  Map<String, dynamic> _handle(http.Response res) {
    Map<String, dynamic> json;
    try {
      json = res.body.isEmpty ? {} : jsonDecode(res.body) as Map<String, dynamic>;
    } catch (_) {
      json = {};
    }

    if (res.statusCode < 200 || res.statusCode >= 300) {
      final message = (json['message'] ?? json['error'] ?? 'เกิดข้อผิดพลาด (${res.statusCode})').toString();
      throw ApiException(res.statusCode, message);
    }
    return json;
  }
}