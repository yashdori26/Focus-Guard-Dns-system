import 'package:flutter_test/flutter_test.dart';
import 'package:focus_dns/engine/per_app/core/per_app_priority_queue.dart';
import 'package:focus_dns/engine/per_app/models/app_lock_config.dart';
import 'package:focus_dns/engine/per_app/models/strictness_profile.dart';

void main() {
  group('Models & PerAppPriorityQueue Tests', () {
    test('1. AppLockConfig default initialization and copyWith clamping', () {
      const config = AppLockConfig(
        appId: 'test_app',
        packageName: 'com.test.app',
      );

      expect(config.mode, equals(AppLockMode.unlocked));
      expect(config.strictness, equals(StrictnessTier.strictUnbreakable));
      expect(config.allocatedTimerMinutes, equals(120));

      final updated = config.copyWith(
        allocatedTimerMinutes: 3000, // should clamp to 1440
        dailyQuotaMinutes: -10, // should clamp to 1
      );
      expect(updated.allocatedTimerMinutes, equals(1440));
      expect(updated.dailyQuotaMinutes, equals(1));
    });

    test('2. AppLockConfig JSON serialization round-trip preserves state', () {
      final now = DateTime.now();
      final config = AppLockConfig(
        appId: 'insta',
        packageName: 'com.instagram.android',
        mode: AppLockMode.independentTimer,
        strictness: StrictnessTier.strictUnbreakable,
        allocatedTimerMinutes: 480,
        dailyQuotaMinutes: 30,
        lockStartTime: now,
        lockTargetEndTime: now.add(const Duration(hours: 8)),
        isCurrentlyLocked: true,
      );

      final json = config.toJson();
      final restored = AppLockConfig.fromJson(json);

      expect(restored.appId, equals(config.appId));
      expect(restored.mode, equals(config.mode));
      expect(restored.strictness, equals(config.strictness));
      expect(restored.isCurrentlyLocked, isTrue);
      expect(restored.allocatedTimerMinutes, equals(480));
    });

    test('3. StrictnessProfile policies correctly disable emergency unlock in strict mode', () {
      final strict = StrictnessProfile.of(StrictnessTier.strictUnbreakable);
      final flex = StrictnessProfile.of(StrictnessTier.flexible);
      final friction = StrictnessProfile.of(StrictnessTier.frictionProtected);

      expect(strict.allowsEmergencyUnlock, isFalse);
      expect(strict.preventsAppUninstall, isTrue);
      expect(strict.rebootResistant, isTrue);

      expect(flex.allowsEmergencyUnlock, isTrue);
      expect(flex.requiresFrictionChallenge, isFalse);

      expect(friction.allowsEmergencyUnlock, isTrue);
      expect(friction.requiresFrictionChallenge, isTrue);
    });

    test('4. PerAppPriorityQueue maintains min-heap order upon insertions', () {
      final pq = PerAppPriorityQueue();
      final now = DateTime.now();

      final t1 = now.add(const Duration(minutes: 60));
      final t2 = now.add(const Duration(minutes: 10));
      final t3 = now.add(const Duration(minutes: 120));
      final t4 = now.add(const Duration(minutes: 5));

      pq.insert(ScheduleTriggerEvent(
        eventId: 'e1',
        appId: 'app1',
        packageName: 'pkg1',
        targetTimestamp: t1,
        eventType: PriorityEventType.timerExpired,
      ));
      pq.insert(ScheduleTriggerEvent(
        eventId: 'e2',
        appId: 'app2',
        packageName: 'pkg2',
        targetTimestamp: t2,
        eventType: PriorityEventType.timerExpired,
      ));
      pq.insert(ScheduleTriggerEvent(
        eventId: 'e3',
        appId: 'app3',
        packageName: 'pkg3',
        targetTimestamp: t3,
        eventType: PriorityEventType.timerExpired,
      ));
      pq.insert(ScheduleTriggerEvent(
        eventId: 'e4',
        appId: 'app4',
        packageName: 'pkg4',
        targetTimestamp: t4,
        eventType: PriorityEventType.timerExpired,
      ));

      expect(pq.length, equals(4));
      // Nearest upcoming should be t4 (5 minutes)
      expect(pq.peek()?.appId, equals('app4'));

      // Pop in chronological order
      expect(pq.pop()?.appId, equals('app4'));
      expect(pq.pop()?.appId, equals('app2'));
      expect(pq.pop()?.appId, equals('app1'));
      expect(pq.pop()?.appId, equals('app3'));
      expect(pq.isEmpty, isTrue);
    });

    test('5. PerAppPriorityQueue popExpired returns only events on or before cutoff', () {
      final pq = PerAppPriorityQueue();
      final base = DateTime(2026, 11, 7, 10, 0, 0);

      pq.insert(ScheduleTriggerEvent(
        eventId: 'e1',
        appId: 'app1',
        packageName: 'pkg1',
        targetTimestamp: base.add(const Duration(minutes: 10)),
        eventType: PriorityEventType.timerExpired,
      ));
      pq.insert(ScheduleTriggerEvent(
        eventId: 'e2',
        appId: 'app2',
        packageName: 'pkg2',
        targetTimestamp: base.add(const Duration(minutes: 20)),
        eventType: PriorityEventType.timerExpired,
      ));
      pq.insert(ScheduleTriggerEvent(
        eventId: 'e3',
        appId: 'app3',
        packageName: 'pkg3',
        targetTimestamp: base.add(const Duration(minutes: 30)),
        eventType: PriorityEventType.timerExpired,
      ));

      // Cutoff at minute 25 -> should pop e1 and e2, keeping e3
      final expired = pq.popExpired(base.add(const Duration(minutes: 25)));
      expect(expired.length, equals(2));
      expect(expired.map((e) => e.appId).toList(), equals(['app1', 'app2']));
      expect(pq.length, equals(1));
      expect(pq.peek()?.appId, equals('app3'));
    });

    test('6. PerAppPriorityQueue removeByAppId cleans all matching triggers', () {
      final pq = PerAppPriorityQueue();
      final now = DateTime.now();

      pq.insert(ScheduleTriggerEvent(
        eventId: 'e1',
        appId: 'target_app',
        packageName: 'pkg',
        targetTimestamp: now.add(const Duration(minutes: 10)),
        eventType: PriorityEventType.timerExpired,
      ));
      pq.insert(ScheduleTriggerEvent(
        eventId: 'e2',
        appId: 'other_app',
        packageName: 'pkg',
        targetTimestamp: now.add(const Duration(minutes: 15)),
        eventType: PriorityEventType.timerExpired,
      ));

      pq.removeByAppId('target_app');
      expect(pq.length, equals(1));
      expect(pq.peek()?.appId, equals('other_app'));
    });
  });
}
