// Standalone local preview: flutter run -d chrome -t lib/avatar_preview.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'providers/avatar_provider.dart';
import 'screens/wardrobe/wardrobe_screen.dart';

void main() {
  runApp(ProviderScope(
    overrides: [
      avatarProvider.overrideWith((ref) {
        const storage = FlutterSecureStorage();
        return AvatarWardrobe(
          read: () => storage.read(key: 'avatar_preview_v1'),
          write: (value) =>
              storage.write(key: 'avatar_preview_v1', value: value),
        )..restore();
      }),
    ],
    child: MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark(useMaterial3: true),
      home: const WardrobeScreen(),
    ),
  ));
}
