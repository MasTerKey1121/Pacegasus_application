import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

Future<void> lockMobilePortrait() async {
  if (!kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS)) {
    await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  }
}

class MobilePortraitLock extends StatefulWidget {
  const MobilePortraitLock({super.key, required this.child});
  final Widget child;
  @override
  State<MobilePortraitLock> createState() => _MobilePortraitLockState();
}

class _MobilePortraitLockState extends State<MobilePortraitLock>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(lockMobilePortrait().catchError((Object _) {
        debugPrint('[Orientation] portrait request unavailable');
      }));
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
