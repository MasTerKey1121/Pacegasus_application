import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pacegasus/services/api_client.dart';

void main() {
  test('falls back to the next Android development server address', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      request.response
        ..statusCode = HttpStatus.ok
        ..headers.contentType = ContentType.json
        ..write(jsonEncode({
          'success': true,
          'data': {'ok': true}
        }));
      await request.response.close();
    });
    addTearDown(server.close);

    final client = ApiClient(baseUrls: [
      'http://127.0.0.1:1',
      'http://127.0.0.1:${server.port}',
    ]);

    final response = await client.get('/api/health');

    expect(response['data']['ok'], isTrue);
    expect(client.baseUrl, 'http://127.0.0.1:${server.port}');
  });

  test('returns a readable error instead of loading forever', () async {
    final client = ApiClient(baseUrl: 'http://127.0.0.1:1');

    await expectLater(
      client.get('/api/health'),
      throwsA(
        isA<ApiException>().having(
          (error) => error.message,
          'message',
          contains('เชื่อมต่อเซิร์ฟเวอร์ไม่ได้'),
        ),
      ),
    );
  });
}
