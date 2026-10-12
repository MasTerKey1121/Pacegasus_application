import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/auth_provider.dart';
import 'api_client.dart';

final clubApiProvider =
    Provider((ref) => ClubApi(ref.watch(apiClientProvider)));

class ClubApi {
  final ApiClient client;
  ClubApi(this.client);
  Future<String> uploadImage(Uint8List bytes) async {
    final response = await client.post('/api/clubs/images',
        body: {'imageBase64': base64Encode(bytes)}, auth: true);
    return response['data']['imageUrl'] as String;
  }

  Future<Map<String, dynamic>?> mine() async =>
      (await client.get('/api/clubs/me', auth: true))['data']
          as Map<String, dynamic>?;
  Future<Map<String, dynamic>> detail(String id) async =>
      (await client.get('/api/clubs/$id', auth: true))['data']
          as Map<String, dynamic>;
  Future<Map<String, dynamic>> search(String q, int offset) async =>
      (await client.get(
          '/api/clubs?${Uri(queryParameters: {
                'q': q,
                'offset': '$offset',
                'limit': '20'
              }).query}',
          auth: true))['data'] as Map<String, dynamic>;
  Future<Map<String, dynamic>> save(Map<String, dynamic> body,
          {String? id}) async =>
      (id == null
          ? await client.post('/api/clubs', body: body, auth: true)
          : await client.patch('/api/clubs/$id',
              body: body, auth: true))['data'] as Map<String, dynamic>;
  Future<void> join(String id) async {
    await client.post('/api/clubs/$id/join-requests', body: {}, auth: true);
  }

  Future<void> leave(String id) async {
    await client.post('/api/clubs/$id/leave', auth: true);
  }

  Future<void> disband(String id) async {
    await client.delete('/api/clubs/$id', auth: true);
  }

  Future<List<Map<String, dynamic>>> requests(
      {String? clubId, String kind = 'request'}) async {
    final result = <Map<String, dynamic>>[];
    for (var offset = 0;; offset += 100) {
      final response = await client.get(
          '/api/clubs/${clubId ?? 'me'}/join-requests?kind=$kind&limit=100&offset=$offset',
          auth: true);
      final rows =
          (response['data']['requests'] as List).cast<Map<String, dynamic>>();
      result.addAll(rows);
      if (rows.length < 100) return result;
    }
  }

  Future<void> handleRequest(String requestId,
      {String? clubId, required bool accept}) async {
    final path = '/api/clubs/${clubId ?? 'me'}/join-requests/$requestId';
    if (accept) {
      await client.patch('$path/${clubId == null ? 'accept' : 'approve'}',
          auth: true);
    } else {
      await client.delete(path, auth: true);
    }
  }

  Future<void> invite(String id, String uid) async {
    await client.post('/api/clubs/$id/invites',
        body: {'uid': uid.trim().toUpperCase()}, auth: true);
  }

  Future<void> role(String id, String userId, String role) async {
    await client.patch('/api/clubs/$id/members/$userId/role',
        body: {'role': role}, auth: true);
  }

  Future<void> kick(String id, String userId) async {
    await client.delete('/api/clubs/$id/members/$userId', auth: true);
  }

  Future<Map<String, dynamic>> permissions(String id) async =>
      (await client.get('/api/clubs/$id/permissions', auth: true))['data']
          as Map<String, dynamic>;
  Future<void> setPermissions(
      String id, String role, Map<String, dynamic> body) async {
    await client.patch('/api/clubs/$id/permissions/$role',
        body: body, auth: true);
  }
}
