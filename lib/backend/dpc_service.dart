import 'dart:async';
import 'package:flutter/services.dart';

/// Diagnostic model representing Android Enterprise Device Policy Controller (DPC) posture.
class DpcDiagnosticModel {
  final bool isDeviceOwner;
  final bool isProfileOwner;
  final bool isEnterpriseDpcActive;
  final bool canUninstallApp;
  final Map<String, bool> activeRestrictions;
  final bool coreRestrictionsEnforced;

  const DpcDiagnosticModel({
    this.isDeviceOwner = false,
    this.isProfileOwner = false,
    this.isEnterpriseDpcActive = false,
    this.canUninstallApp = true,
    this.activeRestrictions = const {},
    this.coreRestrictionsEnforced = false,
  });

  factory DpcDiagnosticModel.fromMap(Map<dynamic, dynamic> map) {
    final rawRestrictions = map['activeRestrictions'] as Map<dynamic, dynamic>? ?? {};
    final parsedRestrictions = rawRestrictions.map(
      (k, v) => MapEntry(k.toString(), v == true),
    );

    return DpcDiagnosticModel(
      isDeviceOwner: map['isDeviceOwner'] == true,
      isProfileOwner: map['isProfileOwner'] == true,
      isEnterpriseDpcActive: map['isEnterpriseDpcActive'] == true,
      canUninstallApp: map['canUninstallApp'] != false,
      activeRestrictions: parsedRestrictions,
      coreRestrictionsEnforced: map['coreRestrictionsEnforced'] == true,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'isDeviceOwner': isDeviceOwner,
      'isProfileOwner': isProfileOwner,
      'isEnterpriseDpcActive': isEnterpriseDpcActive,
      'canUninstallApp': canUninstallApp,
      'activeRestrictions': activeRestrictions,
      'coreRestrictionsEnforced': coreRestrictionsEnforced,
    };
  }
}

/// Model representing Android Enterprise Managed Configurations (AppConfig).
class ManagedConfigModel {
  final String serverUrl;
  final String tenantId;
  final String enrollmentToken;
  final bool enforceStrictUninstallLock;
  final List<String> whitelistedPackages;
  final bool kioskEnabled;
  final String approvedDotHost;

  const ManagedConfigModel({
    this.serverUrl = 'https://dns.focusguard.internal',
    this.tenantId = 'default_enterprise',
    this.enrollmentToken = '',
    this.enforceStrictUninstallLock = false,
    this.whitelistedPackages = const [],
    this.kioskEnabled = false,
    this.approvedDotHost = '',
  });

  factory ManagedConfigModel.fromMap(Map<dynamic, dynamic> map) {
    final rawPkgs = (map['whitelisted_split_tunnel_pkgs'] ?? map['whitelistedPackages']) as List<dynamic>? ?? [];
    return ManagedConfigModel(
      serverUrl: (map['server_url'] ?? map['serverUrl'] ?? 'https://dns.focusguard.internal').toString(),
      tenantId: (map['tenant_id'] ?? map['tenantId'] ?? 'default_enterprise').toString(),
      enrollmentToken: (map['enrollment_token'] ?? map['enrollmentToken'] ?? '').toString(),
      enforceStrictUninstallLock: map['enforce_strict_uninstall_lock'] == true || map['enforceStrictUninstallLock'] == true,
      whitelistedPackages: rawPkgs.map((e) => e.toString()).toList(),
      kioskEnabled: map['lock_task_kiosk_enabled'] == true || map['kioskEnabled'] == true,
      approvedDotHost: (map['approved_dot_host'] ?? map['approvedDotHost'] ?? '').toString(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'serverUrl': serverUrl,
      'tenantId': tenantId,
      'enrollmentToken': enrollmentToken,
      'enforceStrictUninstallLock': enforceStrictUninstallLock,
      'whitelistedPackages': whitelistedPackages,
      'kioskEnabled': kioskEnabled,
      'approvedDotHost': approvedDotHost,
    };
  }
}

/// Service managing DPC operations, LockTask kiosk mode, and Managed Configurations.
class FocusDpcService {
  static const MethodChannel _channel = MethodChannel('focus_dns/mdm');

  // Simulation state for desktop and test runs
  static bool _simulatedDeviceOwner = false;
  static bool _simulatedProfileOwner = false;
  static bool _simulatedKioskActive = false;
  static ManagedConfigModel _simulatedConfig = const ManagedConfigModel();

  static void setSimulatedState({
    bool? isDeviceOwner,
    bool? isProfileOwner,
    bool? isKioskActive,
    ManagedConfigModel? config,
  }) {
    if (isDeviceOwner != null) _simulatedDeviceOwner = isDeviceOwner;
    if (isProfileOwner != null) _simulatedProfileOwner = isProfileOwner;
    if (isKioskActive != null) _simulatedKioskActive = isKioskActive;
    if (config != null) _simulatedConfig = config;
  }

