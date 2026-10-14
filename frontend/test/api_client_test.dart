import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pacegasus/services/api_client.dart';
import 'package:pacegasus/services/own_profile_api.dart';
import 'package:pacegasus/services/profile_image_picker.dart';

void main() {
  test('avatar upload falls back, refreshes token and resends the same file',
      () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(server.close);
    final requests = <String>[];
    final tokens = <String?>[];
    server.listen((request) async {
      expect(request.method, 'PUT');
      expect(request.uri.path, '/api/users/me/avatar');
      expect(request.headers.contentType!.mimeType, 'multipart/form-data');
      tokens.add(request.headers.value('authorization'));
      requests.add(await utf8.decoder.bind(request).join());
      request.response.headers.contentType = ContentType.json;
      if (tokens.length == 1) {
        request.response.statusCode = 401;
        request.response.write(jsonEncode({'message': 'expired'}));
      } else {
        request.response.write(jsonEncode({
          'data': {
            'user': {
              'uid': 'ABCDE23456',
              'displayName': 'Runner',
              'avatarUrl':
                  'http://127.0.0.1:${server.port}/uploads/avatars/new.png',
            }
          }
        }));
      }
      await request.response.close();
    });
    var token = 'old-token';
    var refreshes = 0;
    final client = ApiClient(baseUrls: [
      'http://127.0.0.1:1',
      'http://127.0.0.1:${server.port}',
    ])
        ..getAccessToken = (() => token)
        ..onUnauthorized = () async {
          refreshes++;
          token = 'new-token';
          return true;
        };
    final user = await OwnProfileApi(client).uploadAvatar(ProfileImage(
        Uint8List.fromList(utf8.encode('image-content')),
        'image/png',
        'avatar.png'));
    expect(refreshes, 1);
    expect(tokens, ['Bearer old-token', 'Bearer new-token']);
    for (final body in requests) {
      expect(body, contains('name="avatar"; filename="avatar.png"'));
      expect(body, contains('content-type: image/png'));
      expect(body, contains('image-content'));
    }
    expect(user['avatarUrl'], endsWith('/uploads/avatars/new.png'));
  });

  test('avatar upload preserves API validation errors', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(server.close);
    server.listen((request) async {
      await request.drain<void>();
      request.response
        ..statusCode = 400
        ..headers.contentType = ContentType.json
        ..write(jsonEncode({'message': 'ไฟล์รูปต้องมีขนาดไม่เกิน 5 MB'}));
      await request.response.close();
    });
    final api =
        OwnProfileApi(ApiClient(baseUrl: 'http://127.0.0.1:${server.port}'));
    await expectLater(
        api.uploadAvatar(ProfileImage(Uint8List(1), 'image/png', 'avatar.png')),
        throwsA(isA<ApiException>()
            .having((e) => e.statusCode, 'status', 400)
            .having(
                (e) => e.message, 'message', 'ไฟล์รูปต้องมีขนาดไม่เกิน 5 MB')));
  });

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
