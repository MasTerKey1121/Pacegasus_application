import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'package:flutter/material.dart';
import 'package:web/web.dart' as web;

class AvatarRenderer extends StatefulWidget {
  const AvatarRenderer({super.key, this.orbitDegrees = 0});
  final double orbitDegrees;
  @override
  State<AvatarRenderer> createState() => _AvatarRendererState();
}

class _AvatarRendererState extends State<AvatarRenderer> {
  web.HTMLElement? _element;
  JSFunction? _load, _finished, _error;
  bool _started = false, _failed = false;
  Future<void> _play(String name, {bool once = false}) async {
    final element = _element!;
    element.setAttribute('animation-name', name);
    // Lit's animation-name update resets playback options. Wait for it before
    // requesting one repetition, otherwise the greeting silently loops.
    final update = (element as JSObject)
        .getProperty<JSPromise<JSAny?>>('updateComplete'.toJS);
    await update.toDart;
    if (!mounted || _element != element) return;
    (element as JSObject).setProperty('currentTime'.toJS, 0.toJS);
    if (once) {
      (element as JSObject)
          .callMethod<JSAny?>('play'.toJS, {'repetitions': 1}.jsify());
    } else {
      (element as JSObject).callMethod<JSAny?>('play'.toJS);
    }
  }

  void _created(Object object) {
    final element = object as web.HTMLElement;
    _element = element;
    element.style.width = '100%';
    element.style.height = '100%';
    element.style.backgroundColor = 'transparent';
    element.style.pointerEvents = 'none';
    element.setAttribute(
        'src', 'assets/assets/models/pacegasus_wave_male_v8.glb');
    element.setAttribute(
        'camera-orbit', '${widget.orbitDegrees}deg 85deg 105%');
    element.setAttribute('shadow-intensity', '0.6');
    element.setAttribute('animation-crossfade-duration', '150');
    _load = ((web.Event event) {
      if (_started || !mounted) return;
      _started = true;
      _play('Wave_Greeting', once: true);
    }).toJS;
    _finished = ((web.Event event) {
      if (mounted) _play('Idle_Loop');
    }).toJS;
    _error = ((web.Event event) {
      if (mounted) setState(() => _failed = true);
    }).toJS;
    element.addEventListener('load', _load);
    element.addEventListener('finished', _finished);
    element.addEventListener('error', _error);
  }

  @override
  void didUpdateWidget(covariant AvatarRenderer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.orbitDegrees != widget.orbitDegrees) {
      _element?.setAttribute(
          'camera-orbit', '${widget.orbitDegrees}deg 85deg 105%');
    }
  }

  @override
  void dispose() {
    final element = _element;
    if (element != null) {
      element.removeEventListener('load', _load);
      element.removeEventListener('finished', _finished);
      element.removeEventListener('error', _error);
      element.removeAttribute('src');
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _failed
      ? const Center(child: Text('โหลดอวตารไม่สำเร็จ'))
      : HtmlElementView.fromTagName(
          tagName: 'model-viewer', onElementCreated: _created);
}
