/// Central application configuration.
///
/// Override API_BASE_URL at build time:
///   flutter run --dart-define=API_BASE_URL=https://api.hospital.tz/api
///   flutter build apk --dart-define=API_BASE_URL=https://api.hospital.tz/api
class AppConfig {
  AppConfig._();

  static const String baseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://192.168.100.194:8000/api',
  );

  // Added to bypass ngrok's browser-interstitial page when tunnelling.
  // Safe to include in production (unknown headers are ignored).
  static const Map<String, String> defaultHeaders = {
    'Accept': 'application/json',
    'ngrok-skip-browser-warning': 'true',
  };
}
