import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pacegasus/navigation/home_route_observer.dart';
import 'package:pacegasus/screens/home/home_avatar.dart';

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
  testWidgets('greets once per page entry, not rebuild or dialog',
      (tester) async {
    var starts = 0;
    final navigator = GlobalKey<NavigatorState>();
    final rebuild = ValueNotifier(0);
    await tester.pumpWidget(MaterialApp(
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
    ));
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
