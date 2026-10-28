import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Data model representing the device uninstallation and focus lock state.
class MdmLockStatus {
  final String sessionState;
  final bool isProtectionActive;
  final bool isTimerActive;
  final int remainingSeconds;
  final String formattedRemainingTime;
  final bool canUninstall;
  final bool canDeactivateAdmin;
  final bool isDeviceAdminActive;
  final bool isIntegrityValid;

  const MdmLockStatus({
    this.sessionState = 'IDLE',
    this.isProtectionActive = false,
    this.isTimerActive = false,
    this.remainingSeconds = 0,
    this.formattedRemainingTime = '00:00',
    this.canUninstall = true,
    this.canDeactivateAdmin = true,
    this.isDeviceAdminActive = false,
    this.isIntegrityValid = true,
  });

  factory MdmLockStatus.fromMap(Map<dynamic, dynamic>? map) {
    if (map == null) return const MdmLockStatus();
    return MdmLockStatus(
      sessionState: map['sessionState']?.toString() ?? 'IDLE',
      isProtectionActive: map['isProtectionActive'] == true,
      isTimerActive: map['isTimerActive'] == true,
      remainingSeconds: (map['remainingSeconds'] as num?)?.toInt() ?? 0,
      formattedRemainingTime: map['formattedRemainingTime']?.toString() ?? '00:00',
      canUninstall: map['canUninstall'] == true,
      canDeactivateAdmin: map['canDeactivateAdmin'] == true,
      isDeviceAdminActive: map['isDeviceAdminActive'] == true,
      isIntegrityValid: map['isIntegrityValid'] != false,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'sessionState': sessionState,
      'isProtectionActive': isProtectionActive,
      'isTimerActive': isTimerActive,
      'remainingSeconds': remainingSeconds,
      'formattedRemainingTime': formattedRemainingTime,
      'canUninstall': canUninstall,
      'canDeactivateAdmin': canDeactivateAdmin,
      'isDeviceAdminActive': isDeviceAdminActive,
      'isIntegrityValid': isIntegrityValid,
    };
  }
}

/// Data model representing an installed application for split-tunneling.
class SplitTunnelAppItem {
  final String packageName;
  final String appName;
  final bool isSystemApp;
  final bool isSelected;

  const SplitTunnelAppItem({
    required this.packageName,
    required this.appName,
    this.isSystemApp = false,
    this.isSelected = false,
  });

  factory SplitTunnelAppItem.fromMap(Map<dynamic, dynamic> map) {
    return SplitTunnelAppItem(
      packageName: map['packageName']?.toString() ?? '',
      appName: map['appName']?.toString() ?? '',
      isSystemApp: map['isSystemApp'] == true,
      isSelected: map['isSelected'] == true,
    );
  }
}

/// FocusMdmManager manages Device Administrator permissions, uninstallation prevention,
/// strict monotonic focus timers, and per-app split-tunneling.
class FocusMdmManager {
  static const MethodChannel _channel = MethodChannel('focus_dns/mdm');

  static bool _simulatedAdmin = false;
  static bool _simulatedProtection = false;
  static int _simulatedTimerSec = 0;
  static final List<String> _simulatedSplitApps = <String>[];

  static final StreamController<MdmLockStatus> _lockStatusController =
      StreamController<MdmLockStatus>.broadcast();

  static Stream<MdmLockStatus> get lockStatusStream => _lockStatusController.stream;

