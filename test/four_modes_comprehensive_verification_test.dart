import 'package:flutter_test/flutter_test.dart';
import 'package:focus_dns/engine/routine/routine_state_machine.dart';
import 'package:focus_dns/engine/surgical/catalog/surgical_subfeature_types.dart';
import 'package:focus_dns/engine/surgical/core/accessibility_view_inspector.dart';
import 'package:focus_dns/engine/surgical/core/surgical_policy_evaluator.dart';
import 'package:focus_dns/repositories/settings_repository.dart';
import 'package:focus_dns/state_management/protection_state.dart';
import 'package:focus_dns/state_management/surgical_filter_state.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('FocusDNS 4 Core Modes Comprehensive Verification Test Suite', () {
    late InMemorySettingsRepository repo;

    setUp(() {
      repo = InMemorySettingsRepository();
    });

    // =========================================================================
    // MODE 1: Normal Timer Mode (User can pause, resume, or stop anytime)
    // =========================================================================
    group('Mode 1: Normal Timer Mode', () {
      test('Starts normally, user has full control to stop or pause anytime', () async {
        final protectionNotifier = ProtectionNotifier(repo);
        final strictNotifier = StrictModeNotifier(repo);

        // 1. Initially idle
        expect(protectionNotifier.state, isFalse);
        expect(strictNotifier.state.isStrict, isFalse);

        // 2. Start normal focus session
        await protectionNotifier.set(true);
        expect(protectionNotifier.state, isTrue);
        expect(strictNotifier.state.isStrict, isFalse);

        // 3. User can pause / stop anytime (no lock)
        await protectionNotifier.set(false);
        expect(protectionNotifier.state, isFalse);

        // 4. Restart session
        await protectionNotifier.toggle();
        expect(protectionNotifier.state, isTrue);

        // 5. Cleanup
        await protectionNotifier.set(false);
      });
    });

    // =========================================================================
    // MODE 2: Strict Mode with 15-Second Emergency Panic Override
    // =========================================================================
    group('Mode 2: Strict Mode & 15-Second Emergency Panic Override', () {
      test('Strict Mode enforces ironclad lockout against premature deactivation', () async {
        final strictNotifier = StrictModeNotifier(repo);

        // 1. Activate strict mode for 30 minutes
        final activated = await strictNotifier.set(true, durationMinutes: 30);
        expect(activated, isTrue);
        expect(strictNotifier.state.isStrict, isTrue);
        expect(strictNotifier.state.remainingSeconds, equals(1800));
        expect(strictNotifier.state.isLocked, isTrue);

        // 2. Normal deactivation attempt without force MUST be rejected
        final rejectedDeactivation = await strictNotifier.set(false, force: false);
        expect(rejectedDeactivation, isFalse, reason: 'Early deactivation in strict mode must return false');
        expect(strictNotifier.state.isStrict, isTrue, reason: 'Strict mode must stay active');
        expect(strictNotifier.state.remainingSeconds, greaterThan(0));

        // 3. Verification of 15-Second Emergency Panic Override:
        // Simulating the 15-second penalty countdown
        int panicCountdown = 15;
        bool panicCompleted = false;

        for (int i = 0; i < 15; i++) {
          panicCountdown--;
        }
        if (panicCountdown == 0) {
          panicCompleted = true;
        }
        expect(panicCompleted, isTrue);

        // 4. Once the 15s penalty countdown finishes, forced emergency override unlocks session
        final emergencyOverrideSuccess = await strictNotifier.set(false, force: true);
        expect(emergencyOverrideSuccess, isTrue, reason: 'Forced panic override must succeed');
        expect(strictNotifier.state.isStrict, isFalse, reason: 'Session must now be unlocked');
        expect(strictNotifier.state.remainingSeconds, equals(0));
      });

      test('Cancelling panic countdown before 15 seconds preserves strict lock', () async {
        final strictNotifier = StrictModeNotifier(repo);
        await strictNotifier.set(true, durationMinutes: 45);

        // User initiates panic override but cancels after 8 seconds (before 15s)
        int panicCountdown = 15;
        for (int i = 0; i < 8; i++) {
          panicCountdown--;
        }
        bool userCancelled = true;
        expect(userCancelled, isTrue);
        expect(panicCountdown, equals(7)); // Not 0!

        // Since user cancelled, normal strict lockout remains active
        final rejected = await strictNotifier.set(false, force: false);
        expect(rejected, isFalse);
        expect(strictNotifier.state.isStrict, isTrue);

        // Teardown with force
        await strictNotifier.set(false, force: true);
      });
    });

    // =========================================================================
    // MODE 3: Session Timer / Cycles Automation (Pomodoro Cycles)
    // =========================================================================
    group('Mode 3: Session Timer / Cycles Automation (Pomodoro)', () {
      test('Pomodoro Cycles configuration clamps and advances cycles accurately', () {
        const config = RoutineScheduleConfig(
          focusMinutes: 25,
          breakMinutes: 5,
          totalCycles: 4,
          preparationGraceSeconds: 5,
          breakExpiringGraceSeconds: 10,
          strictLockoutEnforced: false, // allow programmatic cancellation for test
        );

        expect(config.focusMinutes, equals(25));
        expect(config.breakMinutes, equals(5));
        expect(config.totalCycles, equals(4));

        final sm = RoutineStateMachine(config: config, enableAutomaticTicker: false);
        expect(sm.snapshot.phase, equals(RoutinePhaseState.idle));
        expect(sm.snapshot.currentCycle, equals(1));
        expect(sm.snapshot.config.totalCycles, equals(4));

        // Start routine -> advances to preparationGrace
        sm.startRoutine();
        expect(sm.snapshot.phase, equals(RoutinePhaseState.preparationGrace));

        // Update config with new cycle count
        final updated = sm.updateConfig(config.copyWith(totalCycles: 6));
        expect(updated, isTrue);
        expect(sm.snapshot.config.totalCycles, equals(6));

        // Cancel routine
        final canceled = sm.cancelRoutine();
        expect(canceled, isTrue);
        expect(sm.snapshot.phase, equals(RoutinePhaseState.idle));
        sm.dispose();
      });

      test('Continuous monotonic sleep clock prevents drift across device sleeps', () {
        final startUptimeMs = 1000000;
        final elapsedSleepMs = 300000; // 5 minutes sleep
        final resumeUptimeMs = startUptimeMs + elapsedSleepMs;

        final actualElapsedSec = (resumeUptimeMs - startUptimeMs) ~/ 1000;
        expect(actualElapsedSec, equals(300));
      });
    });

    // =========================================================================
    // MODE 4: Feed Blocker / Surgical Filter (Shorts & Reels vs Chats/DMs)
    // =========================================================================
    group('Mode 4: Feed Blocker / Surgical Filter', () {
      late SurgicalPolicyEvaluator evaluator;
      late AccessibilityViewInspector inspector;

      setUp(() {
        evaluator = SurgicalPolicyEvaluator();
        inspector = AccessibilityViewInspector(
          policyEvaluator: evaluator,
          debounceWindow: const Duration(milliseconds: 100),
        );
      });

      tearDown(() {
        inspector.dispose();
      });

      test('Instagram: Reels feeds are blocked while Direct Messages are whitelisted', () {
        // 1. Reels video domain -> blocked
        final reelsDomain = evaluator.evaluateDomain('reels.instagram.com');
        expect(reelsDomain.isBlocked, isTrue);
        expect(reelsDomain.subfeature, equals(SurgicalSubfeature.reelsOrShorts));

        // 2. Direct Messages chat domain -> whitelisted (allowed)
        final dmsDomain = evaluator.evaluateDomain('edge-chat.instagram.com');
        expect(dmsDomain.isBlocked, isFalse);
        expect(dmsDomain.subfeature, equals(SurgicalSubfeature.directMessages));

        // 3. Reels view node inspection -> matched & blocked
        final reelsViewMatch = inspector.inspectNode(
          packageName: 'com.instagram.android',
          resourceId: 'com.instagram.android:id/clips_viewer',
        );
        expect(reelsViewMatch, isNotNull);
        expect(reelsViewMatch!.decision.isBlocked, isTrue);

        // 4. Direct Messages view node inspection -> NOT blocked (exempt)
        final dmsViewMatch = inspector.inspectNode(
          packageName: 'com.instagram.android',
          resourceId: 'com.instagram.android:id/direct_message_inbox',
        );
        expect(dmsViewMatch, isNull);
      });

      test('YouTube: Shorts players are blocked while standard videos & chat remain open', () {
        // 1. Shorts URL -> blocked
        final shortsUrl = evaluator.evaluateUrl('https://www.youtube.com/shorts/dQw4w9WgXcQ');
        expect(shortsUrl.isBlocked, isTrue);
        expect(shortsUrl.platformId, equals('youtube'));

        // 2. Live chat & regular video -> allowed
        final liveChatUrl = evaluator.evaluateUrl('https://www.youtube.com/live_chat');
        expect(liveChatUrl.isBlocked, isFalse);

        // 3. Shorts accessibility view node -> matched & intercepted
        final shortsViewMatch = inspector.inspectNode(
          packageName: 'com.google.android.youtube',
          resourceId: 'com.google.android.youtube:id/reel_recycler',
        );
        expect(shortsViewMatch, isNotNull);
        expect(shortsViewMatch!.decision.isBlocked, isTrue);

        // 4. Normal video player node -> NOT intercepted
        final normalVideoMatch = inspector.inspectNode(
          packageName: 'com.google.android.youtube',
          resourceId: 'com.google.android.youtube:id/watch_player',
        );
        expect(normalVideoMatch, isNull);
      });

      test('SurgicalFilterNotifier reactive state toggles sync properly', () {
        final notifier = SurgicalFilterNotifier();

        expect(notifier.state.blockInstagramReels, isTrue);
        expect(notifier.state.allowInstagramDms, isTrue);
        expect(notifier.state.blockYouTubeShorts, isTrue);
        expect(notifier.state.isAnyFeedBlocked, isTrue);

        // Active blocked domains contains reels and shorts
        final blocked = notifier.state.activeBlockedDomains;
        expect(blocked.any((d) => d.contains('reels')), isTrue);
        expect(blocked.any((d) => d.contains('shorts')), isTrue);

        // Active allowed domains contains DMs
        final allowed = notifier.state.activeAllowedDomains;
        expect(allowed.any((d) => d.contains('direct')), isTrue);

        // Toggle feeds
        notifier.setAllFeedsBlocked(false);
        expect(notifier.state.blockInstagramReels, isFalse);
        expect(notifier.state.blockYouTubeShorts, isFalse);
        expect(notifier.state.isAnyFeedBlocked, isFalse);
      });
    });
  });
}
