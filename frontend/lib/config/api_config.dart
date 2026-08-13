import 'dart:io' show Platform;

class ApiConfig {
  /// Override for a physical device, for example:
  /// flutter run --dart-define=API_BASE_URL=http://192.168.1.20:4000
  static const _configuredBaseUrl = String.fromEnvironment('API_BASE_URL');

  static String get baseUrl {
    if (_configuredBaseUrl.isNotEmpty) return _configuredBaseUrl;
    // Android emulator reaches the host computer through this special address.
    if (Platform.isAndroid) return 'http://10.0.2.2:4000';
    return 'http://localhost:4000';
  }
}
