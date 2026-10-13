import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import '../../navigation/home_route_observer.dart';
import 'avatar_renderer.dart';

class HomeAvatar extends StatefulWidget {
  const HomeAvatar({super.key, this.rendererBuilder});
  @visibleForTesting
  final WidgetBuilder? rendererBuilder;
  @override
  State<HomeAvatar> createState() => _HomeAvatarState();
}

class _HomeAvatarState extends State<HomeAvatar> with RouteAware {
  PageRoute<dynamic>? _route;
  bool _visible = true;
  int _entry = 0;
  double _orbitDegrees = 0;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if (route is PageRoute<dynamic> && route != _route) {
      homeRouteObserver.unsubscribe(this);
      _route = route;
      homeRouteObserver.subscribe(this, route);
    }
  }

  @override
  void didPushNext() => setState(() => _visible = false);
  @override
  void didPopNext() => setState(() {
        _visible = true;
        _entry++;
        _orbitDegrees = 0;
      });
  @override
  void dispose() {
    homeRouteObserver.unsubscribe(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
      child: GestureDetector(
          key: const Key('avatar-rotation'),
          behavior: HitTestBehavior.opaque,
          dragStartBehavior: DragStartBehavior.down,
          onHorizontalDragUpdate: (details) => setState(() {
                _orbitDegrees = (_orbitDegrees - details.delta.dx * .7) % 360;
              }),
          child: Stack(alignment: Alignment.center, children: [
            if (_visible)
              Positioned.fill(
                  child: IgnorePointer(
                      child: KeyedSubtree(
                          key: ValueKey(_entry),
                          child: widget.rendererBuilder?.call(context) ??
                              AvatarRenderer(orbitDegrees: _orbitDegrees)))),
          ])));
}
