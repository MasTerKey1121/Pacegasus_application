import 'dart:math' as math;
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pacegasus/screens/home/avatar_layout.dart';

void main() {
  test('Home is 10% smaller than the preceding .9 layout', () {
    for (final viewport in [const Size(320, 700), const Size(1280, 720)]) {
      for (final only in [false, true]) {
        final top = math.min(160.0, viewport.height * .25);
        final previousHeight = math.min(
                math.min(330.0, viewport.height * .48) * 2,
                only ? viewport.height - 24 : viewport.height - top - 12) *
            .9;
        final previousWidth = math.min(460.0, viewport.width - 24) * .9;
        final layout = AvatarLayout.home(viewport, avatarOnly: only);
        expect(layout.height, closeTo(previousHeight * .9, .0001));
        expect(layout.width, closeTo(previousWidth * .9, .0001));
        expect(layout.top, top - 5);
      }
    }
  });
}