  /// Checks if FocusDNS is Android Enterprise Device Owner.
  static Future<bool> isDeviceOwner() async {
    try {
      final res = await _channel.invokeMethod<bool>('isDeviceOwner');
      if (res != null) return res;
    } catch (_) {}
    return _simulatedDeviceOwner;
  }

  /// Checks if FocusDNS is Profile Owner.
  static Future<bool> isProfileOwner() async {
    try {
      final res = await _channel.invokeMethod<bool>('isProfileOwner');
      if (res != null) return res;
    } catch (_) {}
    return _simulatedProfileOwner;
  }

  /// Retrieves deep diagnostic report of DPC posture.
  static Future<DpcDiagnosticModel> getDpcDiagnostics() async {
    try {
      final res = await _channel.invokeMethod<Map<dynamic, dynamic>>('getDpcDiagnostics');
      if (res != null) {
        return DpcDiagnosticModel.fromMap(res);
      }
    } catch (_) {}

    return DpcDiagnosticModel(
      isDeviceOwner: _simulatedDeviceOwner,
      isProfileOwner: _simulatedProfileOwner,
      isEnterpriseDpcActive: _simulatedDeviceOwner || _simulatedProfileOwner,
      canUninstallApp: !_simulatedDeviceOwner,
      activeRestrictions: {
        'no_uninstall_apps': _simulatedDeviceOwner,
        'no_safe_boot': _simulatedDeviceOwner,
        'no_config_vpn': _simulatedDeviceOwner,
      },
      coreRestrictionsEnforced: _simulatedDeviceOwner,
    );
  }

  /// Applies conditional user restrictions based on protection state.
  static Future<Map<String, bool>> applyConditionalFocusPolicy(bool isProtected) async {
    try {
      final res = await _channel.invokeMethod<Map<dynamic, dynamic>>(
        'applyConditionalFocusPolicy',
        {'isProtected': isProtected},
      );
      if (res != null) {
        return res.map((k, v) => MapEntry(k.toString(), v == true));
      }
    } catch (_) {}
    return {
      'no_uninstall_apps': isProtected,
      'no_safe_boot': isProtected,
      'no_config_vpn': isProtected,
    };
  }

  /// Enables or disables USB debugging (ADB).
  static Future<bool> setUsbDebuggingDisabled(bool disabled) async {
    try {
      final res = await _channel.invokeMethod<bool>(
        'setUsbDebuggingDisabled',
        {'disabled': disabled},
      );
      if (res != null) return res;
    } catch (_) {}
    return true;
  }

  /// Starts LockTask Kiosk Mode for strict containment.
  static Future<bool> startKioskMode({List<String> packages = const []}) async {
    try {
      final res = await _channel.invokeMethod<bool>('startKioskMode', {'packages': packages});
      if (res != null) return res;
    } catch (_) {}
    _simulatedKioskActive = true;
    return true;
  }

  /// Stops LockTask Kiosk Mode.
  static Future<bool> stopKioskMode() async {
    try {
      final res = await _channel.invokeMethod<bool>('stopKioskMode');
      if (res != null) return res;
    } catch (_) {}
    _simulatedKioskActive = false;
    return true;
  }

  /// Checks if LockTask Kiosk Mode is currently running.
  static Future<bool> isKioskModeActive() async {
    try {
      final res = await _channel.invokeMethod<bool>('isKioskModeActive');
      if (res != null) return res;
    } catch (_) {}
    return _simulatedKioskActive;
  }

  /// Retrieves Android Enterprise Managed Configurations.
  static Future<ManagedConfigModel> getManagedConfiguration() async {
    try {
      final res = await _channel.invokeMethod<Map<dynamic, dynamic>>('getManagedConfiguration');
      if (res != null) {
        return ManagedConfigModel.fromMap(res);
      }
    } catch (_) {}
    return _simulatedConfig;
  }

  /// Parses Android Enterprise Zero-Touch QR Code JSON.
  static ZeroTouchPayloadModel parseZeroTouchPayload(Map<String, dynamic> json) {
    return ZeroTouchPayloadModel.fromJson(json);
  }

  /// Generates a valid Android Enterprise enrollment bundle.
  static ZeroTouchPayloadModel createDefaultZeroTouchBundle({
    String tenantId = 'default_enterprise',
    String serverUrl = 'https://dns.focusguard.internal',
    String? token,
    bool enforceStrictUninstallLock = false,
  }) {
    return ZeroTouchPayloadModel(
      packageName: 'com.focusdns.app',
      componentName: 'com.focusdns.app/.FocusDeviceAdminReceiver',
      signatureChecksum: '4a24cd80388b818606eb02eb55b650c4035787207dd6551724d2968a07a9e163',
      adminExtras: ManagedConfigModel(
        tenantId: tenantId,
        serverUrl: serverUrl,
        enrollmentToken: token ?? '',
        enforceStrictUninstallLock: enforceStrictUninstallLock,
      ),
    );
  }
}

/// Wi-Fi configuration extracted from Zero-Touch QR Code.
class WifiConfigModel {
  final String? ssid;
  final String? password;
  final String securityType;
  final bool hidden;

  const WifiConfigModel({
    this.ssid,
    this.password,
    this.securityType = 'WPA',
    this.hidden = false,
  });

