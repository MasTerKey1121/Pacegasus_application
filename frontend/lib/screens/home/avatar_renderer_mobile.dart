import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:model_viewer_plus/model_viewer_plus.dart';

class AvatarRenderer extends StatelessWidget {
  const AvatarRenderer({super.key});
  @override
  Widget build(BuildContext context) {
    if (defaultTargetPlatform != TargetPlatform.android &&
        defaultTargetPlatform != TargetPlatform.iOS) {
      return const Center(
          child: Text('โมเดล 3D ใช้ได้บนมือถือและเว็บ',
              textAlign: TextAlign.center));
    }
    return const ModelViewer(
      src: 'assets/models/pacegasus_wave_male_v8.glb',
      alt: 'Pacegasus runner',
      backgroundColor: Colors.transparent,
      ar: false,
      cameraControls: false,
      disableZoom: true,
      autoPlay: false,
      cameraOrbit: '0deg 85deg 105%',
      shadowIntensity: 0.6,
      animationCrossfadeDuration: 150,
      debugLogging: false,
      relatedJs: '''
        const avatar = document.querySelector('model-viewer');
        let started = false;
        async function greet() {
          if (started) return;
          started = true;
          avatar.animationName = 'Wave_Greeting';
          await avatar.updateComplete;
          avatar.currentTime = 0;
          avatar.play({repetitions: 1});
        }
        avatar.addEventListener('load', greet);
        avatar.addEventListener('finished', async () => {
          avatar.animationName = 'Idle_Loop';
          await avatar.updateComplete;
          avatar.currentTime = 0;
          avatar.play();
        });
        if (avatar.loaded) greet();
      ''',
    );
  }
}
