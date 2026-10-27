import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:focus_dns/backend/blocker_service.dart';
import 'package:focus_dns/state_management/providers.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('FocusDnsBlockerManager & Provider Tests', () {
    setUp(() {
      FocusDnsBlockerManager.resetSimulation();
    });

    test('FocusDnsBlockerManager lifecycle on simulated environment', () async {
      // Simulation default is false
      expect(await FocusDnsBlockerManager.isAccessibilityServiceEnabled(), isFalse);

      // Trigger settings open
      final opened = await FocusDnsBlockerManager.openAccessibilitySettings();
      expect(opened, isTrue);

      // In simulation mode, opening settings marks enabled
      expect(await FocusDnsBlockerManager.isAccessibilityServiceEnabled(), isTrue);

      // Package synchronization
      final synced = await FocusDnsBlockerManager.setBlockedPackages(['com.reddit.frontpage']);
      expect(synced, isTrue);

      // Strict mode synchronization
      final strictSynced = await FocusDnsBlockerManager.setStrictMode(true);
      expect(strictSynced, isTrue);

      // Full sync
      final fullSync = await FocusDnsBlockerManager.syncRules(
        packages: ['com.reddit.frontpage', 'com.instagram.android'],
        isStrictMode: true,
      );
      expect(fullSync, isTrue);
    });

    test('blockerProvider manages state and settings toggle cleanly', () async {
      final container = ProviderContainer();

      try {
        await container.read(blockerProvider.notifier).checkStatus();
        final initial = container.read(blockerProvider);
        expect(initial.isLoading, isFalse);
        expect(initial.isEnabled, isFalse);

        await container.read(blockerProvider.notifier).openSettings();
        final updated = container.read(blockerProvider);
        expect(updated.isEnabled, isTrue);
      } finally {
        container.dispose();
      }
    });

    test('deepFocusProvider automatically syncs package names', () async {
      final container = ProviderContainer();

      try {
        final state = container.read(deepFocusProvider);
        expect(state.websites.any((w) => w.packages.contains('com.reddit.frontpage')), isTrue);
      } finally {
        container.dispose();
      }
    });
  });
}