  factory WifiConfigModel.fromMap(Map<dynamic, dynamic> map) {
    return WifiConfigModel(
      ssid: map['ssid']?.toString(),
      password: map['password']?.toString(),
      securityType: map['securityType']?.toString() ?? 'WPA',
      hidden: map['hidden'] == true,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      if (ssid != null) 'ssid': ssid,
      if (password != null) 'password': password,
      'securityType': securityType,
      'hidden': hidden,
    };
  }
}

/// Android Enterprise Zero-Touch QR Code enrollment payload model.
class ZeroTouchPayloadModel {
  final String packageName;
  final String componentName;
  final String? downloadLocation;
  final String? signatureChecksum;
  final WifiConfigModel? wifiConfig;
  final ManagedConfigModel adminExtras;
  final String? locale;
  final String? timeZone;
  final bool leaveAllSystemAppsEnabled;

  const ZeroTouchPayloadModel({
    this.packageName = 'com.focusdns.app',
    this.componentName = 'com.focusdns.app/.FocusDeviceAdminReceiver',
    this.downloadLocation,
    this.signatureChecksum,
    this.wifiConfig,
    this.adminExtras = const ManagedConfigModel(),
    this.locale,
    this.timeZone,
    this.leaveAllSystemAppsEnabled = true,
  });

  factory ZeroTouchPayloadModel.fromJson(Map<String, dynamic> json) {
    WifiConfigModel? wifi;
    final ssid = json['android.app.extra.PROVISIONING_WIFI_SSID']?.toString();
    if (ssid != null && ssid.isNotEmpty) {
      wifi = WifiConfigModel(
        ssid: ssid,
        password: json['android.app.extra.PROVISIONING_WIFI_PASSWORD']?.toString(),
        securityType: json['android.app.extra.PROVISIONING_WIFI_SECURITY_TYPE']?.toString() ?? 'WPA',
        hidden: json['android.app.extra.PROVISIONING_WIFI_HIDDEN'] == true,
      );
    }

    ManagedConfigModel extras = const ManagedConfigModel();
    final rawExtras = json['android.app.extra.PROVISIONING_ADMIN_EXTRAS_BUNDLE'];
    if (rawExtras is Map) {
      extras = ManagedConfigModel.fromMap(rawExtras);
    }

    return ZeroTouchPayloadModel(
      packageName: json['android.app.extra.PROVISIONING_DEVICE_ADMIN_PACKAGE_NAME']?.toString() ?? 'com.focusdns.app',
      componentName: json['android.app.extra.PROVISIONING_DEVICE_ADMIN_COMPONENT_NAME']?.toString() ?? 'com.focusdns.app/.FocusDeviceAdminReceiver',
      downloadLocation: json['android.app.extra.PROVISIONING_DEVICE_ADMIN_PACKAGE_DOWNLOAD_LOCATION']?.toString(),
      signatureChecksum: json['android.app.extra.PROVISIONING_DEVICE_ADMIN_SIGNATURE_CHECKSUM']?.toString(),
      wifiConfig: wifi,
      adminExtras: extras,
      locale: json['android.app.extra.PROVISIONING_LOCALE']?.toString(),
      timeZone: json['android.app.extra.PROVISIONING_TIME_ZONE']?.toString(),
      leaveAllSystemAppsEnabled: json['android.app.extra.PROVISIONING_LEAVE_ALL_SYSTEM_APPS_ENABLED'] != false,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'android.app.extra.PROVISIONING_DEVICE_ADMIN_PACKAGE_NAME': packageName,
      'android.app.extra.PROVISIONING_DEVICE_ADMIN_COMPONENT_NAME': componentName,
      if (downloadLocation != null)
        'android.app.extra.PROVISIONING_DEVICE_ADMIN_PACKAGE_DOWNLOAD_LOCATION': downloadLocation,
      if (signatureChecksum != null)
        'android.app.extra.PROVISIONING_DEVICE_ADMIN_SIGNATURE_CHECKSUM': signatureChecksum,
      if (wifiConfig?.ssid != null) ...{
        'android.app.extra.PROVISIONING_WIFI_SSID': wifiConfig!.ssid,
        if (wifiConfig!.password != null)
          'android.app.extra.PROVISIONING_WIFI_PASSWORD': wifiConfig!.password,
        'android.app.extra.PROVISIONING_WIFI_SECURITY_TYPE': wifiConfig!.securityType,
        'android.app.extra.PROVISIONING_WIFI_HIDDEN': wifiConfig!.hidden,
      },
      'android.app.extra.PROVISIONING_ADMIN_EXTRAS_BUNDLE': adminExtras.toMap(),
      if (locale != null) 'android.app.extra.PROVISIONING_LOCALE': locale,
      if (timeZone != null) 'android.app.extra.PROVISIONING_TIME_ZONE': timeZone,
      'android.app.extra.PROVISIONING_LEAVE_ALL_SYSTEM_APPS_ENABLED': leaveAllSystemAppsEnabled,
    };
  }
}
