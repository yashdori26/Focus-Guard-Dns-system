import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// FocusDnsVpnManager manages the native Android VpnService via MethodChannel.
/// Includes graceful fallback simulation for non-Android platforms (e.g. desktop/testing).
class FocusDnsVpnManager {
  static const MethodChannel _channel = MethodChannel('focus_dns/vpn');

  static bool _simulatedRunning = false;

  /// Requests VPN permission from the Android system.
  /// Returns `true` if permission is granted, `false` if user denied or pending.
  static Future<bool> prepare() async {
    if (!kIsWeb && Platform.isAndroid) {
      try {
        final bool? result = await _channel.invokeMethod<bool>('prepare');
        return result ?? false;
      } on MissingPluginException {
        debugPrint('[FocusDNS VPN] MethodChannel missing, falling back to simulation.');
        return true;
      } catch (e) {
        debugPrint('[FocusDNS VPN] Error preparing VPN: $e');
        return false;
      }
    }
    // Simulated approval for non-Android platforms
    return true;
  }

  /// Starts the local DNS-only VPN service.
  static Future<bool> startVpn({
    String serverUrl = 'http://10.0.2.2:8080/dns-query',
    String profileId = 'a1b2c3',
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
        debugPrint('[FocusDNS VPN] MethodChannel missing, simulating VPN start.');
        _simulatedRunning = true;
        return true;
      } catch (e) {
        debugPrint('[FocusDNS VPN] Error starting VPN: $e');
        return false;
      }
    }

    _simulatedRunning = true;
    return true;
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

  /// Sets up a listener for real-time VPN and backend connectivity state changes.
  static void registerStateListener(void Function(bool isRunning, bool isBackendReachable) onStateChange) {
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'onVpnStateChanged') {
        final args = call.arguments as Map<dynamic, dynamic>?;
        final running = args?['isRunning'] as bool? ?? false;
        final reachable = args?['isBackendReachable'] as bool? ?? true;
        onStateChange(running, reachable);
      }
    });
  }
}
