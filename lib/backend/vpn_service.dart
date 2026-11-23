import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:focus_dns/shim/channel.dart';
import 'package:flutter/services.dart' hide MethodChannel;

/// FocusDnsVpnManager manages the native Android VpnService via MethodChannel.
/// Includes graceful fallback simulation for non-Android platforms (e.g. desktop/testing).
class FocusDnsVpnManager {
  static const MethodChannel _channel = MethodChannel('focus_dns/vpn');

  static bool _simulatedRunning = false;
  static final StreamController<Map<String, dynamic>> _liveQueryStreamController =
      StreamController<Map<String, dynamic>>.broadcast();

  static Stream<Map<String, dynamic>> get liveQueryStream =>
      _liveQueryStreamController.stream;


  /// Requests VPN permission from the Android system.
  /// Returns `true` if permission is granted, `false` if user denied or pending.
  static Future<bool> prepare() async {
    if (!kIsWeb && Platform.isAndroid) {
      try {
        final bool? result = await _channel.invokeMethod<bool>('prepare');
        return result ?? false;
      } on MissingPluginException {
        debugPrint('[FocusDNS VPN] Native VPN channel missing.');
        return false;
      } catch (e) {
        debugPrint('[FocusDNS VPN] Error preparing VPN: $e');
        return false;
      }
    }
    // VPN filtering is Android-only; never report fake approval.
    return false;
  }

  /// Starts the local DNS-only VPN service.
  static Future<bool> startVpn({
    String serverUrl = const String.fromEnvironment('API_BASE_URL') + '/dns-query',
    String profileId = 'local',
    String apiToken = '',
  }) async {
    if (!kIsWeb && Platform.isAndroid) {
      try {
        final prepared = await prepare();
        if (!prepared) {
          debugPrint('[FocusDNS VPN] VPN permission not granted by user.');
          return false;
        }

        final bool? result = await _channel.invokeMethod<bool>('startVpn', {
          'serverUrl': serverUrl,
          'profileId': profileId,
          'apiToken': apiToken,
        });
        return result ?? false;
      } on MissingPluginException {
        debugPrint('[FocusDNS VPN] Native VPN channel missing; VPN NOT started.');
        return false;
      } catch (e) {
        debugPrint('[FocusDNS VPN] Error starting VPN: $e');
        return false;
      }
    }

    debugPrint('[FocusDNS VPN] Unsupported platform; VPN NOT started.');
    return false;
  }

  /// Stops the local DNS-only VPN service.
  static Future<bool> stopVpn() async {
    if (!kIsWeb && Platform.isAndroid) {
      try {
        final bool? result = await _channel.invokeMethod<bool>('stopVpn');
        return result ?? false;
      } on MissingPluginException {
        _simulatedRunning = false;
        return true;
      } catch (e) {
        debugPrint('[FocusDNS VPN] Error stopping VPN: $e');
        return false;
      }
    }

    _simulatedRunning = false;
    return true;
  }

  /// Queries whether the VPN is currently active.
  static Future<bool> isRunning() async {
    if (!kIsWeb && Platform.isAndroid) {
      try {
        final bool? result = await _channel.invokeMethod<bool>('isRunning');
        return result ?? false;
      } on MissingPluginException {
        return _simulatedRunning;
      } catch (e) {
        debugPrint('[FocusDNS VPN] Error checking VPN status: $e');
        return _simulatedRunning;
      }
    }
    return _simulatedRunning;
  }

  /// Queries whether the FocusDNS backend is reachable.
  static Future<bool> isBackendReachable() async {
    if (!kIsWeb && Platform.isAndroid) {
      try {
        final bool? result = await _channel.invokeMethod<bool>('isBackendReachable');
        return result ?? true;
      } on MissingPluginException {
        return true;
      } catch (e) {
        return true;
      }
    }
    return true;
  }

  /// Retrieves real-time DNS telemetry from the native engine.
  static Future<Map<String, dynamic>> getLiveTelemetry() async {
    if (!kIsWeb && Platform.isAndroid) {
      try {
        final res = await _channel.invokeMethod<Map>('getLiveTelemetry');
        if (res != null) {
          return Map<String, dynamic>.from(res);
        }
      } catch (e) {
        debugPrint('[FocusDNS VPN] Error getting live telemetry: $e');
      }
    }
    return {
      'totalQueries': 0,
      'blockedQueries': 0,
      'blockedPercentage': '0.0%',
      'threatRatio': 0.0,
      'averageLatencyMs': 0,
      'recentQueries': <Map<String, dynamic>>[],
    };
  }

