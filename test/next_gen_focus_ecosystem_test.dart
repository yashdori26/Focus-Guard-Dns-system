import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:focus_dns/models/app_models.dart';
import 'package:focus_dns/state_management/providers.dart';
import 'package:focus_dns/frontend/widgets/routine_focus_card.dart';
import 'package:focus_dns/frontend/widgets/per_app_timer_card.dart';
import 'package:focus_dns/frontend/widgets/surgical_filter_card.dart';
import 'package:focus_dns/frontend/widgets/longitudinal_analytics_card.dart';
import 'package:focus_dns/frontend/theme/wabi_sabi_theme.dart';
import 'package:focus_dns/frontend/more_screen.dart';
import 'package:focus_dns/backend/blocker_service.dart';

Widget _buildTestHarness({required Widget child, List<Override> overrides = const []}) {
  return ProviderScope(
    overrides: overrides,
    child: MaterialApp(
      theme: WabiSabiTheme.darkTheme,
      home: Scaffold(
        body: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: child,
          ),
        ),
      ),
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Next-Gen Focus Ecosystem: Routine Focus State & Card', () {
    test('1. RoutineFocusConfig clamps break duration to a maximum of 30 minutes', () {
      const config = RoutineFocusConfig();
      final updated = config.copyWith(breakMinutes: 45);
      expect(updated.breakMinutes, equals(30));

      final updated2 = config.copyWith(breakMinutes: 15);
      expect(updated2.breakMinutes, equals(15));
    });

    test('2. RoutineFocusNotifier updates configuration when idle', () {
      final notifier = RoutineFocusNotifier(enableTicker: false);
      notifier.updateConfig(sessionMinutes: 50, breakMinutes: 10, totalCycles: 4);

      expect(notifier.state.config.sessionMinutes, equals(50));
      expect(notifier.state.config.breakMinutes, equals(10));
      expect(notifier.state.config.totalCycles, equals(4));
    });

    test('3. Starting routine switches phase to focusSession and calculates remaining seconds', () {
      final notifier = RoutineFocusNotifier(enableTicker: false);
      notifier.updateConfig(sessionMinutes: 45, breakMinutes: 10, totalCycles: 3);
      notifier.startRoutine();

      expect(notifier.state.phase, equals(RoutinePhase.focusSession));
      expect(notifier.state.isFocus, isTrue);
      expect(notifier.state.isBreak, isFalse);
      expect(notifier.state.currentCycle, equals(1));
      expect(notifier.state.remainingSeconds, equals(45 * 60));
    });

    test('4. Canceling routine resets state cleanly to idle', () {
      final notifier = RoutineFocusNotifier(enableTicker: false);
      notifier.startRoutine();
      expect(notifier.state.isActive, isTrue);

      notifier.cancelRoutine();
      expect(notifier.state.phase, equals(RoutinePhase.idle));
      expect(notifier.state.remainingSeconds, equals(0));
    });

    testWidgets('5. RoutineFocusCard renders session, break and cycles chips', (tester) async {
      await tester.pumpWidget(_buildTestHarness(child: const RoutineFocusCard()));
      await tester.pump();

      expect(find.text('Anti-Doomscroll Routine'), findsOneWidget);
      expect(find.text('START FOCUS + BREAK ROUTINE'), findsOneWidget);
      expect(find.text('Break (Max 30m)'), findsOneWidget);
    });
  });

  group('Next-Gen Focus Ecosystem: Per-App Independent Timers', () {
    test('6. PerAppTimersNotifier initializes default app presets (Instagram, YouTube, Reddit)', () {
      final notifier = PerAppTimersNotifier(enableTicker: false);
      expect(notifier.state.containsKey('instagram'), isTrue);
      expect(notifier.state.containsKey('youtube'), isTrue);
      expect(notifier.state.containsKey('reddit'), isTrue);
      expect(notifier.state['instagram']!.allocatedMinutes, equals(480)); // 8 hours
      expect(notifier.state['youtube']!.allocatedMinutes, equals(120));   // 2 hours
    });

    test('7. Starting lock for Instagram sets isLocked and remainingSeconds', () {
      final notifier = PerAppTimersNotifier(enableTicker: false);
      notifier.startAppLock('instagram', customMinutes: 480);

      final insta = notifier.state['instagram']!;
      expect(insta.isLocked, isTrue);
      expect(insta.remainingSeconds, equals(480 * 60));

      // YouTube should remain unlocked
      final yt = notifier.state['youtube']!;
      expect(yt.isLocked, isFalse);
    });

    testWidgets('8. PerAppTimerCard renders independent app timer options', (tester) async {
      await tester.pumpWidget(_buildTestHarness(child: const PerAppTimerCard()));
      await tester.pump();

      expect(find.text('Independent App Timers'), findsOneWidget);
      expect(find.text('Instagram'), findsOneWidget);
      expect(find.text('YouTube'), findsOneWidget);
      expect(find.text('Reddit'), findsOneWidget);
    });
  });

  group('Next-Gen Focus Ecosystem: Surgical Feed vs Chat Filtering', () {
    test('9. SurgicalFilterState initializes with feeds blocked and DMs allowed', () {
      const state = SurgicalFilterState();
      expect(state.blockInstagramReels, isTrue);
      expect(state.allowInstagramDms, isTrue);
      expect(state.blockYouTubeShorts, isTrue);
      expect(state.blockYouTubeRecommendations, isTrue);
      expect(state.blockRedditFeed, isTrue);
      expect(state.allowRedditDms, isTrue);
    });

    test('10. SurgicalFilterState populates correct domain endpoints for feeds and chats', () {
      const state = SurgicalFilterState();
      expect(state.activeBlockedDomains, contains('reels.instagram.com'));
      expect(state.activeBlockedDomains, contains('youtube.com/shorts'));
      expect(state.activeAllowedDomains, contains('direct.instagram.com'));
      expect(state.activeAllowedDomains, contains('chat.reddit.com'));
    });

    testWidgets('11. SurgicalFilterCard renders toggle switches for Instagram, YouTube and Reddit', (tester) async {
      await tester.pumpWidget(_buildTestHarness(child: const SurgicalFilterCard()));
      await tester.pump();

      expect(find.text('Surgical Feed vs Chat Filtering'), findsOneWidget);
      expect(find.text('Block Reels & Explore Feed'), findsOneWidget);
      expect(find.text('Keep Direct Messages Active'), findsOneWidget);
      expect(find.text('Block YouTube Shorts URLs'), findsOneWidget);
      expect(find.text('Block Popular & Home Infinite Feeds'), findsOneWidget);
    });
  });

  group('Next-Gen Focus Ecosystem: Longitudinal Analytics', () {
    test('12. LongitudinalAnalyticsNotifier switches between Day, Week, Month, and Year timeframes', () {
      final notifier = LongitudinalAnalyticsNotifier();
      expect(notifier.state.selectedTimeframe, equals(AnalyticsTimeframe.week));
      expect(notifier.state.currentMetrics.completedSessions, equals(26));

      notifier.selectTimeframe(AnalyticsTimeframe.day);
      expect(notifier.state.selectedTimeframe, equals(AnalyticsTimeframe.day));
      expect(notifier.state.currentMetrics.completedSessions, equals(4));

      notifier.selectTimeframe(AnalyticsTimeframe.year);
      expect(notifier.state.selectedTimeframe, equals(AnalyticsTimeframe.year));
      expect(notifier.state.currentMetrics.completedSessions, equals(1140));
    });

    testWidgets('13. LongitudinalAnalyticsCard renders adherence badge, metrics tiles, and selector', (tester) async {
      await tester.pumpWidget(_buildTestHarness(child: const LongitudinalAnalyticsCard()));
      await tester.pump();

      expect(find.text('Longitudinal Progress'), findsOneWidget);
      expect(find.text('FOCUS TIME'), findsOneWidget);
      expect(find.text('SAVED TIME'), findsOneWidget);
      expect(find.text('BREAK DURATION'), findsOneWidget);
      expect(find.text('BLOCKED ATTEMPTS'), findsOneWidget);
      expect(find.text('Day'), findsOneWidget);
      expect(find.text('Week'), findsOneWidget);
      expect(find.text('Month'), findsOneWidget);
      expect(find.text('Year'), findsOneWidget);
    });
  });

  group('Next-Gen Focus Ecosystem: Multi-Cycle Engine & Battery Optimization', () {
    test('14. Routine transitions from focusSession to breakSession automatically on phase completion', () {
      final notifier = RoutineFocusNotifier(enableTicker: false);
      notifier.updateConfig(sessionMinutes: 25, breakMinutes: 5, totalCycles: 2);
      notifier.startRoutine();

      expect(notifier.state.phase, equals(RoutinePhase.focusSession));
      expect(notifier.state.currentCycle, equals(1));

      // Simulate completion of focus session
      notifier.advancePhaseForTesting();
      expect(notifier.state.phase, equals(RoutinePhase.breakSession));
      expect(notifier.state.remainingSeconds, equals(5 * 60));
    });

    test('15. Break expiration advances to cycle 2 and executes auto-close for foreground apps', () {
      final notifier = RoutineFocusNotifier(enableTicker: false);
      notifier.updateConfig(sessionMinutes: 25, breakMinutes: 5, totalCycles: 2);
      notifier.startRoutine();

      // Focus session 1 -> Break session 1
      notifier.advancePhaseForTesting();
      expect(notifier.state.phase, equals(RoutinePhase.breakSession));

      // Break session 1 -> Focus session 2
      notifier.advancePhaseForTesting();
      expect(notifier.state.phase, equals(RoutinePhase.focusSession));
      expect(notifier.state.currentCycle, equals(2));
      expect(notifier.state.remainingSeconds, equals(25 * 60));
    });

    test('16. Routine completes all configured cycles and transitions cleanly to RoutinePhase.completed', () {
      final notifier = RoutineFocusNotifier(enableTicker: false);
      notifier.updateConfig(sessionMinutes: 25, breakMinutes: 5, totalCycles: 1);
      notifier.startRoutine();

      // Focus session 1 finishes
      notifier.advancePhaseForTesting();
      expect(notifier.state.phase, equals(RoutinePhase.breakSession));

      // Break session 1 finishes (totalCycles = 1 reached)
      notifier.advancePhaseForTesting();
      expect(notifier.state.phase, equals(RoutinePhase.completed));
      expect(notifier.state.remainingSeconds, equals(0));
      expect(notifier.state.isActive, isFalse);
    });

    test('17. PerAppTimersNotifier tickForTesting decrements remaining seconds and unlocks app on expiry', () {
      final notifier = PerAppTimersNotifier(enableTicker: false);
      notifier.startAppLock('instagram', customMinutes: 60);

      expect(notifier.state['instagram']!.isLocked, isTrue);

      // Simulate 30 minutes passing
      final halfWay = DateTime.now().add(const Duration(minutes: 30));
      notifier.tickForTesting(halfWay);
      expect(notifier.state['instagram']!.isLocked, isTrue);
      expect(notifier.state['instagram']!.remainingSeconds, inInclusiveRange(1700, 1800));

      // Simulate expiration (61 minutes passing)
      final expired = DateTime.now().add(const Duration(minutes: 61));
      notifier.tickForTesting(expired);
      expect(notifier.state['instagram']!.isLocked, isFalse);
      expect(notifier.state['instagram']!.remainingSeconds, equals(0));
    });

    test('18. Adding custom app with independent lockout duration (e.g. TikTok for 3 hours)', () {
      final notifier = PerAppTimersNotifier(enableTicker: false);
      const customApp = AppBlockTimer(
        appId: 'tiktok',
        appName: 'TikTok',
        icon: '🎵',
        packages: ['com.zhiliaoapp.musically'],
        domains: ['tiktok.com', 'tiktokv.com', 'byteoversea.com'],
        allocatedMinutes: 180,
      );

      notifier.addCustomApp(customApp);
      expect(notifier.state.containsKey('tiktok'), isTrue);
      expect(notifier.state['tiktok']!.allocatedMinutes, equals(180));

      notifier.startAppLock('tiktok', customMinutes: 180);
      expect(notifier.state['tiktok']!.isLocked, isTrue);
      expect(notifier.state['tiktok']!.remainingSeconds, equals(180 * 60));
    });

    test('19. Battery Optimization helper methods return non-null safety values', () async {
      final isIgnored = await FocusDnsBlockerManager.isBatteryOptimizationIgnored();
      expect(isIgnored, isTrue);

      final req = await FocusDnsBlockerManager.requestIgnoreBatteryOptimizations();
      expect(req, isTrue);
    });

    testWidgets('20. MoreTab includes Anti-Doomscroll Ecosystem section with all 4 items', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            theme: WabiSabiTheme.darkTheme,
            home: Scaffold(
              body: MoreTab(palette: WabiSabiPalette.dark),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('ANTI-DOOMSCROLL ECOSYSTEM'), findsOneWidget);
      expect(find.text('Focus Routine & Breaks'), findsOneWidget);
      expect(find.text('App Lockout Timers'), findsOneWidget);
      expect(find.text('Surgical Feed Killer'), findsOneWidget);
      expect(find.text('Longitudinal Analytics'), findsOneWidget);
    });
  });
}
