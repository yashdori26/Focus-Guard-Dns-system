import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// FocusDnsBlockerManager interfaces with the native Android Accessibility Service
/// and on-device RulesStore via MethodChannel 'focus_dns/blocker'.
class FocusDnsBlockerManager {
  static const MethodChannel _channel = MethodChannel('focus_dns/blocker');

  static bool _simulatedEnabled = false;

  /// Resets simulation state (useful for test isolation).
  static void resetSimulation() => _simulatedEnabled = false;

  /// Checks if the FocusDNS Accessibility Service is enabled in Android settings.
  static Future<bool> isAccessibilityServiceEnabled() async {
    if (!kIsWeb && Platform.isAndroid) {
      try {
        final bool? result = await _channel.invokeMethod<bool>('isAccessibilityServiceEnabled');
        return result ?? false;
      } on MissingPluginException {
        return _simulatedEnabled;
      } catch (e) {
        debugPrint('[FocusDNS Blocker] Error checking accessibility status: $e');
        return _simulatedEnabled;
      }
    }
    return _simulatedEnabled;
  }

  /// Opens the Android Accessibility Settings screen.
  static Future<bool> openAccessibilitySettings() async {
    if (!kIsWeb && Platform.isAndroid) {
      try {
        final bool? result = await _channel.invokeMethod<bool>('openAccessibilitySettings');
        return result ?? false;
      } on MissingPluginException {
        _simulatedEnabled = true;
        return true;
      } catch (e) {
        debugPrint('[FocusDNS Blocker] Error opening accessibility settings: $e');
        return false;
      }
    }
    _simulatedEnabled = true;
    return true;
  }

  /// Opens the FocusDNS App Info / Details settings screen (useful for Android 13+ restricted settings).
  static Future<bool> openAppSettings() async {
    if (!kIsWeb && Platform.isAndroid) {
      try {
        final bool? result = await _channel.invokeMethod<bool>('openAppSettings');
        return result ?? false;
      } catch (e) {
        debugPrint('[FocusDNS Blocker] Error opening app settings: $e');
        return false;
      }
    }
    return true;
  }

  /// Synchronizes blocked package names with the native RulesStore.
  static Future<bool> setBlockedPackages(List<String> packages) async {
    if (!kIsWeb && Platform.isAndroid) {
      try {
        final bool? result = await _channel.invokeMethod<bool>('setBlockedPackages', {
          'packages': packages,
        });
        return result ?? false;
      } catch (e) {
        debugPrint('[FocusDNS Blocker] Error setting blocked packages: $e');
        return false;
      }
    }
    return true;
  }

  /// Synchronizes Strict Mode status with the native RulesStore.
  static Future<bool> setStrictMode(bool enabled, {int? durationMinutes}) async {
    if (!kIsWeb && Platform.isAndroid) {
      try {
        final bool? result = await _channel.invokeMethod<bool>('setStrictMode', {
          'enabled': enabled,
          if (durationMinutes != null && durationMinutes > 0) 'durationMinutes': durationMinutes,
        });
        return result ?? false;
      } catch (e) {
        debugPrint('[FocusDNS Blocker] Error setting strict mode: $e');
        return false;
      }
    }
    return true;
  }

  /// Gets the remaining seconds for timed Strict Mode from native RulesStore.
  static Future<int> getStrictRemainingSeconds() async {
    if (!kIsWeb && Platform.isAndroid) {
      try {
        final int? result = await _channel.invokeMethod<int>('getStrictRemainingSeconds');
        return result ?? 0;
      } catch (e) {
        debugPrint('[FocusDNS Blocker] Error getting remaining strict seconds: $e');
        return 0;
      }
    }
    return 0;
  }

  /// Synchronizes all rules and flags atomically to native storage.
  static Future<bool> syncRules({
    required List<String> packages,
    required bool isStrictMode,
    int? durationMinutes,
  }) async {
    if (!kIsWeb && Platform.isAndroid) {
      try {
        final bool? result = await _channel.invokeMethod<bool>('syncRules', {
          'packages': packages,
          'isStrictMode': isStrictMode,
          if (durationMinutes != null && durationMinutes > 0) 'durationMinutes': durationMinutes,
        });
        return result ?? false;
      } catch (e) {
        debugPrint('[FocusDNS Blocker] Error syncing rules: $e');
        return false;
      }
    }
    return true;
  }
}
