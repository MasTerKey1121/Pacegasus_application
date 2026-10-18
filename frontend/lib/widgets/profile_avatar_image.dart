import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/auth_provider.dart';
import '../services/profile_avatar_url.dart';

/// Uses the latest confirmed own-profile URL even in previously loaded lists.
class ProfileAvatarImage extends ConsumerWidget {
  const ProfileAvatarImage(
      {super.key,
      this.url,
      this.uid,
      this.userId,
      required this.size,
      this.fallback = const Icon(Icons.person_outline)});
  final String? url, uid, userId;
  final double size;
  final Widget fallback;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authProvider.select((s) => s.user));
    final own = user != null &&
        user.containsKey('avatarUrl') &&
        ((uid != null && uid == user['uid']) ||
            (userId != null && userId == user['id']));
    final resolved = profileAvatarUrl(
        own ? user['avatarUrl'] : url, ref.read(apiClientProvider).baseUrl);
    return resolved == null
        ? fallback
        : Image.network(resolved,
            key: ValueKey('${own ? user['id'] : uid ?? userId}/$resolved'),
            width: size,
            height: size,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => fallback);
  }
}
