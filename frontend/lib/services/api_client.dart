import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import '../config/api_config.dart';
import 'run_finish_operation.dart';

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
  final Duration requestTimeout;
  final Duration authTimeout;

  final List<String> _baseUrls;
  String? _reachableBaseUrl;

  String get baseUrl => _reachableBaseUrl ?? _baseUrls.first;

  /// เอา accessToken ปัจจุบันจาก AuthProvider (set ตอน app start)
  String? Function()? getAccessToken;
  Object? Function()? getSessionIdentity;
  bool refreshingProfile = false;

  /// เรียกตอนเจอ 401 — คืน true ถ้า refresh สำเร็จ (ให้ retry request เดิม)
  Future<bool> Function()? onUnauthorized;

  ApiClient(
      {String? baseUrl,
      List<String>? baseUrls,
      this.requestTimeout = const Duration(seconds: 30),
      this.authTimeout = const Duration(seconds: 75)})
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
    final identity = getSessionIdentity?.call();
    final originalToken = getAccessToken?.call();
    void ensureSameAccount() {
      if (auth &&
          getSessionIdentity != null &&
          identity != getSessionIdentity?.call()) {
        throw ApiException(0, 'บัญชีเปลี่ยนระหว่างคำขอ กรุณาลองใหม่');
      }
    }

    Future<http.Response> send() => _sendWithFallback((candidate) async {
          ensureSameAccount();
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
    ensureSameAccount();
    if (response.statusCode == 401 && auth && onUnauthorized != null) {
      final refreshed =
          originalToken != getAccessToken?.call() || await onUnauthorized!();
      ensureSameAccount();
      if (refreshed) response = await send();
    }
    ensureSameAccount();
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

    Future<http.Response> send() => _sendWithFallback(
        (candidate) => _dispatch(
            method, Uri.parse('$candidate$path'), headers, encodedBody),
        timeout: path.startsWith('/api/auth/') ? authTimeout : requestTimeout,
        // A missing write response does not establish whether it committed.
        // Only reads may switch addresses automatically; Side Quest GET
        // creates instances, so it is treated as a write too.
        allowFallback:
            method == 'GET' && !path.startsWith('/api/quests/side?'));
    final result = await send();
    if (RunFinishOperation.current == null &&
        method == 'GET' &&
        !path.startsWith('/api/quests/side?') &&
        [502, 503, 504].contains(result.statusCode)) {
      await Future<void>.delayed(const Duration(milliseconds: 400));
      return send(); // One read retry; mutating/generating requests never replay.
    }
    return result;
  }

  Future<http.Response> _sendWithFallback(
      Future<http.Response> Function(String candidate) send,
      {bool allowFallback = true,
      Duration? timeout}) async {
    final candidates = <String>[
      if (_reachableBaseUrl != null) _reachableBaseUrl!,
      ..._baseUrls.where((url) => url != _reachableBaseUrl),
    ];
    Object? lastConnectionError;

    for (final candidate
        in candidates.take(allowFallback ? candidates.length : 1)) {
      try {
        final scope = RunFinishOperation.current;
        final response = scope == null
            ? await send(candidate).timeout(timeout ?? requestTimeout)
            : await scope.wait(() => send(candidate),
                cap: timeout ?? requestTimeout);
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
    RunFinishOperation.current?.check();
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
    final scope = RunFinishOperation.current;
    scope?.check();
    final originalToken = getAccessToken?.call();
    final originalIdentity = getSessionIdentity?.call();
    var res = await _sendRaw(method, path, body, auth);
    if (res.statusCode == 401) scope?.log('auth_rejected', status: 401);
    bool changedAccount() => getSessionIdentity == null
        ? originalToken != getAccessToken?.call()
        : originalIdentity != getSessionIdentity?.call();
    if (auth && changedAccount()) {
      throw ApiException(
          0, 'บัญชีหรือข้อมูลเข้าสู่ระบบเปลี่ยนระหว่างคำขอ กรุณาลองใหม่');
    }

    if (res.statusCode == 401 &&
        auth &&
        onUnauthorized != null &&
        !(path == '/api/auth/me' && refreshingProfile)) {
      scope?.stage('auth_refresh');
      final refreshed = originalToken != getAccessToken?.call() ||
          (scope == null
              ? await onUnauthorized!()
              : await scope.wait(() => onUnauthorized!()));
      scope?.log('auth_refresh_result', status: refreshed ? 200 : null);
      if (getSessionIdentity != null &&
          originalIdentity != getSessionIdentity?.call()) {
        throw ApiException(0, 'บัญชีเปลี่ยนระหว่างคำขอ กรุณาลองใหม่');
      }
      if (refreshed) {
        res = await _sendRaw(method, path, body, auth); // retry ครั้งเดียว
      } else if (scope != null && getAccessToken?.call() != null) {
        // Refresh may have failed temporarily. Keep the current run and let
        // its bounded read-only connection recovery continue.
        throw ApiException(0, 'ยังต่ออายุการเชื่อมต่อไม่ได้ กรุณาลองใหม่');
      }
    }

    if (auth &&
        getSessionIdentity != null &&
        originalIdentity != getSessionIdentity?.call()) {
      throw ApiException(0, 'บัญชีเปลี่ยนระหว่างคำขอ กรุณาลองใหม่');
    }

    scope?.check();
    scope?.log('http_response', status: res.statusCode);
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
