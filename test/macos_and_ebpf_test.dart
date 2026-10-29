import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:focus_dns/backend/macos_ebpf_service.dart';
import 'package:focus_dns/frontend/macos_proxy_screen.dart';
import 'package:focus_dns/frontend/linux_ebpf_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('macOS & Linux eBPF Models Unit Tests', () {
    test('MacOsExtensionStatus serialization and defaults', () {
      final json = {
        'is_proxy_active': true,
        'is_filter_active': true,
        'is_protection_locked': false,
        'remaining_timer_seconds': 0,
        'can_uninstall': true,
        'active_profile': 'profile_deep_work',
        'total_udp_flows': 25000,
        'total_tcp_flows': 6200,
        'blocked_bypasses': 95,
        'keychain_secured': true,
      };

      final status = MacOsExtensionStatus.fromJson(json);
      expect(status.isProxyActive, isTrue);
      expect(status.isFilterActive, isTrue);
      expect(status.isProtectionLocked, isFalse);
      expect(status.remainingTimerSeconds, 0);
      expect(status.canUninstall, isTrue);
      expect(status.activeProfile, 'profile_deep_work');
      expect(status.totalUdpFlows, 25000);
      expect(status.totalTcpFlows, 6200);
      expect(status.blockedBypasses, 95);
      expect(status.isKeychainTokenSecured, isTrue);
    });

    test('EbpfRouterStatus serialization and parsing', () {
      final json = {
        'is_loaded': true,
        'attached_interface': 'eth0',
        'is_locked': true,
        'remaining_timer_seconds': 1200,
        'can_uninstall': false,
        'queries_redirected': 89000,
        'doh_drops': 210,
        'dot_drops': 45,
        'rogue_ips_count': 18,
        'is_fallback_mode': false,
      };

      final status = EbpfRouterStatus.fromJson(json);
      expect(status.isLoaded, isTrue);
      expect(status.attachedInterface, 'eth0');
      expect(status.isLocked, isTrue);
      expect(status.remainingTimerSeconds, 1200);
      expect(status.canUninstall, isFalse);
      expect(status.queriesRedirected, 89000);
      expect(status.dohDrops, 210);
      expect(status.dotDrops, 45);
      expect(status.rogueIpsCount, 18);
    });

    test('FocusMacOsEbpfService script generators', () {
      final asusCmd = FocusMacOsEbpfService.getAsuswrtInstallScript('profile_strict_kids');
      expect(asusCmd, contains('asuswrt.sh'));
      expect(asusCmd, contains('profile_strict_kids'));

      final ddwrtCmd = FocusMacOsEbpfService.getDdWrtInstallScript('profile_strict_kids');
      expect(ddwrtCmd, contains('rc_firewall'));
      expect(ddwrtCmd, contains('5353'));
    });
  });

  group('MacOsProxyScreen Widget Tests', () {
    testWidgets('Renders macOS extension card, Keychain badge, and clean posture', (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: MacOsProxyScreen(),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      // Title & extension banner
      expect(find.text('macOS Network Extensions'), findsOneWidget);
      expect(find.text('SYSTEM EXTENSION ACTIVE'), findsOneWidget);
      expect(find.text('System-Wide NEDNSProxy & Content Filter'), findsOneWidget);

      // Posture card
      expect(find.text('Normal Mode: Clean Uninstallation Permitted'), findsOneWidget);

      // Keychain badge
      expect(find.text('Apple Keychain & Secure Enclave'), findsOneWidget);
      expect(find.text('HARDWARE SECURED'), findsOneWidget);

      // MDM deployment section
      expect(find.text('1-Click MDM Profile Deployment'), findsOneWidget);
      expect(find.textContaining('sudo profiles install'), findsOneWidget);
    });
  });

  group('LinuxEbpfScreen Widget Tests', () {
    testWidgets('Renders Linux eBPF banner, drop metrics, and router tabs', (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: LinuxEbpfScreen(),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      // Banner & in-kernel indicator
      expect(find.text('Linux eBPF & Router Drivers'), findsOneWidget);
      expect(find.text('eBPF / XDP IN-KERNEL ACTIVE'), findsOneWidget);
      expect(find.text('Zero-Overhead Linux Kernel Packet Filter'), findsOneWidget);

      // Posture
      expect(find.text('Normal Mode: Clean Map Unpinning Permitted'), findsOneWidget);

      // Router suite tabs
      expect(find.text('Asuswrt-Merlin (JFFS)'), findsOneWidget);
      expect(find.text('DD-WRT (NVRAM)'), findsOneWidget);
      expect(find.textContaining('asuswrt.sh'), findsOneWidget);

      // Switch tab to DD-WRT
      final ddwrtTab = find.text('DD-WRT (NVRAM)');
      await tester.tap(ddwrtTab);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.textContaining('rc_firewall'), findsOneWidget);
    });
  });
}
