import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:focus_dns/shim/channel.dart';
import 'package:flutter/services.dart' hide MethodChannel;

/// FocusDnsBlockerManager interfaces with the native Android Accessibility Service
/// and on-device RulesStore via MethodChannel 'focus_dns/blocker'.
class FocusDnsBlockerManager {
  static const MethodChannel _channel = MethodChannel('focus_dns/blocker');

  static bool _simulatedEnabled = false;
  static bool _simulatedNotificationsGranted = false;
  static bool _simulatedBatteryIgnored = false;

  /// Resets simulation state (useful for test isolation).
  static void resetSimulation() {
    _simulatedEnabled = false;
    _simulatedNotificationsGranted = false;
    _simulatedBatteryIgnored = false;
  }

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
  static Future<bool> setBlockedPackages(List<String> packages, {String source = 'default'}) async {
    if (!kIsWeb && Platform.isAndroid) {
      try {
        final bool? result = await _channel.invokeMethod<bool>('setBlockedPackages', {
          'packages': packages,
          'source': source,
        });
        return result ?? false;
      } catch (e) {
        debugPrint('[FocusDNS Blocker] Error setting blocked packages: $e');
        return false;
      }
    }
    return true;
  }

  /// Explicitly sets the protection state in the native RulesStore and Accessibility service.
  /// When enabled=false, all app and domain blocking is paused.
  static Future<bool> setProtectionEnabled(bool enabled) async {
    if (!kIsWeb && Platform.isAndroid) {
      try {
        final bool? result = await _channel.invokeMethod<bool>('setProtectionEnabled', {
          'enabled': enabled,
        });
        return result ?? false;
      } catch (e) {
        debugPrint('[FocusDNS Blocker] Error setting protection enabled: $e');
        return false;
      }
    }
    return true;
  }

  /// Synchronizes blocked categories (e.g. porn, gambling) with the native RulesStore.
  /// Turns native Reels/Shorts feed blocking on/off (Accessibility service).
  static Future<bool> setFeedFilters({required bool instagramReels, required bool youtubeShorts}) async {
    if (!kIsWeb && Platform.isAndroid) {
      try {
        final bool? result = await _channel.invokeMethod<bool>('setFeedFilters', {
          'instagramReels': instagramReels,
          'youtubeShorts': youtubeShorts,
        });
        return result ?? false;
      } catch (e) {
        debugPrint('[FocusDNS Blocker] Error setting feed filters: $e');
        return false;
      }
    }
    return true;
  }

