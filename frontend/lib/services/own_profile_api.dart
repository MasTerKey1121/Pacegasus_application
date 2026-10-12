import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/auth_provider.dart';
import 'api_client.dart';

final ownProfileApiProvider =
    Provider((ref) => OwnProfileApi(ref.watch(apiClientProvider)));

class OwnProfileApi {
  final ApiClient client;
  OwnProfileApi(this.client);
  Future<Map<String, dynamic>> load() async =>
      (await client.get('/api/users/me/profile', auth: true))['data']
          as Map<String, dynamic>;
  Future<Map<String, dynamic>> save(String field, String value) async =>
      (await client.patch('/api/users/me/profile',
          body: {field: value},
          auth: true))['data']['user'] as Map<String, dynamic>;
}
