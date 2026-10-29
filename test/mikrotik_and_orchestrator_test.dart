import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:focus_dns/backend/mikrotik_ubiquiti_service.dart';
import 'package:focus_dns/frontend/mikrotik_ubiquiti_screen.dart';
import 'package:focus_dns/frontend/router_orchestrator_screen.dart';
import 'package:focus_dns/frontend/device_policy_audit_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('MikroTik & Ubiquiti Models Unit Tests', () {
    test('MikrotikGatewayStatus serialization and defaults', () {
      final json = {
        'router_model': 'RB5009UG+S+IN',
        'ros_version': 'RouterOS v7.15 (ARM64)',
        'is_nat_active': true,
        'is_container_running': true,
        'is_netwatch_healthy': true,
        'can_uninstall': false,
        'remaining_timer_seconds': 2400,
        'monitored_rogue_ips': 20,
      };

      final status = MikrotikGatewayStatus.fromJson(json);
      expect(status.routerModel, 'RB5009UG+S+IN');
      expect(status.rosVersion, 'RouterOS v7.15 (ARM64)');
      expect(status.isNatRedirectActive, isTrue);
      expect(status.isContainerRunning, isTrue);
      expect(status.isNetwatchHealthy, isTrue);
      expect(status.canUninstall, isFalse);
      expect(status.remainingTimerSeconds, 2400);
      expect(status.monitoredRogueIps, 20);
    });

    test('UbiquitiGatewayStatus serialization and defaults', () {
      final json = {
        'gateway_model': 'UniFi Dream Machine Special Edition (UDM-SE)',
        'os_version': 'UniFi OS 3.2.12',
        'is_prerouting_active': true,
        'is_podman_running': true,
        'can_uninstall': true,
        'remaining_timer_seconds': 0,
        'blocked_dot_drops': 88,
      };

      final status = UbiquitiGatewayStatus.fromJson(json);
      expect(status.gatewayModel, contains('UDM-SE'));
      expect(status.isPreroutingActive, isTrue);
      expect(status.isPodmanDaemonRunning, isTrue);
      expect(status.canUninstall, isTrue);
      expect(status.remainingTimerSeconds, 0);
      expect(status.blockedDoTDrops, 88);
    });

    test('RouterOrchestratorStatus serialization and defaults', () {
      final json = {
        'router_id': 'rtr_edge_core_01',
        'platform': 'Linux 6.1 (ARM64 OpenWrt/Alpine)',
        'is_running': true,
        'uptime_seconds': 120400,
        'is_locked': false,
        'remaining_timer_seconds': 0,
        'can_uninstall': true,
        'active_profile': 'profile_home_primary',
        'subsystems': {
          'stub_daemon': {
            'total_queries': 54200,
            'cache_hit_ratio': 0.624,
          },
          'connected_devices': 14,
          'multiwan': {
            'active_wan': 'wan1 (Symmetric Fiber 1Gbps)',
            'is_lan_fallback_mode': false,
          }
        }
      };

      final status = RouterOrchestratorStatus.fromJson(json);
      expect(status.routerId, 'rtr_edge_core_01');
      expect(status.platform, contains('Linux 6.1'));
      expect(status.isRunning, isTrue);
      expect(status.isLocked, isFalse);
      expect(status.canUninstall, isTrue);
      expect(status.totalQueries, 54200);
      expect(status.cacheHitRatio, closeTo(0.624, 0.001));
      expect(status.connectedClientsCount, 14);
      expect(status.activeWan, contains('wan1'));
      expect(status.isFallbackMode, isFalse);
    });
  });

  group('MikroTik & Ubiquiti Screen Widget Tests', () {
    testWidgets('Renders MikrotikUbiquitiScreen tabs and posture cards', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: MikrotikUbiquitiScreen(),
        ),
      );
      await tester.pumpAndSettle();

      // Verify title & tabs
      expect(find.text('MikroTik & Ubiquiti Gateways'), findsOneWidget);
      expect(find.text('MikroTik RouterOS v7'), findsOneWidget);
      expect(find.text('Ubiquiti UniFi & EdgeMAX'), findsOneWidget);

      // Verify header card elements
      expect(find.text('MikroTik Netwatch'), findsOneWidget);
      expect(find.text('UniFi DoT Drops'), findsOneWidget);

      // Switch tab to Ubiquiti
      await tester.tap(find.text('Ubiquiti UniFi & EdgeMAX'));
      await tester.pumpAndSettle();

      // Verify 1-click script section
      expect(find.text('1-Click Gateway Deployment Scripts'), findsOneWidget);
    });
  });

  group('Router Orchestrator Cockpit Widget Tests', () {
    testWidgets('Renders RouterOrchestratorScreen with 7 edge subsystems', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: RouterOrchestratorScreen(),
        ),
      );
      await tester.pumpAndSettle();

      // Verify AppBar title
      expect(find.text('Router Master Cockpit'), findsOneWidget);

      // Verify metrics banner
      expect(find.text('ORCHESTRATOR ONLINE'), findsOneWidget);
      expect(find.text('Total Queries'), findsOneWidget);
      expect(find.text('Cache Hit Ratio'), findsOneWidget);
      expect(find.text('Active Clients'), findsOneWidget);

      // Verify edge subsystems in the cockpit
      expect(find.text('RFC 9250 DNS-over-QUIC (DoQ)'), findsOneWidget);
      expect(find.text('ICANN Root DNSSEC Validator'), findsOneWidget);
      expect(find.text('Multi-WAN Uplink Failover'), findsOneWidget);
      expect(find.text('CAKE DiffServ QoS & SQM'), findsOneWidget);
      expect(find.text('Fast-Path IPSet Engine'), findsOneWidget);
      expect(find.text('Fail-Safe Local Fallback'), findsOneWidget);
    });
  });

  group('Device Policy Audit Navigation Tests', () {
    testWidgets('DevicePolicyAuditScreen includes MikroTik/Ubiquiti and Orchestrator tiles', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: DevicePolicyAuditScreen(),
        ),
      );
      await tester.pumpAndSettle();

      // Scroll down to find the new router tiles
      final scrollableFinder = find.byType(Scrollable).first;
      await tester.scrollUntilVisible(
        find.text('MikroTik & Ubiquiti Gateways'),
        300.0,
        scrollable: scrollableFinder,
      );
      await tester.pumpAndSettle();

      expect(find.text('MikroTik & Ubiquiti Gateways'), findsOneWidget);

      await tester.scrollUntilVisible(
        find.text('Master Router Orchestrator Cockpit'),
        150.0,
        scrollable: scrollableFinder,
      );
      await tester.pumpAndSettle();

      expect(find.text('Master Router Orchestrator Cockpit'), findsOneWidget);
    });
  });
}
