import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'oem_device_profiles.dart';
import 'oem_troubleshooting_guides.dart';

/// Comprehensive hardware & OS identity probe result.
@immutable
class DeviceHardwareProbe {
  final String manufacturer;
  final String brand;
  final String model;
  final String hardware;
  final String buildFingerprint;
  final String romVersion;
  final int sdkInt;
  final bool isDozeExempted;
  final bool isAutostartGranted;
  final bool isLockedInRecents;

  const DeviceHardwareProbe({
    required this.manufacturer,
    required this.brand,
    required this.model,
    required this.hardware,
    required this.buildFingerprint,
    required this.romVersion,
    required this.sdkInt,
    this.isDozeExempted = false,
    this.isAutostartGranted = false,
    this.isLockedInRecents = false,
  });

  factory DeviceHardwareProbe.mockGeneric() => const DeviceHardwareProbe(
        manufacturer: 'Google',
        brand: 'Pixel',
        model: 'Pixel 8 Pro',
        hardware: 'husky',
        buildFingerprint: 'google/husky/husky:14/UD1A.230803.041/10548480:user/release-keys',
        romVersion: 'Stock Android 14',
        sdkInt: 34,
        isDozeExempted: true,
        isAutostartGranted: true,
        isLockedInRecents: true,
      );

  factory DeviceHardwareProbe.mockXiaomi() => const DeviceHardwareProbe(
        manufacturer: 'Xiaomi',
        brand: 'Redmi',
        model: 'Redmi Note 13 Pro',
        hardware: 'garnet',
        buildFingerprint: 'Redmi/garnet_eea/garnet:14/UKQ1.231003.002/V816.0.4.0.UNREUXM:user/release-keys',
        romVersion: 'HyperOS 1.0.4.0',
        sdkInt: 34,
        isDozeExempted: false,
        isAutostartGranted: false,
        isLockedInRecents: false,
      );

  factory DeviceHardwareProbe.mockSamsung() => const DeviceHardwareProbe(
        manufacturer: 'Samsung',
        brand: 'Samsung',
        model: 'Galaxy S24 Ultra',
        hardware: 'qcom',
        buildFingerprint: 'samsung/e3qxxx/e3q:14/UP1A.231005.007/S928BXXU1AXB5:user/release-keys',
        romVersion: 'One UI 6.1',
        sdkInt: 34,
        isDozeExempted: false,
        isAutostartGranted: false,
        isLockedInRecents: false,
      );
}

/// Registry and dynamic resolver for device hardware OEM characteristics.
class OemRegistry extends ChangeNotifier {
  static const MethodChannel _channel = MethodChannel('com.focusdns.app/oem_battery');

  DeviceHardwareProbe? _probe;
  OemDeviceProfile? _resolvedProfile;
  OemTroubleshootingGuide? _resolvedGuide;
  bool _isLoading = false;

  OemRegistry({DeviceHardwareProbe? initialProbe}) {
    if (initialProbe != null) {
      _setProbe(initialProbe);
    }
  }

  DeviceHardwareProbe get probe => _probe ?? DeviceHardwareProbe.mockGeneric();
  OemDeviceProfile get currentProfile => _resolvedProfile ?? OemDeviceProfiles.genericAosp;
  OemTroubleshootingGuide get currentGuide => _resolvedGuide ?? OemTroubleshootingGuides.pixel;
  bool get isLoading => _isLoading;

  void _setProbe(DeviceHardwareProbe probe) {
    _probe = probe;
    _resolvedProfile = OemDeviceProfiles.resolveProfile(
      manufacturer: probe.manufacturer,
      brand: probe.brand,
    );
    _resolvedGuide = OemTroubleshootingGuides.getGuide(_resolvedProfile!.family);
    notifyListeners();
  }

  /// Sets an explicit probe for unit testing and CI simulation.
  @visibleForTesting
  void setProbeForTesting(DeviceHardwareProbe probe) {
    _setProbe(probe);
  }

  /// Performs device detection via platform channel or fallback mock.
  Future<void> detectDevice() async {
    _isLoading = true;
    notifyListeners();

    try {
      final dynamic raw = await _channel.invokeMethod('getDeviceHardwareInfo');
      if (raw is Map) {
        final probe = DeviceHardwareProbe(
          manufacturer: raw['manufacturer']?.toString() ?? 'Generic',
          brand: raw['brand']?.toString() ?? 'Android',
          model: raw['model']?.toString() ?? 'Device',
          hardware: raw['hardware']?.toString() ?? 'unknown',
          buildFingerprint: raw['fingerprint']?.toString() ?? '',
          romVersion: raw['romVersion']?.toString() ?? 'Android',
          sdkInt: (raw['sdkInt'] as num?)?.toInt() ?? 33,
          isDozeExempted: raw['isDozeExempted'] == true,
          isAutostartGranted: raw['isAutostartGranted'] == true,
          isLockedInRecents: raw['isLockedInRecents'] == true,
        );
        _setProbe(probe);
      } else {
        _setProbe(DeviceHardwareProbe.mockGeneric());
      }
    } catch (_) {
      // Running on test harness or unsupported environment
      _setProbe(_probe ?? DeviceHardwareProbe.mockGeneric());
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Calculates dynamic survivability score (0 - 100) based on verified exemptions.
  int calculateSurvivabilityScore() {
    final profile = currentProfile;
    final probe = this.probe;

    int score = profile.defaultSurvivalScore;

    if (probe.isDozeExempted) {
      score += 30;
    }

    if (profile.requiresAutostartPermission && probe.isAutostartGranted) {
      score += 25;
    } else if (!profile.requiresAutostartPermission) {
      score += 15;
    }

    if (probe.isLockedInRecents) {
      score += 15;
    }

    if (score > 100) score = 100;
    if (score < 0) score = 0;
    return score;
  }

  /// Dispatches the appropriate native intent to launch the OEM settings activity.
  Future<bool> launchOemSettingsTarget(OemActivityTarget target) async {
    try {
      final result = await _channel.invokeMethod<bool>('launchOemActivity', {
        'packageName': target.packageName,
        'activityName': target.activityName,
        'action': target.action,
        'extras': target.extras,
      });
      return result ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Launches the primary autostart configuration activity for the active OEM.
  Future<bool> launchPrimaryAutostart() async {
    final targets = currentProfile.autostartTargets;
    if (targets.isEmpty) {
      return launchStandardBatteryOptimization();
    }
    for (final target in targets) {
      final success = await launchOemSettingsTarget(target);
      if (success) return true;
    }
    return launchStandardBatteryOptimization();
  }

  /// Launches the primary battery optimization exemption activity.
  Future<bool> launchPrimaryBatteryOptimization() async {
    final targets = currentProfile.batteryOptimizationTargets;
    for (final target in targets) {
      final success = await launchOemSettingsTarget(target);
      if (success) return true;
    }
    return launchStandardBatteryOptimization();
  }

  /// Dispatches standard AOSP battery optimization exemption intent.
  Future<bool> launchStandardBatteryOptimization() async {
    try {
      final result = await _channel.invokeMethod<bool>('requestStandardBatteryOptimization');
      return result ?? false;
    } catch (_) {
      return false;
    }
  }
}
