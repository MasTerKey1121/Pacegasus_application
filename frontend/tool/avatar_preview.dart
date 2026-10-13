// Standalone visual smoke test; does not change authentication or app routes.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pacegasus/providers/avatar_provider.dart';
import 'package:pacegasus/navigation/home_route_observer.dart';
import 'package:pacegasus/screens/home/home_avatar.dart';

void main() => runApp(ProviderScope(
        overrides: [
          avatarOutfitProvider
              .overrideWith((ref) async => const AvatarOutfit({})),
        ],
        child: MaterialApp(
          theme: ThemeData.dark(),
          navigatorObservers: [homeRouteObserver],
          home: const _Preview(),
        )));

class _Preview extends StatelessWidget {
  const _Preview();
  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: const Color(0xFF110E20),
        appBar: AppBar(title: const Text('Pacegasus · Avatar preview')),
        body: Center(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
          Flexible(
              child: SizedBox(width: 560, height: 760, child: HomeAvatar())),
          const SizedBox(height: 24),
          FilledButton(
              onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                        builder: (_) => Scaffold(
                              appBar: AppBar(title: const Text('Other page')),
                              body: Center(
                                  child: FilledButton(
                                      onPressed: () =>
                                          Navigator.of(context).pop(),
                                      child: const Text('Return Home'))),
                            )),
                  ),
              child: const Text('Open other page')),
        ])),
      );
}
