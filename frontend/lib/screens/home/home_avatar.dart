import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/avatar_provider.dart';
import '../../services/shop_api.dart';
import '../../navigation/home_route_observer.dart';
import 'avatar_renderer.dart';

class HomeAvatar extends ConsumerStatefulWidget {
  const HomeAvatar(
      {super.key,
      this.rendererBuilder,
      this.outfitPreview = const {},
      this.productAsset,
      this.productVariant});
  final String? productAsset, productVariant;
  final Map<String, ShopItem> outfitPreview;
  @visibleForTesting
  final WidgetBuilder? rendererBuilder;
  @override
  ConsumerState<HomeAvatar> createState() => _HomeAvatarState();
}

class _HomeAvatarState extends ConsumerState<HomeAvatar> with RouteAware {
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
  void didPopNext() {
    if (widget.rendererBuilder == null) ref.invalidate(avatarOutfitProvider);
    setState(() {
      _visible = true;
      _entry++;
      _orbitDegrees = 0;
    });
  }

  @override
  void dispose() {
    homeRouteObserver.unsubscribe(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Test renderer injection avoids networking and platform-view setup.
    final outfit = widget.rendererBuilder != null || widget.productAsset != null
        ? const AvatarOutfit({})
        : ref.watch(avatarOutfitProvider).valueOrNull ?? const AvatarOutfit({});
    final variant = widget.productAsset != null
        ? widget.productVariant
        : outfit.preview(widget.outfitPreview).variant;
    return ExcludeSemantics(
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
                            key: ValueKey(
                                '$_entry:${widget.productAsset ?? 'avatar'}'),
                            child: widget.rendererBuilder?.call(context) ??
                                AvatarRenderer(
                                    orbitDegrees: _orbitDegrees,
                                    variantName: variant,
                                    assetPath: widget.productAsset ??
                                        'assets/models/pacegasus_starter_v9.glb',
                                    animated: widget.productAsset == null)))),
            ])));
  }
}
