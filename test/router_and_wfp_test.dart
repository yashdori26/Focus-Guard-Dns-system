import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:focus_dns/backend/router_service.dart';
import 'package:focus_dns/frontend/router_firewall_screen.dart';
import 'package:focus_dns/frontend/windows_wfp_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Router & WFP Backend Service Unit Tests', () {
    test('HouseholdDeviceModel serialization and defaults', () {
      final json = {
        'mac_address': 'AA:BB:CC:11:22:33',
        'ip_address': '192.168.1.50',
        'hostname': 'Living-Room-TV',
        'assigned_profile': 'profile_ad_free_iot',
        'device_category': 'SmartTV',
        'strict_lock': false,
      };

      final dev = HouseholdDeviceModel.fromJson(json);
      expect(dev.macAddress, 'AA:BB:CC:11:22:33');
      expect(dev.ipAddress, '192.168.1.50');
      expect(dev.hostname, 'Living-Room-TV');
      expect(dev.assignedProfile, 'profile_ad_free_iot');
      expect(dev.deviceCategory, 'SmartTV');
      expect(dev.strictLock, isFalse);

      final out = dev.toJson();
      expect(out['mac_address'], 'AA:BB:CC:11:22:33');
      expect(out['device_category'], 'SmartTV');
    });

    test('RouterConfigModel serialization and parsing', () {
      final json = {
        'router_id': 'rtr_test_01',
        'platform_type': 'OpenWrt',
        'firmware_version': '23.05.2',
        'is_service_active': true,
        'can_uninstall': true,
        'connected_clients_count': 8,
        'queries_total': 25000,
        'cache_hit_ratio': 0.485,
        'bypasses_blocked_24h': 19,
        'active_profile': 'profile_home_primary',
      };

      final cfg = RouterConfigModel.fromJson(json);
      expect(cfg.routerId, 'rtr_test_01');
      expect(cfg.platformType, 'OpenWrt');
      expect(cfg.isServiceActive, isTrue);
      expect(cfg.canUninstall, isTrue);
      expect(cfg.connectedClientsCount, 8);
      expect(cfg.queriesTotal, 25000);
      expect(cfg.cacheHitRatio, 0.485);
      expect(cfg.bypassesBlocked24h, 19);
    });

    test('WfpStatusModel serialization and parsing', () {
      final json = {
        'service_running': true,
        'is_protection_active': true,
        'remaining_timer_seconds': 1800,
        'can_uninstall': false,
        'total_filters_installed': 22,
        'sublayers_registered': 2,
        'provider_guid': '{5D3E82A1-6B92-4C3D-8E1A-2F7B9C4D6E01}',
        'audit_log_count': 15,
      };

      final wfp = WfpStatusModel.fromJson(json);
      expect(wfp.serviceRunning, isTrue);
      expect(wfp.isProtectionActive, isTrue);
      expect(wfp.remainingTimerSeconds, 1800);
      expect(wfp.canUninstall, isFalse);
      expect(wfp.totalFiltersInstalled, 22);
      expect(wfp.sublayersRegistered, 2);
    });

    test('FocusRouterService getInstallScript generation', () {
      final openwrtCmd = FocusRouterService.getInstallScript('OpenWrt', 'profile_kids');
      expect(openwrtCmd, contains('opkg install luci-app-focus-dns'));
      expect(openwrtCmd, contains('profile_kids'));

      final pfsenseCmd = FocusRouterService.getInstallScript('pfSense', 'profile_kids');
      expect(pfsenseCmd, contains('pkg install -y focus_dns'));
      expect(pfsenseCmd, contains('focus_dns_sync_config'));

      final opnsenseCmd = FocusRouterService.getInstallScript('OPNSense', 'profile_kids');
      expect(opnsenseCmd, contains('opnsense-patch -a focus_dns'));

      final defaultCmd = FocusRouterService.getInstallScript('linux', 'profile_kids');
      expect(defaultCmd, contains('curl -fsSL https://get.focusguard.io/router.sh'));
    });

    test('FocusRouterService fallback mock methods', () async {
      final status = await FocusRouterService.getRouterStatus();
      expect(status.routerId, isNotEmpty);
      expect(status.platformType, 'OpenWrt');

      final devs = await FocusRouterService.getConnectedDevices();
      expect(devs.length, greaterThanOrEqualTo(3));

      final assignResult = await FocusRouterService.assignDeviceProfile(devs.first.macAddress, 'profile_deep_work');
      expect(assignResult, isTrue);

      final wfp = await FocusRouterService.getWfpStatus();
      expect(wfp.serviceRunning, isTrue);
      expect(wfp.totalFiltersInstalled, greaterThan(0));
    });
  });

  group('RouterFirewallScreen Widget Tests', () {
    testWidgets('Renders router gateway card, platform badge, and devices', (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: RouterFirewallScreen(),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      // Gateway card
      expect(find.text('Whole-Home Router Firewall'), findsOneWidget);
      expect(find.text('OpenWrt'), findsWidgets);
      expect(find.text('INTERCEPTING'), findsOneWidget);
      expect(find.text('Whole-Home Wi-Fi Gateway Protection'), findsOneWidget);

      // Installation section
      expect(find.text('1-Click Router Installation'), findsOneWidget);
      expect(find.text('pfSense'), findsOneWidget);
      expect(find.text('OPNSense'), findsOneWidget);

      // Connected devices
      expect(find.textContaining('Household Devices'), findsOneWidget);
      expect(find.text("Sarah's iPad Mini"), findsOneWidget);
      expect(find.text('LG WebOS OLED TV'), findsOneWidget);

      // Anti-Bypass guarantee card
      expect(find.text('Inviolable Anti-Bypass & Fail-Safe Laws'), findsOneWidget);
    });

    testWidgets('Switching router installation tabs updates command string', (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: RouterFirewallScreen(),
        ),
      );

      await tester.pumpAndSettle();

      // Tap pfSense chip
      final pfsenseChip = find.text('pfSense');
      expect(pfsenseChip, findsOneWidget);
      await tester.tap(pfsenseChip);
      await tester.pumpAndSettle();

      expect(find.textContaining('pkg install -y focus_dns'), findsOneWidget);

      // Tap OPNSense chip
      final opnsenseChip = find.text('OPNSense');
      await tester.tap(opnsenseChip);
      await tester.pumpAndSettle();

      expect(find.textContaining('opnsense-patch -a focus_dns'), findsOneWidget);
    });
  });

  group('WindowsWfpScreen Widget Tests', () {
    testWidgets('Renders WFP kernel driver card, filter count, and uninstallation posture', (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: WindowsWfpScreen(),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      // Header card
      expect(find.text('Windows WFP Protection Driver'), findsOneWidget);
      expect(find.text('KERNEL WFP ACTIVE'), findsOneWidget);
      expect(find.text('Windows Filtering Platform Callout Driver'), findsOneWidget);

      // Conditional uninstallation posture
      expect(find.text('Normal Mode: Clean Uninstallation Permitted'), findsOneWidget);

      // Targeted app bypass section
      expect(find.text('Targeted Application Bypasses'), findsOneWidget);
      expect(find.text('Google Chrome'), findsOneWidget);
      expect(find.text('Microsoft Edge'), findsOneWidget);
      expect(find.text('Mozilla Firefox'), findsOneWidget);
      expect(find.text('Discord'), findsOneWidget);
      expect(find.text('Steam'), findsOneWidget);

      // Exemption notice
      expect(find.textContaining('Windows Update (svchost.exe)'), findsOneWidget);
    });
  });
}
