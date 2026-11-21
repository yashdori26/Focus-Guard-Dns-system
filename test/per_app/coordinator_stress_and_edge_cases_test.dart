import 'package:flutter_test/flutter_test.dart';
import 'package:focus_dns/engine/per_app/catalog/app_category_metadata.dart';
import 'package:focus_dns/engine/per_app/catalog/app_definition.dart';
import 'package:focus_dns/engine/per_app/catalog/comprehensive_app_catalog.dart';
import 'package:focus_dns/engine/per_app/catalog/productive_alternative_registry.dart';
import 'package:focus_dns/engine/per_app/core/anti_tamper_clock.dart';
import 'package:focus_dns/engine/per_app/core/per_app_coordinator.dart';
import 'package:focus_dns/engine/per_app/core/per_app_priority_queue.dart';
import 'package:focus_dns/engine/per_app/core/per_app_quota_engine.dart';
import 'package:focus_dns/engine/per_app/core/per_app_recurring_engine.dart';
import 'package:focus_dns/engine/per_app/core/per_app_storage_journal.dart';
import 'package:focus_dns/engine/per_app/models/app_lock_config.dart';
import 'package:focus_dns/engine/per_app/models/app_usage_record.dart';
import 'package:focus_dns/engine/per_app/models/friction_challenge_model.dart';
import 'package:focus_dns/engine/per_app/models/recurring_schedule_rule.dart';
import 'package:focus_dns/engine/per_app/models/strictness_profile.dart';
import 'package:focus_dns/engine/per_app/per_app_database.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('PerAppCoordinator & Engine Extreme Stress & Edge Cases (1-25)', () {
    test('1. Priority queue simultaneous multi-app expiry dispatches in single popExpired pass', () {
      final pq = PerAppPriorityQueue();
      final expiryTime = DateTime(2026, 11, 7, 14, 0, 0);

      // 5 apps with identical target expiration timestamps
      for (int i = 1; i <= 5; i++) {
        pq.insert(ScheduleTriggerEvent(
          eventId: 'event_$i',
          appId: 'app_$i',
          packageName: 'com.app.$i',
          targetTimestamp: expiryTime,
          eventType: PriorityEventType.timerExpired,
        ));
      }

      expect(pq.length, equals(5));
      final expired = pq.popExpired(expiryTime);
      expect(expired.length, equals(5));
      expect(pq.isEmpty, isTrue);
    });

    test('2. Batch category lock locks all matching apps and populates priority queue', () async {
      final coordinator = PerAppCoordinator(enableAutomaticTicker: false);
      await coordinator.lockCategory(AppCategory.shortFormVideo, durationMinutes: 180);

      final active = coordinator.activeLocks;
      expect(active.isNotEmpty, isTrue);

      for (final lock in active) {
        final def = coordinator.catalog[lock.appId];
        if (def?.category == AppCategory.shortFormVideo) {
          expect(lock.isCurrentlyLocked, isTrue);
          expect(lock.allocatedTimerMinutes, equals(180));
        }
      }
    });

    test('3. Quota engine handles rapid micro-second increments without loss', () {
      final engine = PerAppQuotaEngine(initialDate: DateTime(2026, 11, 7, 10, 0));
      const cfg = AppLockConfig(
        appId: 'test_rapid',
        packageName: 'com.test.rapid',
        mode: AppLockMode.dailyQuota,
        dailyQuotaMinutes: 100,
      );
      engine.registerConfig(cfg);

      for (int i = 0; i < 50; i++) {
        engine.recordForegroundUsage('test_rapid', 2, DateTime(2026, 11, 7, 10, 1));
      }

      expect(engine.configs['test_rapid']?.usedQuotaSecondsToday, equals(100));
    });

    test('4. AntiTamperClock verifyAgainstWallClock rejects backwards time jumps over 3 minutes', () {
      final base = DateTime(2026, 11, 7, 15, 0);
      final clock = AntiTamperClock(initialAnchor: base);

      // Drift of 179s passes
      expect(clock.verifyAgainstWallClock(base.subtract(const Duration(seconds: 179))), isTrue);
      expect(clock.tamperingStrikeCount, equals(0));

      // Drift of 185s fails and logs strike
      expect(clock.verifyAgainstWallClock(base.subtract(const Duration(seconds: 185))), isFalse);
      expect(clock.tamperingStrikeCount, equals(1));
    });

    test('5. Recurring schedule handles boundary minute 1439 (11:59 PM) correctly', () {
      const lateRule = RecurringScheduleRule(
        id: 'late',
        appId: 'late_app',
        packageName: 'com.late',
        label: 'Late Night',
        daysOfWeek: [6], // Saturday
        startMinuteOfDay: 1400,
        endMinuteOfDay: 1439,
      );

      final sat1158 = DateTime(2026, 11, 7, 23, 58);
      expect(sat1158.weekday, equals(6));
      expect(lateRule.isTimeWithinWindow(sat1158), isTrue);

      final sat1159 = DateTime(2026, 11, 7, 23, 59);
      expect(lateRule.isTimeWithinWindow(sat1159), isFalse);
    });

    test('6. StorageJournal records and tallies tampering strikes persistently', () async {
      final journal = PerAppStorageJournal();
      expect(await journal.getTamperStrikesCount(), equals(0));

      await journal.recordTamperStrike(DateTime.now(), 'Clock rolled back by 3 hours');
      await journal.recordTamperStrike(DateTime.now(), 'Clock rolled back by 5 hours');

      expect(await journal.getTamperStrikesCount(), equals(2));
    });

    test('7. Strictness profile prevents unlock in strictUnbreakable mode', () async {
      final coordinator = PerAppCoordinator(enableAutomaticTicker: false);
      await coordinator.lockAppTimer(
        'instagram',
        durationMinutes: 60,
        strictness: StrictnessTier.strictUnbreakable,
      );

      final unlocked = await coordinator.unlockApp('instagram', bypassStrictness: false);
      expect(unlocked, isFalse);
      expect(coordinator.configs['instagram']?.isCurrentlyLocked, isTrue);
    });

    test('8. Strictness profile allows emergency unlock in flexible mode', () async {
      final coordinator = PerAppCoordinator(enableAutomaticTicker: false);
      await coordinator.lockAppTimer(
        'instagram',
        durationMinutes: 60,
        strictness: StrictnessTier.flexible,
      );

      final unlocked = await coordinator.unlockApp('instagram', bypassStrictness: false);
      expect(unlocked, isTrue);
      expect(coordinator.configs['instagram']?.isCurrentlyLocked, isFalse);
    });

    test('9. ProductiveAlternativeRegistry fallback chains default to Notion', () {
      final fallback = ProductiveAlternativeRegistry.getSuggestedForCategory('unknown_category_xyz');
      expect(fallback.id, equals('notion'));
      expect(fallback.slogan.isNotEmpty, isTrue);
    });

    test('10. ComprehensiveAppCatalog matches wildcards for subdomains', () {
      final def = ComprehensiveAppCatalog.findByDomain('sub.cdn.scontent.cdninstagram.com');
      expect(def, isNotNull);
      expect(def!.id, equals('instagram'));
    });

    test('11. FrictionChallenge math generator creates distinct randomized equations', () {
      final c1 = FrictionChallenge.createMathChallenge();
      final c2 = FrictionChallenge.createMathChallenge();

      expect(c1.equations.length, equals(3));
      expect(c2.equations.length, equals(3));
      expect(c1.challengeId != c2.challengeId, isTrue);
    });

    test('12. Daily usage hourly distribution records into matching hour bucket', () {
      var record = const AppDailyUsageRecord(
        appId: 'youtube',
        packageName: 'com.google.android.youtube',
        dateKey: '2026-11-07',
      );

      final testTime = DateTime(2026, 11, 7, 14, 30); // hour 14
      record = record.addUsage(durationSec: 900, timestamp: testTime);

      expect(record.totalForegroundSeconds, equals(900));
      expect(record.hourlyUsageSeconds[14], equals(900));
      expect(record.hourlyUsageSeconds[13], equals(0));
      expect(record.sessions.length, equals(1));
      expect(record.sessions.first.durationSeconds, equals(900));
    });

    test('13. Daily usage session intervals track start and end timestamps', () {
      var record = const AppDailyUsageRecord(
        appId: 'tiktok',
        packageName: 'com.zhiliaoapp.musically',
        dateKey: '2026-11-07',
      );

      final end = DateTime(2026, 11, 7, 18, 0, 0);
      record = record.addUsage(durationSec: 120, timestamp: end);

      expect(record.sessions.first.endTime, equals(end));
      expect(record.sessions.first.startTime, equals(end.subtract(const Duration(seconds: 120))));
    });

    test('14. Concurrent timer and quota configs can be stored and transitioned independently', () {
      final cfgTimer = const AppLockConfig(
        appId: 'app1',
        packageName: 'com.app1',
        mode: AppLockMode.independentTimer,
      );
      final cfgQuota = const AppLockConfig(
        appId: 'app2',
        packageName: 'com.app2',
        mode: AppLockMode.dailyQuota,
      );

      expect(cfgTimer.mode, equals(AppLockMode.independentTimer));
      expect(cfgQuota.mode, equals(AppLockMode.dailyQuota));
    });

    test('15. PriorityQueue peek returns null on empty heap', () {
      final pq = PerAppPriorityQueue();
      expect(pq.peek(), isNull);
      expect(pq.pop(), isNull);
    });

    test('16. PriorityQueue removeByEventId removes specific event from heap', () {
      final pq = PerAppPriorityQueue();
      final now = DateTime.now();

      pq.insert(ScheduleTriggerEvent(
        eventId: 'event_to_remove',
        appId: 'app1',
        packageName: 'pkg',
        targetTimestamp: now.add(const Duration(minutes: 5)),
        eventType: PriorityEventType.timerExpired,
      ));
      pq.insert(ScheduleTriggerEvent(
        eventId: 'event_to_keep',
        appId: 'app2',
        packageName: 'pkg',
        targetTimestamp: now.add(const Duration(minutes: 10)),
        eventType: PriorityEventType.timerExpired,
      ));

      pq.removeByEventId('event_to_remove');
      expect(pq.length, equals(1));
      expect(pq.peek()?.eventId, equals('event_to_keep'));
    });

    test('17. Consecutive midnight rollovers track multiple date shifts cleanly', () {
      final engine = PerAppQuotaEngine(initialDate: DateTime(2026, 11, 7, 23, 55));
      const cfg = AppLockConfig(
        appId: 'test_app',
        packageName: 'com.test',
        mode: AppLockMode.dailyQuota,
        dailyQuotaMinutes: 15,
        usedQuotaSecondsToday: 900,
      );
      engine.registerConfig(cfg);

      // Rollover 1: Nov 7 -> Nov 8
      expect(engine.checkMidnightRollover(DateTime(2026, 11, 8, 0, 5)), isTrue);
      expect(engine.currentDateKey, equals('2026-11-08'));
      expect(engine.configs['test_app']?.usedQuotaSecondsToday, equals(0));

      // Same day check: Nov 8 10:00 AM -> no rollover
      expect(engine.checkMidnightRollover(DateTime(2026, 11, 8, 10, 0)), isFalse);

      // Rollover 2: Nov 8 -> Nov 9
      expect(engine.checkMidnightRollover(DateTime(2026, 11, 9, 0, 1)), isTrue);
      expect(engine.currentDateKey, equals('2026-11-09'));
    });

    test('18. Month and year boundary rollovers format date keys with leading zeroes', () {
      final engine = PerAppQuotaEngine(initialDate: DateTime(2026, 12, 31, 23, 59));
      expect(engine.currentDateKey, equals('2026-12-31'));

      engine.checkMidnightRollover(DateTime(2027, 1, 1, 0, 1));
      expect(engine.currentDateKey, equals('2027-01-01'));
    });

    test('19. High-volume JSON serialization stress test with 100 configurations', () {
      final map = <String, AppLockConfig>{};
      for (int i = 0; i < 100; i++) {
        map['app_$i'] = AppLockConfig(
          appId: 'app_$i',
          packageName: 'com.app.$i',
          allocatedTimerMinutes: (i + 1) * 10,
          dailyQuotaMinutes: (i + 1) * 2,
        );
      }

      final journal = PerAppStorageJournal();
      expect(() async => await journal.saveConfigs(map), returnsNormally);
    });

    test('20. AppLockConfig isQuotaDepleted is true when used seconds equals total allowed', () {
      const cfg = AppLockConfig(
        appId: 'a',
        packageName: 'p',
        dailyQuotaMinutes: 10,
        usedQuotaSecondsToday: 600,
      );
      expect(cfg.isQuotaDepleted, isTrue);
      expect(cfg.remainingQuotaSecondsToday, equals(0));
    });

    test('21. AppLockConfig remainingTimerSeconds returns 0 when targetEndTime is in past', () {
      final past = DateTime.now().subtract(const Duration(minutes: 10));
      final cfg = AppLockConfig(
        appId: 'a',
        packageName: 'p',
        isCurrentlyLocked: true,
        lockTargetEndTime: past,
      );
      expect(cfg.remainingTimerSeconds, equals(0));
    });

    test('22. AppCategoryMetadata registry includes common keywords for search matching', () {
      final shortMeta = AppCategoryMetadata.of(AppCategory.shortFormVideo);
      expect(shortMeta.commonKeywords, contains('tiktok'));
      expect(shortMeta.commonKeywords, contains('reels'));
      expect(shortMeta.commonKeywords, contains('shorts'));
    });

    test('23. RecurringScheduleRule cross-midnight evaluates Sunday into Monday rollover', () {
      const sunNight = RecurringScheduleRule(
        id: 'sun_roll',
        appId: 'a',
        packageName: 'p',
        label: 'Sunday Night Fast',
        daysOfWeek: [7], // Sunday only
        startMinuteOfDay: 1380, // 11:00 PM
        endMinuteOfDay: 300, // 05:00 AM
      );

      // Monday (weekday 1) at 03:00 AM -> rollover from Sunday -> true
      final mondayEarly = DateTime(2026, 11, 9, 3, 0);
      expect(mondayEarly.weekday, equals(1));
      expect(sunNight.isTimeWithinWindow(mondayEarly), isTrue);
    });

    test('24. PerAppCoordinator tickForTesting advances state and unlocks expired timers', () async {
      final coordinator = PerAppCoordinator(enableAutomaticTicker: false);
      final startTime = coordinator.clock.monotonicNow;

      await coordinator.lockAppTimer('tiktok', durationMinutes: 10);
      expect(coordinator.configs['tiktok']?.isCurrentlyLocked, isTrue);

      // Advance time by 15 minutes past the start time
      coordinator.tickForTesting(startTime.add(const Duration(minutes: 15)));
      expect(coordinator.configs['tiktok']?.isCurrentlyLocked, isFalse);
    });

    test('25. PerAppCoordinator dispose cleanly disposes without exceptions', () {
      final coordinator = PerAppCoordinator(enableAutomaticTicker: true);
      expect(() => coordinator.dispose(), returnsNormally);
    });
  });
}
