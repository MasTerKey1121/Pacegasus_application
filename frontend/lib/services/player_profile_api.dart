import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/auth_provider.dart';
import 'api_client.dart';
import 'club_api.dart';

final playerProfileApiProvider =
    Provider((ref) => PlayerProfileApi(ref.watch(apiClientProvider)));

/// Adapts the public UID profile and existing friendship/club APIs for the dialog.
class PlayerProfileApi {
  final ApiClient client;
  PlayerProfileApi(this.client);
  Future<Map<String, dynamic>> load(String uid) async {
    final result = await client
        .get('/api/users/profile/${Uri.encodeComponent(uid)}', auth: true);
    final profile = Map<String, dynamic>.from(result['data'] as Map);
    final user = Map<String, dynamic>.from(profile['user'] as Map);
    Map<String, dynamic> relationship = {
      'status': profile['relationship'] == 'friend'
          ? 'accepted'
          : profile['relationship'] == 'self'
              ? 'self'
              : 'unavailable'
    };
    if (profile['relationship'] == 'none') {
      try {
        final lookup = await client
            .get('/api/friends/lookup/${Uri.encodeComponent(uid)}', auth: true);
        relationship =
            Map<String, dynamic>.from(lookup['data']['relationship'] as Map);
      } catch (_) {
        /* Keep profile readable; never guess whether a request is pending. */
      }
    }
    var canManage = false;
    final club = profile['club'] as Map?;
    if (club != null && relationship['status'] != 'self') {
      try {
        final api = ClubApi(client);
        final mine = await api.mine();
        if (mine?['club']['id'] == club['id']) {
          final detail = await api.detail(club['id'] as String);
          for (final member in detail['members'] as List) {
            if (member['user']['uid'] == uid) {
              user['id'] = member['user']['id'];
              canManage = detail['myMembership']?['role'] == 'leader' &&
                  member['role'] != 'leader';
              break;
            }
          }
        }
      } catch (_) {/* Hide management until membership can be verified. */}
    }
    return {
      ...profile,
      'user': user,
      'relationship': relationship,
      'canManageMember': canManage,
      'distanceKm': (profile['stats'] as Map)['totalDistanceKm']
    };
  }
}
