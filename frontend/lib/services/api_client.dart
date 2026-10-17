import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

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
  static const _requestTimeout = Duration(seconds: 10);

  final List<String> _baseUrls;
  String? _reachableBaseUrl;

  String get baseUrl => _reachableBaseUrl ?? _baseUrls.first;

  /// เอา accessToken ปัจจุบันจาก AuthProvider (set ตอน app start)
  String? Function()? getAccessToken;

  /// เรียกตอนเจอ 401 — คืน true ถ้า refresh สำเร็จ (ให้ retry request เดิม)
  Future<bool> Function()? onUnauthorized;

  ApiClient({String? baseUrl, List<String>? baseUrls})
      : assert(baseUrl == null || baseUrls == null),
        _baseUrls = baseUrls ??
            (baseUrl == null ? ApiConfig.baseUrls : <String>[baseUrl]);

  Future<Map<String, dynamic>> get(String path, {bool auth = false}) =>
      _request('GET', path, auth: auth);

  Future<Map<String, dynamic>> post(String path,
          {Map<String, dynamic>? body, bool auth = false}) =>
      _request('POST', path, body: body, auth: auth);

  Future<Map<String, dynamic>> put(String path,
          {Map<String, dynamic>? body, bool auth = false}) =>
      _request('PUT', path, body: body, auth: auth);

  Future<Map<String, dynamic>> patch(String path,
          {Map<String, dynamic>? body, bool auth = false}) =>
      _request('PATCH', path, body: body, auth: auth);

  Future<Map<String, dynamic>> delete(String path,
          {Map<String, dynamic>? body, bool auth = false}) =>
      _request('DELETE', path, body: body, auth: auth);

  Future<Map<String, dynamic>> upload(
    String path, {
    required Uint8List bytes,
    required String filename,
    required String mimeType,
    String field = 'avatar',
    bool auth = false,
  }) async {
    Future<http.Response> send() => _sendWithFallback((candidate) async {
          // Multipart requests are single-use: rebuild for fallback and token retry.
          final request =
              http.MultipartRequest('PUT', Uri.parse('$candidate$path'));
          final token = getAccessToken?.call();
          if (auth && token != null && token.isNotEmpty) {
            request.headers['Authorization'] = 'Bearer $token';
          }
          request.files.add(http.MultipartFile.fromBytes(field, bytes,
              filename: filename, contentType: http.MediaType.parse(mimeType)));
          return http.Response.fromStream(await request.send());
        });
    var response = await send();
    if (response.statusCode == 401 && auth && onUnauthorized != null) {
      if (await onUnauthorized!()) response = await send();
    }
    return _handle(response);
  }

  Future<http.Response> _sendRaw(
    String method,
    String path,
    Map<String, dynamic>? body,
    bool auth,
  ) async {
    final headers = <String, String>{'Content-Type': 'application/json'};
    if (auth) {
      final token = getAccessToken?.call();
      if (token != null && token.isNotEmpty) {
        headers['Authorization'] = 'Bearer $token';
      }
    }
    final encodedBody = body != null ? jsonEncode(body) : null;

    final guardedRunWrite = path == '/api/rpe' ||
        path.startsWith('/api/running-sessions') ||
        path.startsWith('/api/side-quests') ||
        path.startsWith('/api/quests/') ||
        (path.startsWith('/api/programs/quests/') &&
            path.endsWith('/complete'));
    return _sendWithFallback(
        (candidate) => _dispatch(
            method, Uri.parse('$candidate$path'), headers, encodedBody),
        allowFallback: !guardedRunWrite ||
            (method == 'GET' && !path.startsWith('/api/quests/side?')));
  }

  Future<http.Response> _sendWithFallback(
      Future<http.Response> Function(String candidate) send,
      {bool allowFallback = true}) async {
    final candidates = <String>[
      if (_reachableBaseUrl != null) _reachableBaseUrl!,
      ..._baseUrls.where((url) => url != _reachableBaseUrl),
    ];
    Object? lastConnectionError;

    for (final candidate
        in candidates.take(allowFallback ? candidates.length : 1)) {
      try {
        final response = await send(candidate).timeout(_requestTimeout);
        _reachableBaseUrl = candidate;
        return response;
      } on TimeoutException catch (error) {
        lastConnectionError = error;
      } on SocketException catch (error) {
        lastConnectionError = error;
      } on http.ClientException catch (error) {
        lastConnectionError = error;
      }
    }

    throw ApiException(
      0,
      lastConnectionError is TimeoutException
          ? 'หมดเวลารอการเชื่อมต่อเซิร์ฟเวอร์ กรุณาลองใหม่อีกครั้ง'
          : 'เชื่อมต่อเซิร์ฟเวอร์ไม่ได้ กรุณาตรวจสอบว่าเซิร์ฟเวอร์เปิดอยู่',
    );
  }

  Future<http.Response> _dispatch(
    String method,
    Uri uri,
    Map<String, String> headers,
    String? encodedBody,
  ) {
    switch (method) {
      case 'GET':
        return http.get(uri, headers: headers);
      case 'POST':
        return http.post(uri, headers: headers, body: encodedBody);
      case 'PUT':
        return http.put(uri, headers: headers, body: encodedBody);
      case 'PATCH':
        return http.patch(uri, headers: headers, body: encodedBody);
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
    final originalToken = getAccessToken?.call();
    var res = await _sendRaw(method, path, body, auth);
    if (auth && originalToken != getAccessToken?.call()) {
      throw ApiException(
          0, 'บัญชีหรือข้อมูลเข้าสู่ระบบเปลี่ยนระหว่างคำขอ กรุณาลองใหม่');
    }

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
      json =
          res.body.isEmpty ? {} : jsonDecode(res.body) as Map<String, dynamic>;
    } catch (_) {
      json = {};
    }

    if (res.statusCode < 200 || res.statusCode >= 300) {
      final message = (json['message'] ??
              json['error'] ??
              'เกิดข้อผิดพลาด (${res.statusCode})')
          .toString();
      throw ApiException(res.statusCode, message);
    }
    return json;
  }
}
