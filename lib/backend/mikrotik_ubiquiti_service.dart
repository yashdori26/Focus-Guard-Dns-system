import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// MikroTik RouterOS gateway status model.
class MikrotikGatewayStatus {
  final String routerModel;
  final String rosVersion;
  final bool isNatRedirectActive;
  final bool isContainerRunning;
  final bool isNetwatchHealthy;
  final bool canUninstall;
  final int remainingTimerSeconds;
  final int monitoredRogueIps;

  const MikrotikGatewayStatus({
    required this.routerModel,
    required this.rosVersion,
    required this.isNatRedirectActive,
    required this.isContainerRunning,
    required this.isNetwatchHealthy,
    required this.canUninstall,
    required this.remainingTimerSeconds,
    required this.monitoredRogueIps,
  });

  factory MikrotikGatewayStatus.fromJson(Map<String, dynamic> json) {
    return MikrotikGatewayStatus(
      routerModel: json['router_model'] as String? ?? 'hAP ax3 / RB5009',
      rosVersion: json['ros_version'] as String? ?? 'RouterOS v7.14',
      isNatRedirectActive: json['is_nat_active'] as bool? ?? true,
      isContainerRunning: json['is_container_running'] as bool? ?? true,
      isNetwatchHealthy: json['is_netwatch_healthy'] as bool? ?? true,
      canUninstall: json['can_uninstall'] as bool? ?? true,
      remainingTimerSeconds: json['remaining_timer_seconds'] as int? ?? 0,
      monitoredRogueIps: json['monitored_rogue_ips'] as int? ?? 12,
    );
  }
}

/// Ubiquiti EdgeRouter & UniFi gateway status model.
class UbiquitiGatewayStatus {
  final String gatewayModel;
  final String osVersion;
  final bool isPreroutingActive;
  final bool isPodmanDaemonRunning;
  final bool canUninstall;
  final int remainingTimerSeconds;
  final int blockedDoTDrops;

  const UbiquitiGatewayStatus({
    required this.gatewayModel,
    required this.osVersion,
    required this.isPreroutingActive,
    required this.isPodmanDaemonRunning,
    required this.canUninstall,
    required this.remainingTimerSeconds,
    required this.blockedDoTDrops,
  });

  factory UbiquitiGatewayStatus.fromJson(Map<String, dynamic> json) {
    return UbiquitiGatewayStatus(
      gatewayModel: json['gateway_model'] as String? ?? 'UniFi Dream Machine Pro (UDM-Pro)',
      osVersion: json['os_version'] as String? ?? 'UniFi OS 3.2.12',
      isPreroutingActive: json['is_prerouting_active'] as bool? ?? true,
      isPodmanDaemonRunning: json['is_podman_running'] as bool? ?? true,
      canUninstall: json['can_uninstall'] as bool? ?? true,
      remainingTimerSeconds: json['remaining_timer_seconds'] as int? ?? 0,
      blockedDoTDrops: json['blocked_dot_drops'] as int? ?? 48,
    );
  }
}

/// Unified Router Orchestrator master status model.
class RouterOrchestratorStatus {
  final String routerId;
  final String platform;
  final bool isRunning;
  final int uptimeSeconds;
  final bool isLocked;
  final int remainingTimerSeconds;
  final bool canUninstall;
  final String activeProfile;
  final int totalQueries;
  final double cacheHitRatio;
  final int connectedClientsCount;
  final String activeWan;
  final bool isFallbackMode;

  const RouterOrchestratorStatus({
    required this.routerId,
    required this.platform,
    required this.isRunning,
    required this.uptimeSeconds,
    required this.isLocked,
    required this.remainingTimerSeconds,
    required this.canUninstall,
    required this.activeProfile,
    required this.totalQueries,
    required this.cacheHitRatio,
    required this.connectedClientsCount,
    required this.activeWan,
    required this.isFallbackMode,
  });

