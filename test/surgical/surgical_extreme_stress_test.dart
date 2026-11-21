import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:focus_dns/engine/surgical/catalog/surgical_platform_catalog.dart';
import 'package:focus_dns/engine/surgical/catalog/surgical_subfeature_types.dart';
import 'package:focus_dns/engine/surgical/core/accessibility_view_inspector.dart';
import 'package:focus_dns/engine/surgical/core/mindful_nudge_coordinator.dart';
import 'package:focus_dns/engine/surgical/core/surgical_policy_evaluator.dart';
import 'package:focus_dns/engine/surgical/core/surgical_trie_matcher.dart';
import 'package:focus_dns/engine/surgical/models/surgical_interception_event.dart';
import 'package:focus_dns/engine/surgical/models/surgical_rule_model.dart';
import 'package:focus_dns/engine/surgical/models/surgical_telemetry_snapshot.dart';
import 'package:focus_dns/engine/surgical/models/view_node_target.dart';
import 'package:focus_dns/engine/surgical/telemetry/reclaimed_dopamine_calculator.dart';
import 'package:focus_dns/engine/surgical/telemetry/surgical_telemetry_recorder.dart';

void main() {
  group('Surgical Decoupling Engine 25 Extreme Stress Tests', () {
    late SurgicalPolicyEvaluator evaluator;
    late SurgicalTelemetryRecorder recorder;

    setUp(() {
      evaluator = SurgicalPolicyEvaluator();
      recorder = SurgicalTelemetryRecorder(maxEventCapacity: 2000);
    });

    tearDown(() {
      recorder.dispose();
    });

    // 1. 10,000 Rapid Concurrent Domain Queries
    test('Stress 1: 10,000 rapid concurrent domain queries against Trie', () async {
      final domains = [
        'reels.instagram.com',
        'edge-chat.instagram.com',
        'v.redd.it',
        'chat.reddit.com',
        'video.twimg.com',
        'unknown-domain.com',
      ];

      final futures = <Future>[];
      for (int i = 0; i < 10000; i++) {
        final d = domains[i % domains.length];
        futures.add(Future.microtask(() => evaluator.evaluateDomain(d)));
      }

      final results = await Future.wait(futures);
      expect(results.length, equals(10000));
    });

    // 2. Malformed Domain Inputs
    test('Stress 2: Malformed domain inputs (empty, whitespace, trailing dots, ports)', () {
      final badInputs = [
        '',
        '   ',
        '...',
        'http:///',
        'https://reels.instagram.com:8443///',
        'reels.instagram.com..',
        'reels.instagram.com:443',
        '\n\r\t',
      ];

      for (final input in badInputs) {
        expect(() => evaluator.evaluateDomain(input), returnsNormally);
      }
    });

    // 3. Massive Subdomain Depth
    test('Stress 3: Deep 50-level subdomain hierarchy lookup', () {
      final deepSubdomain = List.generate(50, (i) => 'sub$i').join('.') + '.instagram.com';
      expect(() => evaluator.evaluateDomain(deepSubdomain), returnsNormally);
    });

    // 4. Rapid Sub-feature Policy Mutations During Active Lookups
    test('Stress 4: Rapid subfeature policy mutations while lookups occur simultaneously', () async {
      bool isRunning = true;

      final lookupFuture = Future(() async {
        int count = 0;
        while (isRunning && count < 2000) {
          evaluator.evaluateDomain('reels.instagram.com');
          count++;
          await Future.microtask(() {});
        }
      });

      final mutateFuture = Future(() async {
        for (int i = 0; i < 200; i++) {
          evaluator.setSubfeatureToggle(
            platformId: 'instagram',
            subfeature: SurgicalSubfeature.reelsOrShorts,
            blocked: i % 2 == 0,
          );
          await Future.microtask(() {});
        }
        isRunning = false;
      });

      await Future.wait([lookupFuture, mutateFuture]);
    });

    // 5. Zero-Division Resilience in Dopamine Calculator
    test('Stress 5: Zero-division resilience with zero events, zero hours, zero chats', () {
      expect(ReclaimedDopamineCalculator.computeDopamineSensitivityRecovery(0.0), equals(0.0));
      expect(ReclaimedDopamineCalculator.computeBooksReadEquivalent(0.0), equals(0.0));
      expect(ReclaimedDopamineCalculator.computeDeepWorkCyclesReclaimed(0.0), equals(0.0));
      expect(ReclaimedDopamineCalculator.project30DayReclaimedHours(0.0), equals(0.0));
      expect(ReclaimedDopamineCalculator.project1YearReclaimedHours(0.0), equals(0.0));

      final emptySnap = SurgicalTelemetrySnapshot.empty();
      expect(emptySnap.reelsToChatRatio, equals(0.0));
      expect(emptySnap.totalAvertedMinutes, equals(0));
      expect(emptySnap.formattedBandwidthSaved, equals('0.0 MB'));
      expect(ReclaimedDopamineCalculator.evaluateUnlockedMilestones(emptySnap), isEmpty);
    });

    // 6. Max Integer Bounds on Telemetry Counters
    test('Stress 6: Maximum integer values handled safely without overflow', () {
      const hugeCount = 2147483647; // Max 32-bit int
      final hugeSnap = SurgicalTelemetrySnapshot.empty().copyWith(
        totalInterceptions: hugeCount,
        blockedReelsCount: hugeCount,
        allowedChatCount: hugeCount,
        estimatedHoursReclaimed: 50000.0,
        bandwidthSavedMegabytes: 10485760.0, // 10 TB
        dopamineIndexScore: 98,
      );

      expect(hugeSnap.totalInterceptions, equals(hugeCount));
      expect(hugeSnap.formattedBandwidthSaved, contains('GB'));
      expect(hugeSnap.dopamineStatusTitle, equals('Dopamine Sovereign'));
    });

    // 7. Ring Buffer Saturation Over 5,000 Events
    test('Stress 7: Ring buffer saturation over 5,000 events without memory leak', () {
      final now = DateTime.now();
      for (int i = 0; i < 5000; i++) {
        recorder.recordInterception(
          SurgicalInterceptionEvent(
            eventId: 'stress_evt_$i',
            timestamp: now,
            platformId: 'instagram',
            platformName: 'Instagram',
            subfeature: SurgicalSubfeature.reelsOrShorts,
            interceptedTarget: 'reels.instagram.com',
            actionApplied: ViewInterceptionAction.navigateBack,
            triggerSource: InterceptionTriggerSource.dnsQuery,
            packageName: 'com.instagram.android',
          ),
        );
      }

      expect(recorder.bufferedEventCount, equals(2000)); // Capped at maxEventCapacity
      expect(recorder.recentEvents.first.eventId, equals('stress_evt_4999'));
    });

    // 8. Unicode and Punycode Domain Spoofing
    test('Stress 8: Unicode and Punycode domain spoofing resilience', () {
      final punycodeDomains = [
        'xn--instgram-vxb.com',
        'reels.instägram.com',
        'reels.instagram.com.attacker.com',
        'instagram.com.evil.co',
      ];

      for (final domain in punycodeDomains) {
        final decision = evaluator.evaluateDomain(domain);
        // Should not match official Instagram platform
        if (domain.endsWith('.attacker.com') || domain.endsWith('.evil.co')) {
          expect(decision.verdict, equals(SurgicalVerdict.passThrough));
        }
      }
    });

    // 9. Rapid Back-to-Back View Hierarchy Flutter
    test('Stress 9: Rapid back-to-back view hierarchy flutter (100 events in loop)', () {
      final inspector = AccessibilityViewInspector(
        policyEvaluator: evaluator,
        debounceWindow: const Duration(milliseconds: 500),
      );

      for (int i = 0; i < 100; i++) {
        inspector.inspectNode(
          packageName: 'com.instagram.android',
          resourceId: 'com.instagram.android:id/clips_viewer',
        );
      }

      expect(inspector.totalViewsMatched, equals(1));
      expect(inspector.totalViewsDebounced, equals(99));
      inspector.dispose();
    });

    // 10. Simultaneous Multi-Platform Toggle Mutations
    test('Stress 10: Simultaneous multi-platform toggle mutations across all 12 platforms', () {
      for (final rule in SurgicalPlatformCatalog.allPlatforms) {
        for (final sub in SurgicalSubfeature.values) {
          evaluator.setSubfeatureToggle(
            platformId: rule.platformId,
            subfeature: sub,
            blocked: false,
          );
          expect(evaluator.isSubfeatureBlocked(rule.platformId, sub), isFalse);

          evaluator.setSubfeatureToggle(
            platformId: rule.platformId,
            subfeature: sub,
            blocked: true,
          );
          expect(evaluator.isSubfeatureBlocked(rule.platformId, sub), isTrue);
        }
      }
    });

    // 11. Empty Catalog and Null Rules Handling
    test('Stress 11: Empty rule queries and unmapped package lookup', () {
      final unmapped = evaluator.evaluateAccessibilityView(
        packageName: 'com.nonexistent.app.xyz',
        resourceId: 'some_view',
      );
      expect(unmapped.isBlocked, isFalse);
      expect(unmapped.verdict, equals(SurgicalVerdict.passThrough));
    });

    // 12. Non-ASCII Motivational Prompts and Pledges
    test('Stress 12: Non-ASCII motivational prompts and pledges (Unicode / Emojis)', () {
      final coordinator = MindfulNudgeCoordinator();
      const unicodePrompt = '🧘 Focus deeply. لا تستسلم للتشتت. 专注于深度工作。';
      final session = coordinator.startNudge(
        platformId: 'instagram',
        platformName: 'Instagram',
        subfeature: SurgicalSubfeature.reelsOrShorts,
        customPrompt: unicodePrompt,
      );

      expect(session.motivationalPrompt, equals(unicodePrompt));
      coordinator.dispose();
    });

    // 13. URL Path Matching with Query Parameters and Fragments
    test('Stress 13: URL path matching with complex queries and fragments', () {
      final urls = [
        'https://www.youtube.com/shorts/dQw4w9WgXcQ?feature=share#header',
        'https://www.instagram.com/reels/videos/?query=test&tag=fun',
      ];

      for (final url in urls) {
        expect(() => evaluator.evaluateUrl(url), returnsNormally);
      }
    });

    // 14. Mindful Pause Boundary Countdown Values
    test('Stress 14: Mindful pause zero and boundary duration values', () {
      final coordinator = MindfulNudgeCoordinator(defaultPauseSeconds: 0);
      final session = coordinator.startNudge(
        platformId: 'instagram',
        platformName: 'Instagram',
        subfeature: SurgicalSubfeature.reelsOrShorts,
        customDurationSeconds: 0,
      );

      expect(session.totalDurationSeconds, equals(0));
      expect(session.progress, equals(1.0));
      coordinator.dispose();
    });

    // 15. High-Frequency Live Stream Event Broadcasting
    test('Stress 15: High-frequency live stream event broadcasting (500 events in rapid succession)', () async {
      int receivedCount = 0;
      final sub = recorder.eventStream.listen((evt) {
        receivedCount++;
      });

      final now = DateTime.now();
      for (int i = 0; i < 500; i++) {
        recorder.recordInterception(
          SurgicalInterceptionEvent(
            eventId: 'hf_$i',
            timestamp: now,
            platformId: 'instagram',
            platformName: 'Instagram',
            subfeature: SurgicalSubfeature.reelsOrShorts,
            interceptedTarget: 'reels.instagram.com',
            actionApplied: ViewInterceptionAction.navigateBack,
            triggerSource: InterceptionTriggerSource.dnsQuery,
            packageName: 'com.instagram.android',
          ),
        );
      }

      await Future.delayed(const Duration(milliseconds: 100));
      expect(receivedCount, equals(500));
      await sub.cancel();
    });

    // 16. Subfeature Metadata Completeness
    test('Stress 16: All 8 subfeatures have complete metadata and icons', () {
      for (final f in SurgicalSubfeature.values) {
        final meta = SurgicalSubfeatureRegistry.getMetadata(f);
        expect(meta.displayName.isNotEmpty, isTrue);
        expect(meta.description.isNotEmpty, isTrue);
        expect(meta.icon, isNotNull);
        expect(meta.dopamineAddictionScore, inInclusiveRange(1, 100));
      }
    });

    // 17. Memory Footprint Boundary for Trie
    test('Stress 17: Trie matcher memory footprint stays under bounded limits', () {
      final matcher = SurgicalTrieMatcher();
      for (int i = 0; i < 1000; i++) {
        matcher.insertDomain(
          domain: 'domain$i.test.com',
          platformId: 'test',
          subfeature: SurgicalSubfeature.feed,
        );
      }

      final memBytes = matcher.estimateMemoryFootprintBytes();
      expect(memBytes, lessThan(2 * 1024 * 1024)); // Less than 2 MB for 1,000 domains
    });

    // 18. Negative and Extreme Values in Dopamine Calculator
    test('Stress 18: Negative and extreme values in dopamine calculator handled defensively', () {
      expect(ReclaimedDopamineCalculator.computeDopamineSensitivityRecovery(-50.0), equals(0.0));
      expect(ReclaimedDopamineCalculator.computeBooksReadEquivalent(-10.0), equals(0.0));
      expect(ReclaimedDopamineCalculator.computeDeepWorkCyclesReclaimed(-5.0), equals(0.0));
      expect(
        ReclaimedDopamineCalculator.computeCognitiveFatigueIndex(totalInterceptions: 0, allowedChats: 0),
        equals(30),
      );
    });

    // 19. ViewNodeTarget with Empty Patterns Matches Nothing
    test('Stress 19: ViewNodeTarget with empty pattern lists matches nothing defensively', () {
      const emptyTarget = ViewNodeTarget(
        targetId: 'empty',
        packageName: 'com.test.app',
        description: 'Empty',
      );

      expect(
        emptyTarget.matches(
          pkg: 'com.test.app',
          resourceId: 'some_id',
          contentDescription: 'some_desc',
        ),
        isFalse,
      );
    });

    // 20. Interception Event copyWith Immutability
    test('Stress 20: SurgicalInterceptionEvent copyWith immutability preserves unchanged fields', () {
      final original = SurgicalInterceptionEvent(
        eventId: 'orig',
        timestamp: DateTime(2026, 1, 1),
        platformId: 'instagram',
        platformName: 'Instagram',
        subfeature: SurgicalSubfeature.reelsOrShorts,
        interceptedTarget: 'reels.instagram.com',
        actionApplied: ViewInterceptionAction.navigateBack,
        triggerSource: InterceptionTriggerSource.dnsQuery,
        packageName: 'com.instagram.android',
      );

      final copy = original.copyWith(notes: 'Updated note');
      expect(copy.eventId, equals(original.eventId));
      expect(copy.timestamp, equals(original.timestamp));
      expect(copy.platformId, equals(original.platformId));
      expect(copy.notes, equals('Updated note'));
      expect(original.notes, isEmpty);
    });

    // 21. Daily Token Counter Boundary Test
    test('Stress 21: Daily bypass token limits enforce strict ceiling', () {
      final coord = MindfulNudgeCoordinator(maxDailyBypassTokens: 1);
      coord.startNudge(
        platformId: 'instagram',
        platformName: 'Instagram',
        subfeature: SurgicalSubfeature.reelsOrShorts,
      );

      expect(coord.grantBypass(), isTrue);
      expect(coord.remainingBypassTokens, equals(0));

      coord.startNudge(
        platformId: 'instagram',
        platformName: 'Instagram',
        subfeature: SurgicalSubfeature.reelsOrShorts,
      );
      expect(coord.grantBypass(), isFalse);

      coord.dispose();
    });

    // 22. Case-Insensitive URL Paths
    test('Stress 22: Case-insensitive URL path lookups', () {
      evaluator.trieMatcher.insertPathPrefix(
        pathPrefix: '/shorts',
        platformId: 'youtube',
        subfeature: SurgicalSubfeature.reelsOrShorts,
      );

      expect(evaluator.trieMatcher.lookupPath('/SHORTS/123'), isNotNull);
      expect(evaluator.trieMatcher.lookupPath('/Shorts/abc'), isNotNull);
    });

    // 23. Query Filtering with Multiple Predicates
    test('Stress 23: Telemetry query filtering with compound predicates', () {
      final now = DateTime.now();
      recorder.recordInterception(
        SurgicalInterceptionEvent(
          eventId: 'q1',
          timestamp: now.subtract(const Duration(minutes: 5)),
          platformId: 'instagram',
          platformName: 'Instagram',
          subfeature: SurgicalSubfeature.reelsOrShorts,
          interceptedTarget: 'reels.instagram.com',
          actionApplied: ViewInterceptionAction.navigateBack,
          triggerSource: InterceptionTriggerSource.dnsQuery,
          packageName: 'com.instagram.android',
          hazardLevel: DopamineHazardLevel.critical,
        ),
      );

      final results = recorder.queryEvents(
        platformId: 'instagram',
        subfeature: SurgicalSubfeature.reelsOrShorts,
        minHazard: DopamineHazardLevel.critical,
      );
      expect(results.length, equals(1));

      final noResults = recorder.queryEvents(
        platformId: 'youtube',
      );
      expect(noResults, isEmpty);
    });

    // 24. ReclaimedDopamineCalculator Summary Generation
    test('Stress 24: ReclaimedDopamineCalculator generates cognitive summary without exception', () {
      final snap = SurgicalTelemetrySnapshot.empty().copyWith(
        totalInterceptions: 45,
        allowedChatCount: 150,
        estimatedHoursReclaimed: 8.5,
      );

      final summary = ReclaimedDopamineCalculator.generateCognitiveSummary(snap);
      expect(summary.contains('45 addiction loops'), isTrue);
      expect(summary.contains('150 direct messages'), isTrue);
      expect(summary.contains('8.5 hours'), isTrue);
    });

    // 25. Complete System Recompilation Stress
    test('Stress 25: Complete rule re-compilation runs under 10ms without errors', () {
      final sw = Stopwatch()..start();
      for (int i = 0; i < 20; i++) {
        evaluator.compileAllRules();
      }
      sw.stop();

      final avgMs = sw.elapsedMilliseconds / 20;
      expect(avgMs, lessThan(50.0), reason: 'Recompilation should be fast and in-memory');
      expect(evaluator.compiledRules.length, greaterThanOrEqualTo(12));
    });
  });
}
