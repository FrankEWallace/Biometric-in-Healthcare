/// Central application configuration.
///
/// Override API_BASE_URL at build time:
///   flutter run --dart-define=API_BASE_URL=https://api.hospital.tz/api
///   flutter build apk --dart-define=API_BASE_URL=https://api.hospital.tz/api
class AppConfig {
  AppConfig._();

  static const String baseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://192.168.100.144:8000/api',
  );
}