  static void initialize() {
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'onLockStatusChanged') {
        final args = call.arguments as Map<dynamic, dynamic>?;
        if (args != null) {
          _lockStatusController.add(MdmLockStatus.fromMap(args));
        }
      }
    });
  }

  /// Checks whether FocusDNS is currently an active Device Administrator.
  static Future<bool> isDeviceAdminActive() async {
    if (!kIsWeb && Platform.isAndroid) {
      try {
        final bool? result = await _channel.invokeMethod<bool>('isDeviceAdminActive');
        return result ?? false;
      } on MissingPluginException {
        return _simulatedAdmin;
      } catch (e) {
        debugPrint('[FocusDNS MDM] Error checking device admin: $e');
        return false;
      }
    }
    return _simulatedAdmin;
  }

  /// Requests the user to activate FocusDNS as a Device Administrator.
  static Future<bool> requestDeviceAdmin() async {
    if (!kIsWeb && Platform.isAndroid) {
      try {
        final bool? result = await _channel.invokeMethod<bool>('requestDeviceAdmin');
        return result ?? false;
      } on MissingPluginException {
        _simulatedAdmin = true;
        _notifySimulatedState();
        return true;
      } catch (e) {
        debugPrint('[FocusDNS MDM] Error requesting device admin: $e');
        return false;
      }
    }
    _simulatedAdmin = true;
    _notifySimulatedState();
    return true;
  }

  /// Attempts to deactivate Device Administrator privileges.
  /// Only succeeds if canUninstall / canDeactivateAdmin is TRUE.
  static Future<bool> deactivateDeviceAdmin() async {
    if (!kIsWeb && Platform.isAndroid) {
      try {
        final bool? result = await _channel.invokeMethod<bool>('deactivateDeviceAdmin');
        return result ?? false;
      } on MissingPluginException {
        if (canUninstallSynchronous()) {
          _simulatedAdmin = false;
          _notifySimulatedState();
          return true;
        }
        return false;
      } catch (e) {
        debugPrint('[FocusDNS MDM] Error deactivating device admin: $e');
        return false;
      }
    }
    if (canUninstallSynchronous()) {
      _simulatedAdmin = false;
      _notifySimulatedState();
      return true;
    }
    return false;
  }

  /// Checks if the application can currently be uninstalled.
  /// Returns TRUE if both Protection Mode is OFF and Strict Timer is 0.
  static Future<bool> canUninstall() async {
    if (!kIsWeb && Platform.isAndroid) {
      try {
        final bool? result = await _channel.invokeMethod<bool>('canUninstall');
        return result ?? true;
      } on MissingPluginException {
        return canUninstallSynchronous();
      } catch (e) {
        debugPrint('[FocusDNS MDM] Error checking canUninstall: $e');
        return true;
      }
    }
    return canUninstallSynchronous();
  }

  static bool canUninstallSynchronous() {
    return !_simulatedProtection && _simulatedTimerSec <= 0;
  }

  /// Retrieves complete real-time telemetry regarding uninstallation and focus lock state.
  static Future<MdmLockStatus> getLockStatus() async {
    if (!kIsWeb && Platform.isAndroid) {
      try {
        final Map<dynamic, dynamic>? result =
            await _channel.invokeMethod<Map<dynamic, dynamic>>('getLockStatus');
        return MdmLockStatus.fromMap(result);
      } on MissingPluginException {
        return _getSimulatedStatus();
      } catch (e) {
        debugPrint('[FocusDNS MDM] Error getting lock status: $e');
        return const MdmLockStatus();
      }
    }
    return _getSimulatedStatus();
  }

  /// Sets or clears the strict focus countdown lock timer in seconds.
  static Future<bool> setStrictLockTimer(int durationSeconds) async {
    if (!kIsWeb && Platform.isAndroid) {
      try {
        final bool? result = await _channel.invokeMethod<bool>('setStrictLockTimer', {
          'durationSeconds': durationSeconds,
        });
        return result ?? false;
      } on MissingPluginException {
        _simulatedTimerSec = durationSeconds;
        _notifySimulatedState();
        return true;
      } catch (e) {
        debugPrint('[FocusDNS MDM] Error setting strict lock timer: $e');
        return false;
      }
    }
    _simulatedTimerSec = durationSeconds;
    _notifySimulatedState();
    return true;
  }

  /// Retrieves list of all installed apps for the split-tunneling picker.
  static Future<List<SplitTunnelAppItem>> getSplitTunnelApps() async {
    if (!kIsWeb && Platform.isAndroid) {
      try {
        final List<dynamic>? result =
            await _channel.invokeMethod<List<dynamic>>('getSplitTunnelApps');
        if (result == null) return <SplitTunnelAppItem>[];
        return result
            .map((item) => SplitTunnelAppItem.fromMap(item as Map<dynamic, dynamic>))
            .toList();
      } on MissingPluginException {
        return _getSimulatedApps();
      } catch (e) {
        debugPrint('[FocusDNS MDM] Error fetching split-tunnel apps: $e');
        return _getSimulatedApps();
      }
    }
    return _getSimulatedApps();
  }

  /// Updates selected packages for split tunneling.
  static Future<bool> setSplitTunnelPackages(List<String> packages) async {
    if (!kIsWeb && Platform.isAndroid) {
      try {
        final bool? result = await _channel.invokeMethod<bool>('setSplitTunnelPackages', {
          'packages': packages,
        });
        return result ?? false;
      } on MissingPluginException {
        _simulatedSplitApps.clear();
        _simulatedSplitApps.addAll(packages);
        return true;
      } catch (e) {
        debugPrint('[FocusDNS MDM] Error setting split-tunnel packages: $e');
        return false;
      }
    }
    _simulatedSplitApps.clear();
    _simulatedSplitApps.addAll(packages);
    return true;
  }

  /// Updates split tunneling mode ('disallow_list' or 'allow_list').
  static Future<bool> setSplitTunnelMode(String mode) async {
    if (!kIsWeb && Platform.isAndroid) {
      try {
        final bool? result = await _channel.invokeMethod<bool>('setSplitTunnelMode', {
          'mode': mode,
        });
        return result ?? false;
      } catch (e) {
        debugPrint('[FocusDNS MDM] Error setting split-tunnel mode: $e');
        return false;
      }
    }
    return true;
  }

  // --- Simulation Helpers for Desktop / Tests ---

  static void setSimulatedProtection(bool active) {
    _simulatedProtection = active;
    _notifySimulatedState();
  }

  static void setSimulatedTimer(int seconds) {
    _simulatedTimerSec = seconds;
    _notifySimulatedState();
  }

  static MdmLockStatus _getSimulatedStatus() {
    final canUn = canUninstallSynchronous();
    final state = (_simulatedProtection && _simulatedTimerSec > 0)
        ? 'LOCKED_PROTECTED'
        : (_simulatedTimerSec > 0)
            ? 'TIMER_ACTIVE'
            : (_simulatedProtection)
                ? 'PROTECTION_ONLY'
                : 'IDLE';

    final minutes = (_simulatedTimerSec % 3600) ~/ 60;
    final secs = _simulatedTimerSec % 60;
    final formatted =
        '${minutes.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}';

    return MdmLockStatus(
      sessionState: state,
      isProtectionActive: _simulatedProtection,
      isTimerActive: _simulatedTimerSec > 0,
      remainingSeconds: _simulatedTimerSec,
      formattedRemainingTime: formatted,
      canUninstall: canUn,
      canDeactivateAdmin: canUn,
      isDeviceAdminActive: _simulatedAdmin,
      isIntegrityValid: true,
    );
  }

  static void _notifySimulatedState() {
    _lockStatusController.add(_getSimulatedStatus());
  }

  static List<SplitTunnelAppItem> _getSimulatedApps() {
    return <SplitTunnelAppItem>[
      SplitTunnelAppItem(
        packageName: 'com.google.android.apps.nbu.paisa.user',
        appName: 'Google Pay',
        isSystemApp: false,
        isSelected: _simulatedSplitApps.contains('com.google.android.apps.nbu.paisa.user'),
      ),
      SplitTunnelAppItem(
        packageName: 'com.sbi.lotusintouch',
        appName: 'YONO SBI',
        isSystemApp: false,
        isSelected: _simulatedSplitApps.contains('com.sbi.lotusintouch'),
      ),
      SplitTunnelAppItem(
        packageName: 'com.android.chrome',
        appName: 'Chrome',
        isSystemApp: true,
        isSelected: _simulatedSplitApps.contains('com.android.chrome'),
      ),
    ];
  }
}
