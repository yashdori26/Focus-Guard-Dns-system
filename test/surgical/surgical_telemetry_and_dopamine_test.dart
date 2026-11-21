import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:focus_dns/engine/surgical/catalog/surgical_subfeature_types.dart';
import 'package:focus_dns/engine/surgical/models/surgical_interception_event.dart';
import 'package:focus_dns/engine/surgical/models/surgical_telemetry_snapshot.dart';
import 'package:focus_dns/engine/surgical/models/view_node_target.dart';
import 'package:focus_dns/engine/surgical/telemetry/reclaimed_dopamine_calculator.dart';
import 'package:focus_dns/engine/surgical/telemetry/surgical_telemetry_recorder.dart';

void main() {
  group('1. Surgical Interception Event Tests', () {
    test('Calculates hazard level and default seconds saved accurately', () {
      expect(
        SurgicalInterceptionEvent.calculateHazardLevel(SurgicalSubfeature.reelsOrShorts),
        equals(DopamineHazardLevel.critical),
      );
      expect(
        SurgicalInterceptionEvent.calculateHazardLevel(SurgicalSubfeature.feed),
        equals(DopamineHazardLevel.high),
      );
      expect(
        SurgicalInterceptionEvent.calculateHazardLevel(SurgicalSubfeature.directMessages),
        equals(DopamineHazardLevel.mild),
      );

      expect(
        SurgicalInterceptionEvent.defaultSecondsSaved(SurgicalSubfeature.reelsOrShorts),
        equals(300),
      );
      expect(
        SurgicalInterceptionEvent.defaultSecondsSaved(SurgicalSubfeature.feed),
        equals(240),
      );
    });

    test('Event JSON serialization round-trip', () {
      final now = DateTime.now();
      final event = SurgicalInterceptionEvent(
        eventId: 'evt_test_123',
        timestamp: now,
        platformId: 'instagram',
        platformName: 'Instagram',
        subfeature: SurgicalSubfeature.reelsOrShorts,
        interceptedTarget: 'reels.instagram.com',
        actionApplied: ViewInterceptionAction.showMindfulNudge,
        triggerSource: InterceptionTriggerSource.dnsQuery,
        packageName: 'com.instagram.android',
        viewResourceId: 'clips_viewer',
        estimatedSecondsSaved: 300,
        estimatedBytesBlocked: 3145728,
        hazardLevel: DopamineHazardLevel.critical,
        userBypassGranted: false,
        notes: 'Test event',
      );

      final json = event.toJson();
      final restored = SurgicalInterceptionEvent.fromJson(json);

      expect(restored.eventId, equals(event.eventId));
      expect(restored.platformId, equals('instagram'));
      expect(restored.subfeature, equals(SurgicalSubfeature.reelsOrShorts));
      expect(restored.interceptedTarget, equals('reels.instagram.com'));
      expect(restored.actionApplied, equals(ViewInterceptionAction.showMindfulNudge));
      expect(restored.triggerSource, equals(InterceptionTriggerSource.dnsQuery));
      expect(restored.estimatedSecondsSaved, equals(300));
      expect(restored.hazardLevel, equals(DopamineHazardLevel.critical));
    });
  });

  group('2. Surgical Telemetry Snapshot Tests', () {
    test('Computes aggregate snapshot from event list accurately', () {
      final now = DateTime.now();
      final events = [
        SurgicalInterceptionEvent(
          eventId: 'e1',
          timestamp: now,
          platformId: 'instagram',
          platformName: 'Instagram',
          subfeature: SurgicalSubfeature.reelsOrShorts,
          interceptedTarget: 'reels.instagram.com',
          actionApplied: ViewInterceptionAction.navigateBack,
          triggerSource: InterceptionTriggerSource.dnsQuery,
          packageName: 'com.instagram.android',
          estimatedSecondsSaved: 300,
          estimatedBytesBlocked: 2097152,
        ),
        SurgicalInterceptionEvent(
          eventId: 'e2',
          timestamp: now,
          platformId: 'youtube',
          platformName: 'YouTube',
          subfeature: SurgicalSubfeature.reelsOrShorts,
          interceptedTarget: 'googlevideo.com',
          actionApplied: ViewInterceptionAction.navigateBack,
          triggerSource: InterceptionTriggerSource.dnsQuery,
          packageName: 'com.google.android.youtube',
          estimatedSecondsSaved: 300,
          estimatedBytesBlocked: 2097152,
        ),
        SurgicalInterceptionEvent(
          eventId: 'e3',
          timestamp: now,
          platformId: 'reddit',
          platformName: 'Reddit',
          subfeature: SurgicalSubfeature.feed,
          interceptedTarget: 'v.redd.it',
          actionApplied: ViewInterceptionAction.navigateBack,
          triggerSource: InterceptionTriggerSource.dnsQuery,
          packageName: 'com.reddit.frontpage',
          estimatedSecondsSaved: 240,
          estimatedBytesBlocked: 1048576,
        ),
      ];

      final snapshot = SurgicalTelemetrySnapshot.fromEvents(
        events: events,
        allowedChats: 10,
        allowedSearches: 5,
        activePlatforms: 12,
      );

      expect(snapshot.totalInterceptions, equals(3));
      expect(snapshot.blockedReelsCount, equals(2));
      expect(snapshot.blockedFeedCount, equals(1));
      expect(snapshot.allowedChatCount, equals(10));
      expect(snapshot.allowedSearchCount, equals(5));
      expect(snapshot.estimatedHoursReclaimed, greaterThan(0.2));
      expect(snapshot.bandwidthSavedMegabytes, greaterThan(4.0));
      expect(snapshot.reelsToChatRatio, equals(0.2));
      expect(snapshot.dopamineIndexScore, greaterThanOrEqualTo(50));
    });

    test('Dopamine status title matches index score tier', () {
      final snapSovereign = SurgicalTelemetrySnapshot.empty().copyWith(dopamineIndexScore: 95);
      expect(snapSovereign.dopamineStatusTitle, equals('Dopamine Sovereign'));

      final snapMinimalist = SurgicalTelemetrySnapshot.empty().copyWith(dopamineIndexScore: 80);
      expect(snapMinimalist.dopamineStatusTitle, equals('Digital Minimalist'));

      final snapShield = SurgicalTelemetrySnapshot.empty().copyWith(dopamineIndexScore: 65);
      expect(snapShield.dopamineStatusTitle, equals('Focus Shield Active'));
    });
  });

  group('3. Reclaimed Dopamine Calculator & Milestones Tests', () {
    test('Calculates dopamine sensitivity recovery logarithmic curve', () {
      expect(ReclaimedDopamineCalculator.computeDopamineSensitivityRecovery(0), equals(0.0));
      final rec24h = ReclaimedDopamineCalculator.computeDopamineSensitivityRecovery(24.0);
      expect(rec24h, closeTo(63.2, 0.5));

      final rec72h = ReclaimedDopamineCalculator.computeDopamineSensitivityRecovery(72.0);
      expect(rec72h, closeTo(95.0, 0.5));
    });

    test('Computes books read equivalent and deep work cycles accurately', () {
      final books10h = ReclaimedDopamineCalculator.computeBooksReadEquivalent(10.0);
      expect(books10h, greaterThan(1.0));

      final cycles6h = ReclaimedDopamineCalculator.computeDeepWorkCyclesReclaimed(6.0);
      expect(cycles6h, equals(4.0)); // 6h / 1.5h = 4 cycles
    });

    test('Projects 30-day and 1-year reclaimed time based on daily average', () {
      const daily = 1.5;
      expect(ReclaimedDopamineCalculator.project30DayReclaimedHours(daily), equals(45.0));
      expect(ReclaimedDopamineCalculator.project1YearReclaimedHours(daily), closeTo(547.8, 1.0));
    });

    test('Evaluates milestone unlock criteria correctly', () {
      final snap = SurgicalTelemetrySnapshot.empty().copyWith(
        totalInterceptions: 60,
        blockedReelsCount: 55,
        estimatedHoursReclaimed: 22.0,
        allowedChatCount: 120,
        blockedFeedCount: 15,
      );

      final milestones = ReclaimedDopamineCalculator.evaluateUnlockedMilestones(snap);
      final milestoneTypes = milestones.map((m) => m.milestone).toList();

      expect(milestoneTypes, contains(DopamineMilestone.firstSever));
      expect(milestoneTypes, contains(DopamineMilestone.reelsNemesis));
      expect(milestoneTypes, contains(DopamineMilestone.timeReclaimer));
      expect(milestoneTypes, contains(DopamineMilestone.attentionGuardian));
      expect(milestoneTypes, contains(DopamineMilestone.pureCommunicator));
    });
  });

  group('4. Surgical Telemetry Recorder Tests', () {
    late SurgicalTelemetryRecorder recorder;

    setUp(() {
      SharedPreferences.setMockInitialValues({});
      recorder = SurgicalTelemetryRecorder(maxEventCapacity: 10);
    });

    tearDown(() {
      recorder.dispose();
    });

    test('Ring buffer adheres strictly to max capacity (FIFO eviction)', () {
      final now = DateTime.now();
      for (int i = 0; i < 15; i++) {
        recorder.recordInterception(
          SurgicalInterceptionEvent(
            eventId: 'evt_$i',
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

      expect(recorder.bufferedEventCount, equals(10));
      final recent = recorder.recentEvents;
      expect(recent.first.eventId, equals('evt_14')); // newest first
      expect(recent.last.eventId, equals('evt_5')); // oldest retained
    });

    test('Records allowed communication and updates snapshot stream', () async {
      recorder.recordAllowedCommunication(platformId: 'instagram', isChat: true, count: 5);
      recorder.recordAllowedCommunication(platformId: 'youtube', isChat: false, count: 2);

      expect(recorder.allowedChatCount, equals(5));
      expect(recorder.allowedSearchCount, equals(2));

      final snap = recorder.computeCurrentSnapshot();
      expect(snap.allowedChatCount, equals(5));
      expect(snap.allowedSearchCount, equals(2));
    });

    test('Filters events via queryEvents', () {
      final now = DateTime.now();
      recorder.recordInterception(
        SurgicalInterceptionEvent(
          eventId: 'e_ig',
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
      recorder.recordInterception(
        SurgicalInterceptionEvent(
          eventId: 'e_yt',
          timestamp: now,
          platformId: 'youtube',
          platformName: 'YouTube',
          subfeature: SurgicalSubfeature.explore,
          interceptedTarget: 'explore.youtube.com',
          actionApplied: ViewInterceptionAction.navigateBack,
          triggerSource: InterceptionTriggerSource.dnsQuery,
          packageName: 'com.google.android.youtube',
        ),
      );

      final igEvents = recorder.queryEvents(platformId: 'instagram');
      expect(igEvents.length, equals(1));
      expect(igEvents.first.platformId, equals('instagram'));

      final exploreEvents = recorder.queryEvents(subfeature: SurgicalSubfeature.explore);
      expect(exploreEvents.length, equals(1));
      expect(exploreEvents.first.platformId, equals('youtube'));
    });

    test('Persists and restores events via SharedPreferences', () async {
      recorder.recordInterception(
        SurgicalInterceptionEvent(
          eventId: 'persist_evt_1',
          timestamp: DateTime.now(),
          platformId: 'reddit',
          platformName: 'Reddit',
          subfeature: SurgicalSubfeature.feed,
          interceptedTarget: 'v.redd.it',
          actionApplied: ViewInterceptionAction.navigateBack,
          triggerSource: InterceptionTriggerSource.dnsQuery,
          packageName: 'com.reddit.frontpage',
        ),
      );
      recorder.recordAllowedCommunication(platformId: 'reddit', isChat: true, count: 8);

      await recorder.saveToPreferences();

      // Create new recorder and load
      final newRecorder = SurgicalTelemetryRecorder();
      await newRecorder.loadFromPreferences();

      expect(newRecorder.bufferedEventCount, equals(1));
      expect(newRecorder.recentEvents.first.eventId, equals('persist_evt_1'));
      expect(newRecorder.allowedChatCount, equals(8));

      newRecorder.dispose();
    });
  });
}
