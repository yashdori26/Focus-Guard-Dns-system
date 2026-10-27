import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:focus_dns/backend/vpn_service.dart';
import 'package:focus_dns/state_management/providers.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('FocusDnsVpnManager & Provider Tests', () {
    test('FocusDnsVpnManager lifecycle on simulated environment', () async {
      expect(await FocusDnsVpnManager.isRunning(), isFalse);
      expect(await FocusDnsVpnManager.isBackendReachable(), isTrue);

      final prepared = await FocusDnsVpnManager.prepare();
      expect(prepared, isTrue);

      final started = await FocusDnsVpnManager.startVpn(
        serverUrl: 'http://127.0.0.1:8080/dns-query',
        profileId: 'a1b2c3',
        apiToken: 'test_token',
      );
      expect(started, isTrue);
      expect(await FocusDnsVpnManager.isRunning(), isTrue);

      final stopped = await FocusDnsVpnManager.stopVpn();
      expect(stopped, isTrue);
      expect(await FocusDnsVpnManager.isRunning(), isFalse);
    });

    test('vpnProvider manages lifecycle and reachability cleanly', () async {
      final containerRef = ProviderContainer();

      try {
        final initial = containerRef.read(vpnProvider);
        expect(initial.isRunning, isFalse);
        expect(initial.isBackendReachable, isTrue);

        await containerRef.read(vpnProvider.notifier).start(profileId: 'a1b2c3');
        expect(containerRef.read(vpnProvider).isRunning, isTrue);
        expect(containerRef.read(vpnProvider).isBackendReachable, isTrue);

        await containerRef.read(vpnProvider.notifier).stop();
        expect(containerRef.read(vpnProvider).isRunning, isFalse);

        await containerRef.read(vpnProvider.notifier).toggle(profileId: 'a1b2c3');
        expect(containerRef.read(vpnProvider).isRunning, isTrue);

        await containerRef.read(vpnProvider.notifier).toggle(profileId: 'a1b2c3');
        expect(containerRef.read(vpnProvider).isRunning, isFalse);
      } finally {
        containerRef.dispose();
      }
    });
  });
}
