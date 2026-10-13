import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pacegasus/providers/avatar_provider.dart';
import 'package:pacegasus/navigation/home_route_observer.dart';
import 'package:pacegasus/screens/home/home_avatar.dart';
import 'package:pacegasus/screens/home/avatar_renderer.dart';

Widget _scope(Widget child) => ProviderScope(overrides: [
      avatarOutfitProvider.overrideWith((ref) async => const AvatarOutfit({})),
    ], child: child);

class _Probe extends StatefulWidget {
  const _Probe(this.onStart);
  final VoidCallback onStart;
  @override
  State<_Probe> createState() => _ProbeState();
}

class _ProbeState extends State<_Probe> {
  @override
  void initState() {
    super.initState();
    widget.onStart();
  }

  @override
  Widget build(BuildContext context) => const SizedBox();
}

void main() {
  testWidgets('drag rotates through 360 without triggering the parent tap',
      (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    var taps = 0;
    await tester.pumpWidget(_scope(MaterialApp(
        home: Scaffold(
            body: Center(
      child: GestureDetector(
          onTap: () => taps++,
          child: const SizedBox(width: 460, height: 600, child: HomeAvatar())),
    )))));
    final viewer = find.byType(AvatarRenderer);
    expect(tester.widget<AvatarRenderer>(viewer).orbitDegrees, 0);
    await tester.drag(
        find.byKey(const Key('avatar-rotation')), const Offset(200, 0));
    await tester.pump();
    expect(
        tester.widget<AvatarRenderer>(viewer).orbitDegrees, closeTo(220, .01));
    expect(taps, 0);
    // More than a full turn wraps the angle instead of clamping it.
    await tester.drag(
        find.byKey(const Key('avatar-rotation')), const Offset(-600, 0));
    await tester.pump();
    expect(
        tester.widget<AvatarRenderer>(viewer).orbitDegrees, closeTo(280, .01));
    await tester.tap(find.byKey(const Key('avatar-rotation')));
    await tester.pump();
    expect(taps, 1);
    await tester.pumpWidget(const SizedBox());
    debugDefaultTargetPlatformOverride = null;
  });
  testWidgets('greets once per page entry, not rebuild or dialog',
      (tester) async {
    var starts = 0;
    final navigator = GlobalKey<NavigatorState>();
    final rebuild = ValueNotifier(0);
    await tester.pumpWidget(_scope(MaterialApp(
      navigatorKey: navigator,
      navigatorObservers: [homeRouteObserver],
      home: Scaffold(
          body: ValueListenableBuilder<int>(
        valueListenable: rebuild,
        builder: (_, value, child) => SizedBox(
            width: 230,
            height: 310,
            child: HomeAvatar(rendererBuilder: (_) => _Probe(() => starts++))),
      )),
    )));
    expect(starts, 1);
    rebuild.value++;
    await tester.pump();
    expect(starts, 1);
    showDialog<void>(
        context: navigator.currentContext!,
        builder: (_) => const AlertDialog(title: Text('dialog')));
    await tester.pumpAndSettle();
    navigator.currentState!.pop();
    await tester.pumpAndSettle();
    expect(starts, 1);
    for (var i = 0; i < 2; i++) {
      navigator.currentState!.push(MaterialPageRoute<void>(
          builder: (_) => const Scaffold(body: Text('other'))));
      await tester.pumpAndSettle();
      expect(find.byType(_Probe), findsNothing);
      navigator.currentState!.pop();
      await tester.pumpAndSettle();
      expect(starts, i + 2);
    }
    await tester.pumpWidget(const SizedBox());
    rebuild.dispose();
  });
}
