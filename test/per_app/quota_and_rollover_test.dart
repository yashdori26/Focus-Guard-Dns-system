import 'package:flutter_test/flutter_test.dart';
import 'package:focus_dns/engine/per_app/core/per_app_quota_engine.dart';
import 'package:focus_dns/engine/per_app/models/app_lock_config.dart';

void main() {
  group('PerAppQuotaEngine & Midnight Rollover Tests', () {
    test('1. Foreground usage increments quota and fires depleted callback upon limit', () {
      String? depletedAppId;
      final engine = PerAppQuotaEngine(
        initialDate: DateTime(2026, 11, 7, 10, 0),
        onQuotaDepleted: (appId, pkg) {
          depletedAppId = appId;
        },
      );

      const config = AppLockConfig(
        appId: 'youtube',
        packageName: 'com.google.android.youtube',
        mode: AppLockMode.dailyQuota,
        dailyQuotaMinutes: 10, // 600 seconds
      );
      engine.registerConfig(config);

      // Add 300 seconds (5 mins) -> not depleted yet
      bool justDepleted = engine.recordForegroundUsage('youtube', 300, DateTime(2026, 11, 7, 10, 5));
      expect(justDepleted, isFalse);
      expect(depletedAppId, isNull);
      expect(engine.getRemainingSeconds('youtube'), equals(300));

      // Add another 350 seconds -> total 650 seconds >= 600 seconds -> depleted!
      justDepleted = engine.recordForegroundUsage('youtube', 350, DateTime(2026, 11, 7, 10, 11));
      expect(justDepleted, isTrue);
      expect(depletedAppId, equals('youtube'));
      expect(engine.getRemainingSeconds('youtube'), equals(0));
      expect(engine.configs['youtube']?.isCurrentlyLocked, isTrue);
    });

    test('2. Midnight rollover resets used quota and unlocks exhausted apps', () {
      String? oldDate;
      String? newDate;

      final engine = PerAppQuotaEngine(
        initialDate: DateTime(2026, 11, 7, 23, 50),
        onMidnightRollover: (oldK, newK) {
          oldDate = oldK;
          newDate = newK;
        },
      );

      const config = AppLockConfig(
        appId: 'instagram',
        packageName: 'com.instagram.android',
        mode: AppLockMode.dailyQuota,
        dailyQuotaMinutes: 20,
        usedQuotaSecondsToday: 1200, // already exhausted
        isCurrentlyLocked: true,
      );
      engine.registerConfig(config);

      expect(engine.configs['instagram']?.isCurrentlyLocked, isTrue);

      // Check with next day timestamp (00:05 AM)
      final nextDay = DateTime(2026, 11, 8, 0, 5);
      final rolledOver = engine.checkMidnightRollover(nextDay);

      expect(rolledOver, isTrue);
      expect(oldDate, equals('2026-11-07'));
      expect(newDate, equals('2026-11-08'));

      final refreshed = engine.configs['instagram']!;
      expect(refreshed.usedQuotaSecondsToday, equals(0));
      expect(refreshed.isCurrentlyLocked, isFalse);
      expect(refreshed.remainingQuotaSecondsToday, equals(20 * 60));
    });

    test('3. Non-quota mode apps ignore quota exhaustion checks', () {
      final engine = PerAppQuotaEngine(
        initialDate: DateTime(2026, 11, 7, 10, 0),
      );

      const config = AppLockConfig(
        appId: 'reddit',
        packageName: 'com.reddit.frontpage',
        mode: AppLockMode.independentTimer,
        dailyQuotaMinutes: 10,
      );
      engine.registerConfig(config);

      final depleted = engine.recordForegroundUsage('reddit', 700, DateTime(2026, 11, 7, 10, 15));
      expect(depleted, isFalse);
    });
  });
}
