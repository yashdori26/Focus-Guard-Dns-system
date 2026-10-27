import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

/// Manages dynamic server endpoint configuration, persistence, and connectivity testing.
/// Resolves the emulator-only 10.0.2.2 trap by allowing users to connect to custom cloud
/// domains (https://dns.example.com), local LAN IPs, or development proxies.
class ServerConfig {
  static const String _keyServerUrl = 'focusdns_custom_server_url';
  static const String _keyProfileId = 'focusdns_active_profile_id';

  final String serverUrl;
  final String activeProfileId;

  const ServerConfig({
    required this.serverUrl,
    this.activeProfileId = 'a1b2c3',
  });

  /// Default development fallback URL depending on platform
  static String get defaultServerUrl {
    if (kIsWeb) {
      return 'http://127.0.0.1:8080';
    }
    // For real physical devices or emulators, default to localhost / standard port
    return 'http://127.0.0.1:8080';
  }

  /// The normalized base URL without trailing slash or path
  String get normalizedBaseUrl {
    var url = serverUrl.trim();
    if (url.endsWith('/')) {
      url = url.substring(0, url.length - 1);
    }
    if (url.endsWith('/dns-query')) {
      url = url.replaceAll('/dns-query', '');
    }
    return url;
  }

  /// Computed RFC 8484 DNS-over-HTTPS endpoint for this server and profile
  String get dohEndpoint {
    return '$normalizedBaseUrl/dns-query?profile_id=$activeProfileId';
  }

  /// Apple iOS / macOS .mobileconfig configuration profile download URL
  String get appleMobileConfigUrl {
    return '$normalizedBaseUrl/api/profile/$activeProfileId/apple.mobileconfig';
  }

  /// Tests connectivity and latency to the configured server
  Future<ConnectionTestResult> testReachability() async {
    final stopwatch = Stopwatch()..start();
    try {
      final uri = Uri.parse('$normalizedBaseUrl/health');
      final res = await http.get(uri).timeout(const Duration(seconds: 3));
      stopwatch.stop();

      if (res.statusCode == 200) {
        return ConnectionTestResult(
          isSuccess: true,
          latencyMs: stopwatch.elapsedMilliseconds,
          message: 'Connected (HTTP 200 OK)',
        );
      } else {
        return ConnectionTestResult(
          isSuccess: false,
          latencyMs: stopwatch.elapsedMilliseconds,
          message: 'Server returned HTTP ${res.statusCode}',
        );
      }
    } catch (e) {
      stopwatch.stop();
      return ConnectionTestResult(
        isSuccess: false,
        latencyMs: stopwatch.elapsedMilliseconds,
        message: 'Unreachable: ${e.toString().split(':').last.trim()}',
      );
    }
  }

  /// Loads saved configuration from device preferences
  static Future<ServerConfig> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedUrl = prefs.getString(_keyServerUrl);
      final savedProfile = prefs.getString(_keyProfileId);

      return ServerConfig(
        serverUrl: savedUrl ?? defaultServerUrl,
        activeProfileId: savedProfile ?? 'a1b2c3',
      );
    } catch (_) {
      return ServerConfig(
        serverUrl: defaultServerUrl,
        activeProfileId: 'a1b2c3',
      );
    }
  }

  /// Saves updated configuration to device preferences
  Future<void> save() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_keyServerUrl, normalizedBaseUrl);
      await prefs.setString(_keyProfileId, activeProfileId);
    } catch (_) {}
  }

  ServerConfig copyWith({
    String? serverUrl,
    String? activeProfileId,
  }) {
    return ServerConfig(
      serverUrl: serverUrl ?? this.serverUrl,
      activeProfileId: activeProfileId ?? this.activeProfileId,
    );
  }
}

class ConnectionTestResult {
  final bool isSuccess;
  final int latencyMs;
  final String message;

  const ConnectionTestResult({
    required this.isSuccess,
    required this.latencyMs,
    required this.message,
  });
}
