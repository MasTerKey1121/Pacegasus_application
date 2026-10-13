import 'package:flutter/foundation.dart';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:model_viewer_plus/model_viewer_plus.dart';
import 'package:webview_flutter/webview_flutter.dart';

class AvatarRenderer extends StatefulWidget {
  const AvatarRenderer({super.key, this.orbitDegrees = 0, this.variantName});
  final double orbitDegrees;
  final String? variantName;
  @override
  State<AvatarRenderer> createState() => _AvatarRendererState();
}

class _AvatarRendererState extends State<AvatarRenderer> {
  WebViewController? _controller;
  void _applyVariant() {
    _controller?.runJavaScript(
        "(() => { const model = document.querySelector('model-viewer'); if (model) model.variantName = ${jsonEncode(widget.variantName)}; })();");
  }

  @override
  void didUpdateWidget(covariant AvatarRenderer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.variantName != oldWidget.variantName) {
      _applyVariant();
    }
    if (widget.orbitDegrees != oldWidget.orbitDegrees) {
      _controller?.runJavaScript(
          "document.querySelector('model-viewer')?.setAttribute('camera-orbit', '${widget.orbitDegrees}deg 85deg 105%');");
    }
  }

  @override
  Widget build(BuildContext context) {
    if (defaultTargetPlatform != TargetPlatform.android &&
        defaultTargetPlatform != TargetPlatform.iOS) {
      return const Center(
          child: Text('โมเดล 3D ใช้ได้บนมือถือและเว็บ',
              textAlign: TextAlign.center));
    }
    return ModelViewer(
      src: 'assets/models/pacegasus_starter_v9.glb',
      variantName: widget.variantName,
      alt: 'Pacegasus runner',
      backgroundColor: Colors.transparent,
      ar: false,
      cameraControls: false,
      disableZoom: true,
      autoPlay: false,
      cameraOrbit: '${widget.orbitDegrees}deg 85deg 105%',
      onWebViewCreated: (controller) => _controller = controller,
      javascriptChannels: {
        JavascriptChannel(
            'AvatarReady',
            onMessageReceived: (_) {
              if (mounted) _applyVariant();
            }),
      },
      shadowIntensity: 0.6,
      animationCrossfadeDuration: 150,
      debugLogging: false,
      relatedJs: '''
        const avatar = document.querySelector('model-viewer');
        let started = false;
        async function greet() {
          if (started) return;
          started = true;
          window.AvatarReady?.postMessage('loaded');
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