  static Future<bool> setBlockedCategories(List<String> categories) async {
    if (!kIsWeb && Platform.isAndroid) {
      try {
        final bool? result = await _channel.invokeMethod<bool>('setBlockedCategories', {
          'categories': categories,
        });
        return result ?? false;
      } catch (e) {
        debugPrint('[FocusDNS Blocker] Error setting blocked categories: $e');
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
    List<String>? packages,
    required bool isStrictMode,
    int? durationMinutes,
  }) async {
    if (!kIsWeb && Platform.isAndroid) {
      try {
        final Map<String, dynamic> args = {
          'isStrictMode': isStrictMode,
          if (durationMinutes != null && durationMinutes > 0) 'durationMinutes': durationMinutes,
        };
        if (packages != null) {
          args['packages'] = packages;
        }
        final bool? result = await _channel.invokeMethod<bool>('syncRules', args);
        return result ?? false;
      } catch (e) {
        debugPrint('[FocusDNS Blocker] Error syncing rules: $e');
        return false;
      }
    }
    return true;
  }

  /// Closes any active blocked foreground app by commanding native Accessibility or Intent.
  static Future<bool> closeActiveBlockedApp() async {
    if (!kIsWeb && Platform.isAndroid) {
      try {
        final bool? result = await _channel.invokeMethod<bool>('closeActiveBlockedApp');
        return result ?? false;
      } catch (e) {
        debugPrint('[FocusDNS Blocker] Error closing active blocked app: $e');
        return false;
      }
    }
    return true;
  }

  /// Checks whether FocusDNS is exempted from battery optimizations (Doze mode).
  static Future<bool> isBatteryOptimizationIgnored() async {
    if (!kIsWeb && Platform.isAndroid) {
      try {
        final bool? result = await _channel.invokeMethod<bool>('isBatteryOptimizationIgnored');
        return result ?? false;
      } on MissingPluginException {
        return _simulatedBatteryIgnored;
      } catch (e) {
        debugPrint('[FocusDNS Blocker] Error checking battery optimization: $e');
        return _simulatedBatteryIgnored;
      }
    }
    return _simulatedBatteryIgnored;
  }

  /// Requests exemption from battery optimizations (Doze mode) for zero-battery background operation.
  static Future<bool> requestIgnoreBatteryOptimizations() async {
    if (!kIsWeb && Platform.isAndroid) {
      try {
        final bool? result = await _channel.invokeMethod<bool>('requestIgnoreBatteryOptimizations');
        return result ?? false;
      } on MissingPluginException {
        _simulatedBatteryIgnored = true;
        return true;
      } catch (e) {
        debugPrint('[FocusDNS Blocker] Error requesting battery optimization ignore: $e');
        return false;
      }
    }
    _simulatedBatteryIgnored = true;
    return true;
  }

  /// Checks whether notification permission is granted.
  static Future<bool> isNotificationPermissionGranted() async {
    if (!kIsWeb && Platform.isAndroid) {
      try {
        final bool? result = await _channel.invokeMethod<bool>('isNotificationPermissionGranted');
        return result ?? false;
      } on MissingPluginException {
        return _simulatedNotificationsGranted;
      } catch (e) {
        debugPrint('[FocusDNS Blocker] Error checking notification permission: $e');
        return _simulatedNotificationsGranted;
      }
    }
    return _simulatedNotificationsGranted;
  }

  /// Requests notification permission from Android.
  static Future<bool> requestNotificationPermission() async {
    if (!kIsWeb && Platform.isAndroid) {
      try {
        final bool? result = await _channel.invokeMethod<bool>('requestNotificationPermission');
        return result ?? false;
      } on MissingPluginException {
        _simulatedNotificationsGranted = true;
        return true;
      } catch (e) {
        debugPrint('[FocusDNS Blocker] Error requesting notification permission: $e');
        return false;
      }
    }
    _simulatedNotificationsGranted = true;
    return true;
  }

  /// Checks whether Device Administrator privileges are active.
  static Future<bool> isDeviceAdminActive() async {
    if (!kIsWeb && Platform.isAndroid) {
      try {
        final bool? result = await _channel.invokeMethod<bool>('isDeviceAdminActive');
        return result ?? false;
      } catch (e) {
        debugPrint('[FocusDNS Blocker] Error checking device admin: $e');
        return false;
      }
    }
    return false;
  }

  /// Prompts the user to activate Device Administrator privileges.
  static Future<bool> requestDeviceAdmin() async {
    if (!kIsWeb && Platform.isAndroid) {
      try {
        final bool? result = await _channel.invokeMethod<bool>('requestDeviceAdmin');
        return result ?? false;
      } catch (e) {
        debugPrint('[FocusDNS Blocker] Error requesting device admin: $e');
        return false;
      }
    }
    return false;
  }

  /// Deactivates Device Administrator privileges if no strict countdown is active.
  static Future<bool> removeDeviceAdmin() async {
    if (!kIsWeb && Platform.isAndroid) {
      try {
        final bool? result = await _channel.invokeMethod<bool>('removeDeviceAdmin');
        return result ?? false;
      } catch (e) {
        debugPrint('[FocusDNS Blocker] Error removing device admin: $e');
        return false;
      }
    }
    return false;
  }

  /// Persists a key-value pair to the native SQLite LocalDb.
  static Future<bool> putKv(String key, String value) async {
    if (!kIsWeb && Platform.isAndroid) {
      try {
        final bool? result = await _channel.invokeMethod<bool>('putKv', {
          'key': key,
          'value': value,
        });
        return result ?? false;
      } catch (e) {
        debugPrint('[FocusDNS Blocker] Error putKv: $e');
        return false;
      }
    }
    return true;
  }

  /// Retrieves a value by key from the native SQLite LocalDb.
  static Future<String> getKv(String key, [String defaultValue = '']) async {
    if (!kIsWeb && Platform.isAndroid) {
      try {
        final String? result = await _channel.invokeMethod<String>('getKv', {
          'key': key,
          'default': defaultValue,
        });
        return result ?? defaultValue;
      } catch (e) {
        debugPrint('[FocusDNS Blocker] Error getKv: $e');
        return defaultValue;
      }
    }
    return defaultValue;
  }
}


