/// Single source of truth for backend URLs. Set at build time:
/// flutter run --dart-define=API_BASE_URL=https://dns.yourdomain.com
class AppConfig {
  static const String baseUrl = String.fromEnvironment('API_BASE_URL');
  static String get dohUrl => '$baseUrl/dns-query';

  /// In local serverless mode, remote URL is optional.
  static void assertConfigured() {
    // No-op for local-first execution
  }
}
