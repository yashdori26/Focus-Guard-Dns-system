import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Household device connected to a home router running FocusDNS.
class HouseholdDeviceModel {
  final String macAddress;
  final String ipAddress;
  final String hostname;
  final String assignedProfile;
  final String deviceCategory;
  final bool strictLock;

  const HouseholdDeviceModel({
    required this.macAddress,
    required this.ipAddress,
    required this.hostname,
    required this.assignedProfile,
    required this.deviceCategory,
    this.strictLock = false,
  });

  factory HouseholdDeviceModel.fromJson(Map<String, dynamic> json) {
    return HouseholdDeviceModel(
      macAddress: json['mac_address'] as String? ?? '00:00:00:00:00:00',
      ipAddress: json['ip_address'] as String? ?? '',
      hostname: json['hostname'] as String? ?? 'Unknown Device',
      assignedProfile: json['assigned_profile'] as String? ?? 'profile_home_primary',
      deviceCategory: json['device_category'] as String? ?? 'Generic',
      strictLock: json['strict_lock'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() => {
    'mac_address': macAddress,
    'ip_address': ipAddress,
    'hostname': hostname,
    'assigned_profile': assignedProfile,
    'device_category': deviceCategory,
    'strict_lock': strictLock,
  };
}

/// Router configuration and status model.
class RouterConfigModel {
  final String routerId;
  final String platformType; // OpenWrt, pfSense, OPNSense
  final String firmwareVersion;
  final bool isServiceActive;
  final bool canUninstall;
  final int connectedClientsCount;
  final int queriesTotal;
  final double cacheHitRatio;
  final int bypassesBlocked24h;
  final String activeProfile;

  const RouterConfigModel({
    required this.routerId,
    required this.platformType,
    required this.firmwareVersion,
    required this.isServiceActive,
    required this.canUninstall,
    required this.connectedClientsCount,
    required this.queriesTotal,
    required this.cacheHitRatio,
    required this.bypassesBlocked24h,
    required this.activeProfile,
  });

  factory RouterConfigModel.fromJson(Map<String, dynamic> json) {
    return RouterConfigModel(
      routerId: json['router_id'] as String? ?? 'rtr_home_gw_01',
      platformType: json['platform_type'] as String? ?? 'OpenWrt',
      firmwareVersion: json['firmware_version'] as String? ?? '23.05.2',
      isServiceActive: json['is_service_active'] as bool? ?? true,
      canUninstall: json['can_uninstall'] as bool? ?? true,
      connectedClientsCount: json['connected_clients_count'] as int? ?? 6,
      queriesTotal: json['queries_total'] as int? ?? 14285,
      cacheHitRatio: (json['cache_hit_ratio'] as num?)?.toDouble() ?? 0.421,
      bypassesBlocked24h: json['bypasses_blocked_24h'] as int? ?? 42,
      activeProfile: json['active_profile'] as String? ?? 'profile_home_primary',
    );
  }
}

/// Windows WFP Driver status model.
class WfpStatusModel {
  final bool serviceRunning;
  final bool isProtectionActive;
  final int remainingTimerSeconds;
  final bool canUninstall;
  final int totalFiltersInstalled;
  final int sublayersRegistered;
  final String providerGuid;
  final int auditLogCount;

  const WfpStatusModel({
    required this.serviceRunning,
    required this.isProtectionActive,
    required this.remainingTimerSeconds,
    required this.canUninstall,
    required this.totalFiltersInstalled,
    required this.sublayersRegistered,
    required this.providerGuid,
    required this.auditLogCount,
  });

  factory WfpStatusModel.fromJson(Map<String, dynamic> json) {
    return WfpStatusModel(
      serviceRunning: json['service_running'] as bool? ?? true,
      isProtectionActive: json['is_protection_active'] as bool? ?? false,
      remainingTimerSeconds: json['remaining_timer_seconds'] as int? ?? 0,
      canUninstall: json['can_uninstall'] as bool? ?? true,
      totalFiltersInstalled: json['total_filters_installed'] as int? ?? 14,
      sublayersRegistered: json['sublayers_registered'] as int? ?? 2,
      providerGuid: json['provider_guid'] as String? ?? '{5D3E82A1-6B92-4C3D-8E1A-2F7B9C4D6E01}',
      auditLogCount: json['audit_log_count'] as int? ?? 0,
    );
  }
}

/// Service managing Router Gateways and Windows WFP Firewall telemetry.
class FocusRouterService {
  static const MethodChannel _channel = MethodChannel('focus_dns/router_wfp');

  // Simulated fallback data for cross-platform preview and widget testing
  static RouterConfigModel _mockRouter = const RouterConfigModel(
    routerId: 'rtr_home_gw_01',
    platformType: 'OpenWrt',
    firmwareVersion: '23.05.2 (Linux 5.15)',
    isServiceActive: true,
    canUninstall: true,
    connectedClientsCount: 5,
    queriesTotal: 18450,
    cacheHitRatio: 0.452,
    bypassesBlocked24h: 38,
    activeProfile: 'profile_home_primary',
  );

  static final List<HouseholdDeviceModel> _mockDevices = [
    const HouseholdDeviceModel(
      macAddress: 'D8:9E:3F:44:55:66',
      ipAddress: '192.168.1.105',
      hostname: "Sarah's iPad Mini",
      assignedProfile: 'profile_strict_kids',
      deviceCategory: 'Tablet',
      strictLock: true,
    ),
    const HouseholdDeviceModel(
      macAddress: 'AA:BB:CC:11:22:33',
      ipAddress: '192.168.1.140',
      hostname: 'LG WebOS OLED TV',
      assignedProfile: 'profile_ad_free_iot',
      deviceCategory: 'SmartTV',
      strictLock: false,
    ),
    const HouseholdDeviceModel(
      macAddress: 'F0:18:98:77:88:99',
      ipAddress: '192.168.1.182',
      hostname: 'MacBook Pro M3',
      assignedProfile: 'profile_deep_work',
      deviceCategory: 'Laptop',
      strictLock: true,
    ),
    const HouseholdDeviceModel(
      macAddress: '00:04:4B:99:AA:BB',
      ipAddress: '192.168.1.199',
      hostname: 'PlayStation 5 Console',
      assignedProfile: 'profile_family_safe',
      deviceCategory: 'GamingConsole',
      strictLock: false,
    ),
    const HouseholdDeviceModel(
      macAddress: 'B8:27:EB:12:34:56',
      ipAddress: '192.168.1.250',
      hostname: 'HomeAssistant Hub',
      assignedProfile: 'profile_ad_free_iot',
      deviceCategory: 'IoT',
      strictLock: false,
    ),
  ];

  static WfpStatusModel _mockWfp = const WfpStatusModel(
    serviceRunning: true,
    isProtectionActive: false,
    remainingTimerSeconds: 0,
    canUninstall: true,
    totalFiltersInstalled: 18,
    sublayersRegistered: 2,
    providerGuid: '{5D3E82A1-6B92-4C3D-8E1A-2F7B9C4D6E01}',
    auditLogCount: 12,
  );

  static bool mockMode = true;

  /// Fetches live router gateway status.
  static Future<RouterConfigModel> getRouterStatus() async {
    if (mockMode) return _mockRouter;
    try {
      final res = await _channel.invokeMethod<String>('getRouterStatus');
      if (res != null) {
        return RouterConfigModel.fromJson(jsonDecode(res) as Map<String, dynamic>);
      }
    } catch (_) {}
    return _mockRouter;
  }

  /// Fetches discovered connected household devices.
  static Future<List<HouseholdDeviceModel>> getConnectedDevices() async {
    if (mockMode) return _mockDevices;
    try {
      final res = await _channel.invokeMethod<String>('getConnectedDevices');
      if (res != null) {
        final list = jsonDecode(res) as List<dynamic>;
        return list.map((e) => HouseholdDeviceModel.fromJson(e as Map<String, dynamic>)).toList();
      }
    } catch (_) {}
    return _mockDevices;
  }

  /// Assigns custom FocusDNS profile to specific device MAC address.
  static Future<bool> assignDeviceProfile(String macAddress, String profileId) async {
    if (mockMode) {
      final idx = _mockDevices.indexWhere((d) => d.macAddress == macAddress);
      if (idx != -1) {
        final old = _mockDevices[idx];
        _mockDevices[idx] = HouseholdDeviceModel(
          macAddress: old.macAddress,
          ipAddress: old.ipAddress,
          hostname: old.hostname,
          assignedProfile: profileId,
          deviceCategory: old.deviceCategory,
          strictLock: old.strictLock,
        );
      }
      return true;
    }
    try {
      final res = await _channel.invokeMethod<bool>('assignDeviceProfile', {
        'mac_address': macAddress,
        'profile_id': profileId,
      });
      return res ?? true;
    } catch (_) {
      final idx = _mockDevices.indexWhere((d) => d.macAddress == macAddress);
      if (idx != -1) {
        final old = _mockDevices[idx];
        _mockDevices[idx] = HouseholdDeviceModel(
          macAddress: old.macAddress,
          ipAddress: old.ipAddress,
          hostname: old.hostname,
          assignedProfile: profileId,
          deviceCategory: old.deviceCategory,
          strictLock: old.strictLock,
        );
      }
      return true;
    }
  }

  /// Fetches Windows WFP driver status.
  static Future<WfpStatusModel> getWfpStatus() async {
    if (mockMode) return _mockWfp;
    try {
      final res = await _channel.invokeMethod<String>('getWfpStatus');
      if (res != null) {
        return WfpStatusModel.fromJson(jsonDecode(res) as Map<String, dynamic>);
      }
    } catch (_) {}
    return _mockWfp;
  }

  /// Generates 1-click installation terminal command for router platform.
  static String getInstallScript(String platform, String profileId) {
    switch (platform.toLowerCase()) {
      case 'openwrt':
        return 'opkg update && opkg install luci-app-focus-dns && uci set focus_dns.settings.profile_id="$profileId" && uci commit && /etc/init.d/focus_dns restart';
      case 'pfsense':
        return 'pkg install -y focus_dns && php -r "require_once(\'/usr/local/pkg/focus_dns.inc\'); focus_dns_sync_config();"';
      case 'opnsense':
        return 'opnsense-patch -a focus_dns && configctl focus_dns start';
      default:
        return 'curl -fsSL https://get.focusguard.io/router.sh | sh -s -- --profile "$profileId"';
    }
  }
}