  /// Synchronizes dynamic blocked and allowed domain lists to the local VPN engine.
  static Future<bool> updateDnsRules({
    required List<String> blockedDomains,
    required List<String> allowedDomains,
    List<String> blockedCategories = const [],
    String source = 'default',
  }) async {
    if (!kIsWeb && Platform.isAndroid) {
      try {
        final bool? res = await _channel.invokeMethod<bool>('updateDnsRules', {
          'blockedDomains': blockedDomains,
          'allowedDomains': allowedDomains,
          'blockedCategories': blockedCategories,
          'source': source,
        });
        return res ?? true;
      } catch (e) {
        debugPrint('[FocusDNS VPN] Error updating DNS rules: $e');
        return false;
      }
    }
    return true;
  }

  /// Fetches paginated query logs directly from the native SQLite database.
  static Future<List<Map<String, dynamic>>> getDbLogs({
    int limit = 100,
    int offset = 0,
    String filter = 'ALL',
  }) async {
    if (!kIsWeb && Platform.isAndroid) {
      try {
        final List<dynamic>? res = await _channel.invokeMethod<List<dynamic>>('getDbLogs', {
          'limit': limit,
          'offset': offset,
          'filter': filter,
        });
        if (res != null) {
          return res.map((e) => Map<String, dynamic>.from(e as Map)).toList();
        }
      } catch (e) {
        debugPrint('[FocusDNS VPN] Error querying SQLite logs: $e');
      }
    }
    return [];
  }

  /// Clears all local DNS query history from native SQLite database.
  static Future<bool> clearDbLogs() async {
    if (!kIsWeb && Platform.isAndroid) {
      try {
        final bool? res = await _channel.invokeMethod<bool>('clearDbLogs');
        return res ?? true;
      } catch (e) {
        debugPrint('[FocusDNS VPN] Error clearing SQLite logs: $e');
        return false;
      }
    }
    return true;
  }

  /// Fetches aggregated metrics across a specified window (hours) from the native SQLite database.
  static Future<Map<String, dynamic>> getDbStats({int timeframeHours = 168}) async {
    if (!kIsWeb && Platform.isAndroid) {
      try {
        final Map? res = await _channel.invokeMethod<Map>('getDbStats', {
          'timeframeHours': timeframeHours,
        });
        if (res != null) {
          return Map<String, dynamic>.from(res);
        }
      } catch (e) {
        debugPrint('[FocusDNS VPN] Error querying SQLite stats: $e');
      }
    }
    return {
      'totalQueries': 0,
      'blockedQueries': 0,
      'blockedPercentage': '0.0%',
      'threatRatio': 0.0,
      'topBlockedDomains': <Map<String, dynamic>>[],
      'bucketTotals': <int>[],
      'bucketBlockeds': <int>[],
    };
  }

  /// Synchronizes security toggles (SafeSearch, Threat Intel, Adblock, Anti-VPN Bypass) down to native SQLite & engine.
  static Future<bool> updateSecuritySettings({
    bool? safesearch,
    bool? threatIntel,
    bool? adblock,
    bool? antiVpnBypass,
  }) async {
    if (!kIsWeb && Platform.isAndroid) {
      try {
        final bool? res = await _channel.invokeMethod<bool>('updateSecuritySettings', {
          if (safesearch != null) 'safesearch': safesearch,
          if (threatIntel != null) 'threatIntel': threatIntel,
          if (adblock != null) 'adblock': adblock,
          if (antiVpnBypass != null) 'antiVpnBypass': antiVpnBypass,
        });
        return res ?? true;
      } catch (e) {
        debugPrint('[FocusDNS VPN] Error updating security settings: $e');
        return false;
      }
    }
    return true;
  }

  /// Sets up a listener for real-time VPN and backend connectivity state changes,
  /// as well as incoming live query stream events.
  static void registerStateListener(void Function(bool isRunning, bool isBackendReachable) onStateChange) {
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'onVpnStateChanged') {
        final args = call.arguments as Map<dynamic, dynamic>?;
        final running = args?['isRunning'] as bool? ?? false;
        final reachable = args?['isBackendReachable'] as bool? ?? true;
        onStateChange(running, reachable);
      } else if (call.method == 'onLiveQuery') {
        final args = call.arguments as Map<dynamic, dynamic>?;
        if (args != null) {
          _liveQueryStreamController.add(Map<String, dynamic>.from(args));
        }
      }
    });
  }
}

