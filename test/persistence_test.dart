import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:focus_dns/models/app_models.dart';
import 'package:focus_dns/models/enums.dart';
import 'package:focus_dns/services/app_storage_service.dart';
import 'package:focus_dns/repositories/persistent_settings_repository.dart';
import 'package:focus_dns/state_management/deep_focus_state.dart';
import 'package:focus_dns/state_management/protection_state.dart';
import 'package:focus_dns/state_management/per_app_timers_state.dart';
import 'package:focus_dns/state_management/routine_focus_state.dart';
import 'package:focus_dns/state_management/theme_state.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('Model Serialization Tests', () {
    test('BlockedItem toJson and fromJson preserve all properties', () {
      const original = BlockedItem(
        id: 'instagram',
        name: 'Instagram',
        icon: '📸',
        color: Color(0xFFFD1D1D),
        description: 'Blocks Instagram and Threads',
        packages: ['com.instagram.android', 'com.instagram.threads'],
      );

      final json = original.toJson();
      final restored = BlockedItem.fromJson(json);

      expect(restored.id, equals(original.id));
      expect(restored.name, equals(original.name));
      expect(restored.icon, equals(original.icon));
      expect(restored.color.value, equals(original.color.value));
      expect(restored.description, equals(original.description));
      expect(restored.packages, equals(original.packages));
    });

    test('AppBlockTimer toJson and fromJson preserve all properties', () {
      final now = DateTime.now();
      final timer = AppBlockTimer(
        appId: 'youtube',
        appName: 'YouTube',
        icon: '▶️',
        packages: const ['com.google.android.youtube'],
        domains: const ['youtube.com', 'googlevideo.com'],
        allocatedMinutes: 120,
        remainingSeconds: 7200,
        targetEndTime: now.add(const Duration(hours: 2)),
        isLocked: true,
      );

      final json = timer.toJson();
      final restored = AppBlockTimer.fromJson(json);

      expect(restored.appId, equals(timer.appId));
      expect(restored.appName, equals(timer.appName));
      expect(restored.allocatedMinutes, equals(timer.allocatedMinutes));
      expect(restored.remainingSeconds, equals(timer.remainingSeconds));
      expect(restored.isLocked, equals(timer.isLocked));
      expect(restored.targetEndTime?.difference(timer.targetEndTime!).inSeconds.abs(), lessThanOrEqualTo(1));
    });
  });

  group('DeepFocus State Persistence Tests', () {
    test('DeepFocusNotifier loads custom apps and categories from persistent storage', () async {
      final customApps = [
        const BlockedItem(
          id: 'instagram',
          name: 'Instagram',
          icon: '📸',
          packages: ['com.instagram.android'],
        ),
        const BlockedItem(
          id: 'youtube',
          name: 'YouTube',
          icon: '▶️',
          packages: ['com.google.android.youtube'],
        ),
      ];

      await AppStorageService.saveBlockedWebsites(customApps);

      final notifier = DeepFocusNotifier();
      // Allow async persistence load to complete
      await Future.delayed(const Duration(milliseconds: 50));

      expect(notifier.state.websites.length, equals(2));
      expect(notifier.state.websites.any((w) => w.id == 'instagram'), isTrue);
      expect(notifier.state.websites.any((w) => w.id == 'youtube'), isTrue);
      expect(notifier.state.websites.any((w) => w.id == 'reddit'), isFalse);
    });

    test('Adding and removing websites immediately persists changes', () async {
      final notifier = DeepFocusNotifier();
      await Future.delayed(const Duration(milliseconds: 50));

      notifier.addWebsite(const BlockedItem(
        id: 'twitch',
        name: 'Twitch',
        icon: '🎮',
        packages: ['tv.twitch.android.app'],
      ));

      await Future.delayed(const Duration(milliseconds: 50));

      final persisted = await AppStorageService.loadBlockedWebsites();
      expect(persisted, isNotNull);
      expect(persisted!.any((w) => w.name == 'Twitch'), isTrue);

      notifier.removeWebsite('Twitch');
      await Future.delayed(const Duration(milliseconds: 50));

      final persistedAfterRemove = await AppStorageService.loadBlockedWebsites();
      expect(persistedAfterRemove!.any((w) => w.name == 'Twitch'), isFalse);
    });
  });

  group('PersistentSettingsRepository & Protection State Tests', () {
    test('Protection state persists and does not reset to false on init', () async {
      final repo = PersistentSettingsRepository();
      await repo.setProtectionOn(true);

      final isProtected = await repo.isProtectionOn();
      expect(isProtected, isTrue);

      final notifier = ProtectionNotifier(repo);
      await Future.delayed(const Duration(milliseconds: 50));

      expect(notifier.state, isTrue);
    });

    test('Strict mode timer calculates remaining seconds accurately from target wall-clock time', () async {
      final repo = PersistentSettingsRepository();
      // Set strict mode for 120 minutes
      await repo.setStrictMode(true, durationMinutes: 120);

      expect(await repo.isStrictMode(), isTrue);
      final remaining = await repo.getStrictRemainingSeconds();
      expect(remaining, greaterThan(7100));
      expect(remaining, lessThanOrEqualTo(7200));

      // Re-create notifier and check state restores locked status
      final strictNotifier = StrictModeNotifier(repo);
      await Future.delayed(const Duration(milliseconds: 50));

      expect(strictNotifier.state.isStrict, isTrue);
      expect(strictNotifier.state.isLocked, isTrue);
      expect(strictNotifier.state.remainingSeconds, greaterThan(7100));
    });

    test('Security and Privacy feature toggles persist', () async {
      final repo = PersistentSettingsRepository();

      await repo.setSecurityFeature(SecurityFeature.aiThreat, true);
      await repo.setSecurityFeature(SecurityFeature.cryptojacking, true);
      await repo.setPrivacyFeature(PrivacyFeature.affiliateLinks, true);

      expect(await repo.getSecurityFeature(SecurityFeature.aiThreat), isTrue);
      expect(await repo.getSecurityFeature(SecurityFeature.cryptojacking), isTrue);
      expect(await repo.getPrivacyFeature(PrivacyFeature.affiliateLinks), isTrue);
    });
  });

  group('PerAppTimers & RoutineFocus Persistence Tests', () {
    test('PerAppTimersNotifier retains configured durations across sessions', () async {
      final notifier = PerAppTimersNotifier(enableTicker: false);
      await Future.delayed(const Duration(milliseconds: 50));

      notifier.setCustomMinutes('instagram', 180);
      await Future.delayed(const Duration(milliseconds: 50));

      // Fresh notifier instance simulating app restart
      final restartedNotifier = PerAppTimersNotifier(enableTicker: false);
      await Future.delayed(const Duration(milliseconds: 50));

      expect(restartedNotifier.state['instagram']?.allocatedMinutes, equals(180));
    });

    test('RoutineFocusNotifier retains custom interval config', () async {
      final notifier = RoutineFocusNotifier(enableTicker: false);
      await Future.delayed(const Duration(milliseconds: 50));

      notifier.updateConfig(sessionMinutes: 50, breakMinutes: 15, totalCycles: 5);
      await Future.delayed(const Duration(milliseconds: 50));

      final restartedNotifier = RoutineFocusNotifier(enableTicker: false);
      await Future.delayed(const Duration(milliseconds: 50));

      expect(restartedNotifier.state.config.sessionMinutes, equals(50));
      expect(restartedNotifier.state.config.breakMinutes, equals(15));
      expect(restartedNotifier.state.config.totalCycles, equals(5));
    });

    test('ThemeModeNotifier persists theme changes', () async {
      final notifier = ThemeModeNotifier();
      await Future.delayed(const Duration(milliseconds: 50));

      notifier.setMode(ThemeMode.light);
      await Future.delayed(const Duration(milliseconds: 50));

      final restarted = ThemeModeNotifier();
      await Future.delayed(const Duration(milliseconds: 50));

      expect(restarted.state, equals(ThemeMode.light));
    });
  });
}
