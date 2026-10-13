import 'dart:math' as math;
import 'package:flutter/widgets.dart';

/// One size calculation shared by Home and expanded shop/wardrobe previews.
class AvatarLayout {
  const AvatarLayout(this.width, this.height, this.top);
  final double width, height, top;

  factory AvatarLayout.home(Size viewport, {bool avatarOnly = false}) {
    const scale = .81; // Previous .9 size, reduced by another 10%.
    final top = math.min(160.0, viewport.height * .25);
    final original = math.min(330.0, viewport.height * .48);
    return AvatarLayout(
      math.max(0, math.min(460.0, viewport.width - 24)) * scale,
      math.max(
              0,
              math.min(
                  original * 2,
                  avatarOnly
                      ? viewport.height - 24
                      : viewport.height - top - 12)) *
          scale,
      top - 5,
    );
  }
}
