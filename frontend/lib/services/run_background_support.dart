import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';

/// Start this location stream while the run screen is visible. Android's
/// location foreground service then keeps it running when the screen locks.
/// No always-on/background-location permission is needed for that flow.
LocationSettings runLocationSettings({TargetPlatform? platform, bool? isWeb}) {
  if (!(isWeb ?? kIsWeb) &&
      (platform ?? defaultTargetPlatform) == TargetPlatform.android) {
    return AndroidSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: 5,
      intervalDuration: const Duration(seconds: 2),
      foregroundNotificationConfig: const ForegroundNotificationConfig(
        notificationTitle: 'Pacegasus • การวิ่งกำลังทำงาน',
        notificationText:
            'ติดตามตำแหน่ง ระยะทาง และความเร็ว • แตะเพื่อกลับไปดูการวิ่ง',
        notificationChannelName: 'การติดตามการวิ่ง',
        notificationIcon:
            AndroidResource(name: 'ic_run_tracking', defType: 'drawable'),
        enableWakeLock: true,
        setOngoing: true,
      ),
    );
  }
  return const LocationSettings(
      accuracy: LocationAccuracy.high, distanceFilter: 5);
}

class RunNotificationAccess {
  static const _channel = MethodChannel('pacegasus/run_tracking');

  static bool get _android =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  static Future<bool> request() async {
    if (!_android) return true;
    try {
      return await _channel
              .invokeMethod<bool>('requestNotificationPermission') ??
          false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  static Future<void> openSettings() async {
    if (!_android) return;
    try {
      await _channel.invokeMethod<void>('openNotificationSettings');
    } on MissingPluginException {
      // A full rebuild is required after adding Android platform code.
    } on PlatformException {
      // The existing run must not be stopped by a settings-screen failure.
    }
  }
}
