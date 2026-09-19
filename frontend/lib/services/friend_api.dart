import 'api_client.dart';

class FriendEntry {
  final String friendshipId, name, uid;
  final String? avatarUrl;

  const FriendEntry(
      {required this.friendshipId,
      required this.name,
      required this.uid,
      this.avatarUrl});

  factory FriendEntry.fromJson(Map<String, dynamic> json) {
    final user = json['user'] as Map<String, dynamic>;
    return FriendEntry(
      friendshipId: json['friendshipId'] as String,
      name: user['displayName'] as String? ?? 'นักวิ่ง',
      uid: user['uid'] as String,
      avatarUrl: user['avatarUrl'] as String?,
    );
  }
}

class FriendApi {
  final ApiClient client;
  FriendApi(this.client);

  // Fetch every page so name search includes all existing friends.
  Future<List<FriendEntry>> list({String? direction}) async {
    final result = <FriendEntry>[];
    const limit = 100;
    for (var offset = 0;; offset += limit) {
      final path = direction == null
          ? '/api/friends?limit=$limit&offset=$offset'
          : '/api/friends/requests?direction=$direction&limit=$limit&offset=$offset';
      final response = await client.get(path, auth: true);
      final rows =
          response['data'][direction == null ? 'friends' : 'requests'] as List;
      result.addAll(
          rows.map((row) => FriendEntry.fromJson(row as Map<String, dynamic>)));
      if (rows.length < limit) return result;
    }
  }

  Future<bool> send(String uid) async {
    final response = await client.post('/api/friends/requests',
        body: {'uid': uid.trim().toUpperCase()}, auth: true);
    return response['data']['autoAccepted'] == true;
  }

  Future<void> accept(String id) async {
    await client.patch(
        '/api/friends/requests/${Uri.encodeComponent(id)}/accept',
        auth: true);
  }

  Future<void> removeRequest(String id) async {
    await client.delete('/api/friends/requests/${Uri.encodeComponent(id)}',
        auth: true);
  }
}
