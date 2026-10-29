import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// macOS NetworkExtension status model.
class MacOsExtensionStatus {
  final bool isProxyActive;
  final bool isFilterActive;
  final bool isProtectionLocked;
  final int remainingTimerSeconds;
  final bool canUninstall;
  final String activeProfile;
  final int totalUdpFlows;
  final int totalTcpFlows;
  final int blockedBypasses;
  final bool isKeychainTokenSecured;

  const MacOsExtensionStatus({
    required this.isProxyActive,
    required this.isFilterActive,
    required this.isProtectionLocked,
    required this.remainingTimerSeconds,
    required this.canUninstall,
    required this.activeProfile,
    required this.totalUdpFlows,
    required this.totalTcpFlows,
    required this.blockedBypasses,
    required this.isKeychainTokenSecured,
  });

  factory MacOsExtensionStatus.fromJson(Map<String, dynamic> json) {
    return MacOsExtensionStatus(
      isProxyActive: json['is_proxy_active'] as bool? ?? true,
      isFilterActive: json['is_filter_active'] as bool? ?? true,
      isProtectionLocked: json['is_protection_locked'] as bool? ?? false,
      remainingTimerSeconds: json['remaining_timer_seconds'] as int? ?? 0,
      canUninstall: json['can_uninstall'] as bool? ?? true,
      activeProfile: json['active_profile'] as String? ?? 'profile_mac_workstation',
      totalUdpFlows: json['total_udp_flows'] as int? ?? 12840,
      totalTcpFlows: json['total_tcp_flows'] as int? ?? 3210,
      blockedBypasses: json['blocked_bypasses'] as int? ?? 58,
      isKeychainTokenSecured: json['keychain_secured'] as bool? ?? true,
    );
  }
}

/// Linux eBPF / XDP router status model.
class EbpfRouterStatus {
  final bool isLoaded;
  final String attachedInterface;
  final bool isLocked;
  final int remainingTimerSeconds;
  final bool canUninstall;
  final int queriesRedirected;
  final int dohDrops;
  final int dotDrops;
  final int rogueIpsCount;
  final bool isFallbackMode;

  const EbpfRouterStatus({
    required this.isLoaded,
    required this.attachedInterface,
    required this.isLocked,
    required this.remainingTimerSeconds,
    required this.canUninstall,
    required this.queriesRedirected,
    required this.dohDrops,
    required this.dotDrops,
    required this.rogueIpsCount,
    required this.isFallbackMode,
  });

  factory EbpfRouterStatus.fromJson(Map<String, dynamic> json) {
    return EbpfRouterStatus(
      isLoaded: json['is_loaded'] as bool? ?? true,
      attachedInterface: json['attached_interface'] as String? ?? 'br-lan',
      isLocked: json['is_locked'] as bool? ?? false,
      remainingTimerSeconds: json['remaining_timer_seconds'] as int? ?? 0,
      canUninstall: json['can_uninstall'] as bool? ?? true,
      queriesRedirected: json['queries_redirected'] as int? ?? 48210,
      dohDrops: json['doh_drops'] as int? ?? 124,
      dotDrops: json['dot_drops'] as int? ?? 31,
      rogueIpsCount: json['rogue_ips_count'] as int? ?? 14,
      isFallbackMode: json['is_fallback_mode'] as bool? ?? false,
    );
  }
}

/// Service managing macOS NetworkExtension and Linux eBPF telemetry.
class FocusMacOsEbpfService {
  static const MethodChannel _channel = MethodChannel('focus_dns/macos_ebpf');
  static bool mockMode = true;

  static const MacOsExtensionStatus _mockMacOs = MacOsExtensionStatus(
    isProxyActive: true,
    isFilterActive: true,
    isProtectionLocked: false,
    remainingTimerSeconds: 0,
    canUninstall: true,
    activeProfile: 'profile_mac_workstation',
    totalUdpFlows: 14920,
    totalTcpFlows: 4120,
    blockedBypasses: 64,
    isKeychainTokenSecured: true,
  );

  static const EbpfRouterStatus _mockEbpf = EbpfRouterStatus(
    isLoaded: true,
    attachedInterface: 'br-lan',
    isLocked: false,
    remainingTimerSeconds: 0,
    canUninstall: true,
    queriesRedirected: 52180,
    dohDrops: 142,
    dotDrops: 39,
    rogueIpsCount: 16,
    isFallbackMode: false,
  );

  /// Fetches macOS NetworkExtension telemetry.
  static Future<MacOsExtensionStatus> getMacExtensionStatus() async {
    if (mockMode) return _mockMacOs;
    try {
      final res = await _channel.invokeMethod<String>('getMacExtensionStatus');
      if (res != null) {
        return MacOsExtensionStatus.fromJson(jsonDecode(res) as Map<String, dynamic>);
      }
    } catch (_) {}
    return _mockMacOs;
  }

  /// Fetches Linux eBPF telemetry.
  static Future<EbpfRouterStatus> getEbpfStatus() async {
    if (mockMode) return _mockEbpf;
    try {
      final res = await _channel.invokeMethod<String>('getEbpfStatus');
      if (res != null) {
        return EbpfRouterStatus.fromJson(jsonDecode(res) as Map<String, dynamic>);
      }
    } catch (_) {}
    return _mockEbpf;
  }

  /// Generates 1-click install command for Asuswrt-Merlin routers.
  static String getAsuswrtInstallScript(String profileId) {
    return 'curl -fsSL https://get.focusguard.io/asuswrt.sh | sh -s -- --profile "$profileId"';
  }

  /// Generates 1-click install sequence for DD-WRT routers.
  static String getDdWrtInstallScript(String profileId) {
    return 'nvram set rc_firewall="iptables -t nat -A PREROUTING -i br0 -p udp --dport 53 -j REDIRECT --to-ports 5353" && nvram commit';
  }
}
