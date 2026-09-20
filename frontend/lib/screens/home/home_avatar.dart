import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:model_viewer_plus/model_viewer_plus.dart';
import '../../providers/avatar_provider.dart';

typedef AvatarViewerBuilder = Widget Function(
    RunnerShirt shirt, RunnerStage stage, bool animate, bool interactive);

/// A replaceable rendering boundary allows widget tests without a platform view.
final avatarViewerBuilderProvider = Provider<AvatarViewerBuilder>((ref) {
  return (shirt, stage, animate, interactive) {
    if (!kIsWeb &&
        defaultTargetPlatform != TargetPlatform.android &&
        defaultTargetPlatform != TargetPlatform.iOS) {
      return Image.asset(shirt.previewAsset(stage), fit: BoxFit.contain);
    }
    return ModelViewer(
      key: ValueKey('${shirt.name}-${stage.name}-$animate-$interactive'),
      src: kIsWeb
          ? 'assets/${shirt.modelAsset(stage)}'
          : shirt.modelAsset(stage),
      alt: 'อวตารนักวิ่ง เสื้อ${shirt.label}',
      loading: Loading.eager,
      autoPlay: animate,
      cameraControls: interactive,
      disableZoom: true,
      disablePan: true,
      interactionPrompt: InteractionPrompt.none,
      cameraOrbit: '0deg 78deg 140%',
      cameraTarget: 'auto auto auto',
      fieldOfView: '35deg',
      minCameraOrbit: 'auto 65deg auto',
      maxCameraOrbit: 'auto 100deg 200%',
      shadowIntensity: .6,
      exposure: 1.1,
      ar: false,
      debugLogging: false,
    );
  };
});

class HomeAvatar extends ConsumerWidget {
  const HomeAvatar({super.key, this.interactive = false});
  final bool interactive;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final wardrobe = ref.watch(avatarProvider);
    final animate = wardrobe.motion &&
        !MediaQuery.disableAnimationsOf(context) &&
        TickerMode.valuesOf(context).enabled &&
        (ModalRoute.of(context)?.isCurrent ?? true);
    return Semantics(
      label: 'อวตารนักวิ่ง เสื้อ${wardrobe.shirt.label}',
      child: IgnorePointer(
        ignoring: !interactive,
        child: ref.watch(avatarViewerBuilderProvider)(
            wardrobe.shirt, wardrobe.stage, animate, interactive),
      ),
    );
  }
}
