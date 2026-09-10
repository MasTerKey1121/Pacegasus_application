import 'dart:io' show Platform;

class ApiConfig {
  /// Override for a deployed server or a device on the same Wi-Fi, for example:
  /// flutter run --dart-define=API_BASE_URL=http://192.168.1.20:4000
  static const _configuredBaseUrl = String.fromEnvironment('API_BASE_URL');

  static List<String> get baseUrls {
    if (_configuredBaseUrl.isNotEmpty) return [_configuredBaseUrl];
    if (Platform.isAndroid) {
      return const [
        // Physical Android devices connected with:
        // adb reverse tcp:4000 tcp:4000
        'http://127.0.0.1:4000',
        // Android Emulator host alias.
        'http://10.0.2.2:4000',
      ];
    }
    return const ['http://localhost:4000'];
  }

  static String get baseUrl => baseUrls.first;
}
