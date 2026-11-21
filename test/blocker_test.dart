import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:focus_dns/backend/blocker_service.dart';
import 'package:focus_dns/state_management/providers.dart';

import 'package:focus_dns/models/app_models.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('FocusDnsBlockerManager & Provider Tests', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
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
        container.read(deepFocusProvider.notifier).addWebsite(const BlockedItem(
          id: 'reddit',
          name: 'Reddit',
          icon: 'R',
          packages: ['com.reddit.frontpage'],
        ));
        final state = container.read(deepFocusProvider);
        expect(state.websites.any((w) => w.packages.contains('com.reddit.frontpage')), isTrue);
      } finally {
        container.dispose();
      }
    });

    test('strictModeProvider lifecycle: activates protection, auto-expires and unblocks cleanly', () async {
      final container = ProviderContainer();

      try {
        expect(container.read(strictModeProvider).isStrict, isFalse);
        expect(container.read(protectionProvider), isFalse);

        // 1. Activate strict mode
        final setSuccess = await container.read(strictModeProvider.notifier).set(true, durationMinutes: 10);
        expect(setSuccess, isTrue);

        final activeState = container.read(strictModeProvider);
        expect(activeState.isStrict, isTrue);
        expect(activeState.remainingSeconds, 600);
        expect(container.read(protectionProvider), isTrue);

        // 2. Cannot deactivate early without force
        final earlyDeact = await container.read(strictModeProvider.notifier).set(false);
        expect(earlyDeact, isFalse);
        expect(container.read(strictModeProvider).isStrict, isTrue);

        // 3. Deactivate/expire restores unblocked state
        final forceDeact = await container.read(strictModeProvider.notifier).set(false, force: true);
        expect(forceDeact, isTrue);

        final unblockedState = container.read(strictModeProvider);
        expect(unblockedState.isStrict, isFalse);
        expect(unblockedState.remainingSeconds, 0);
        expect(container.read(protectionProvider), isFalse);
      } finally {
        container.dispose();
      }
    });
  });
}