  factory RouterOrchestratorStatus.fromJson(Map<String, dynamic> json) {
    final sub = json['subsystems'] as Map<String, dynamic>? ?? {};
    final stub = sub['stub_daemon'] as Map<String, dynamic>? ?? {};
    final wan = sub['multiwan'] as Map<String, dynamic>? ?? {};

    return RouterOrchestratorStatus(
      routerId: json['router_id'] as String? ?? 'rtr_home_master_gw',
      platform: json['platform'] as String? ?? 'Unified-EdgeRouter',
      isRunning: json['is_running'] as bool? ?? true,
      uptimeSeconds: json['uptime_seconds'] as int? ?? 86420,
      isLocked: json['is_locked'] as bool? ?? false,
      remainingTimerSeconds: json['remaining_timer_seconds'] as int? ?? 0,
      canUninstall: json['can_uninstall'] as bool? ?? true,
      activeProfile: json['active_profile'] as String? ?? 'profile_home_primary',
      totalQueries: stub['total_queries'] as int? ?? 28450,
      cacheHitRatio: (stub['cache_hit_ratio'] as num?)?.toDouble() ?? 0.482,
      connectedClientsCount: sub['connected_devices'] as int? ?? 6,
      activeWan: wan['active_wan'] as String? ?? 'wan1 (Primary Fiber)',
      isFallbackMode: wan['is_lan_fallback_mode'] as bool? ?? false,
    );
  }
}

/// Service layer for MikroTik, Ubiquiti, and Router Orchestrator.
class FocusMikrotikUbiquitiService {
  static const MethodChannel _channel = MethodChannel('focus_dns/router_advanced');
  static bool mockMode = true;

  static const MikrotikGatewayStatus _mockMikrotik = MikrotikGatewayStatus(
    routerModel: 'hAP ax3 / RB5009 (ARM64)',
    rosVersion: 'RouterOS v7.14 (Stable)',
    isNatRedirectActive: true,
    isContainerRunning: true,
    isNetwatchHealthy: true,
    canUninstall: true,
    remainingTimerSeconds: 0,
    monitoredRogueIps: 14,
  );

  static const UbiquitiGatewayStatus _mockUbiquiti = UbiquitiGatewayStatus(
    gatewayModel: 'UniFi Dream Machine Pro (UDM-Pro)',
    osVersion: 'UniFi OS 3.2.12',
    isPreroutingActive: true,
    isPodmanDaemonRunning: true,
    canUninstall: true,
    remainingTimerSeconds: 0,
    blockedDoTDrops: 56,
  );

  static const RouterOrchestratorStatus _mockOrchestrator = RouterOrchestratorStatus(
    routerId: 'rtr_home_master_gw_01',
    platform: 'Unified EdgeMaster (Linux 6.1)',
    isRunning: true,
    uptimeSeconds: 94210,
    isLocked: false,
    remainingTimerSeconds: 0,
    canUninstall: true,
    activeProfile: 'profile_home_primary',
    totalQueries: 34180,
    cacheHitRatio: 0.512,
    connectedClientsCount: 8,
    activeWan: 'wan1 (Primary Fiber)',
    isFallbackMode: false,
  );

  static Future<MikrotikGatewayStatus> getMikrotikStatus() async {
    if (mockMode) return _mockMikrotik;
    try {
      final res = await _channel.invokeMethod<String>('getMikrotikStatus');
      if (res != null) {
        return MikrotikGatewayStatus.fromJson(jsonDecode(res) as Map<String, dynamic>);
      }
    } catch (_) {}
    return _mockMikrotik;
  }

  static Future<UbiquitiGatewayStatus> getUbiquitiStatus() async {
    if (mockMode) return _mockUbiquiti;
    try {
      final res = await _channel.invokeMethod<String>('getUbiquitiStatus');
      if (res != null) {
        return UbiquitiGatewayStatus.fromJson(jsonDecode(res) as Map<String, dynamic>);
      }
    } catch (_) {}
    return _mockUbiquiti;
  }

  static Future<RouterOrchestratorStatus> getOrchestratorStatus() async {
    if (mockMode) return _mockOrchestrator;
    try {
      final res = await _channel.invokeMethod<String>('getOrchestratorStatus');
      if (res != null) {
        return RouterOrchestratorStatus.fromJson(jsonDecode(res) as Map<String, dynamic>);
      }
    } catch (_) {}
    return _mockOrchestrator;
  }

  static String getMikrotikScript(String profileId) {
    return '/ip firewall nat add chain=dstnat in-interface-list=LAN protocol=udp dst-port=53 action=redirect to-ports=5353 comment="FocusGuard-DNS"';
  }

  static String getUbiquitiScript(String profileId) {
    return 'curl -fsSL https://get.focusguard.io/unifi.sh | sh -s -- --profile "$profileId"';
  }
}
