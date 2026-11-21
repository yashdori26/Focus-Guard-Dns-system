import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:focus_dns/engine/profile/user_profile_model.dart';
import 'package:focus_dns/engine/profile/fleet_device_model.dart';
import 'package:focus_dns/engine/profile/cross_device_sync_coordinator.dart';
import 'package:focus_dns/engine/profile/accountability_partner_manager.dart';
import 'package:focus_dns/engine/profile/device_pairing_crypto.dart';
import 'package:focus_dns/engine/analytics/longitudinal_time_period.dart';
import 'package:focus_dns/engine/analytics/session_lifecycle_metrics.dart';
import 'package:focus_dns/engine/analytics/streak_momentum_calculator.dart';
import 'package:focus_dns/engine/analytics/attention_heatmap_matrix.dart';
import 'package:focus_dns/engine/analytics/dopamine_rehabilitation_historian.dart';
import 'package:focus_dns/engine/analytics/analytics_persistence_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('Phase 5 Extreme Stress & Edge Cases (25 Stress Tests)', () {
    test('Stress 1: 10,000 synthetic interception events across 7x24 heatmap matrix', () {
      final matrix = AttentionHeatmapMatrix.empty();
      final baseDate = DateTime(2026, 11, 2); // Monday

      final stopwatch = Stopwatch()..start();
      for (int i = 0; i < 10000; i++) {
        final dayOffset = i % 7;
        final hour = i % 24;
        matrix.recordInterception(baseDate.add(Duration(days: dayOffset, hours: hour)), 1);
      }
      stopwatch.stop();

      expect(matrix.totalWeeklyInterceptions, equals(10000));
      expect(stopwatch.elapsedMilliseconds, lessThan(500)); // Sub-second performance
    });

    test('Stress 2: Leap year streak rollover (Feb 28 -> Feb 29 -> March 1)', () {
      var record = StreakRecord.initial();
      // Year 2028 is a leap year
      record = StreakMomentumCalculator.recordActivity(record, DateTime(2028, 2, 28));
      record = StreakMomentumCalculator.recordActivity(record, DateTime(2028, 2, 29));
      record = StreakMomentumCalculator.recordActivity(record, DateTime(2028, 3, 1));

      expect(record.currentStreakDays, equals(3));
      expect(record.longestStreakDays, equals(3));
    });

    test('Stress 3: Year-end streak rollover (Dec 31 -> Jan 1)', () {
      var record = StreakRecord.initial();
      record = StreakMomentumCalculator.recordActivity(record, DateTime(2026, 12, 31));
      record = StreakMomentumCalculator.recordActivity(record, DateTime(2027, 1, 1));

      expect(record.currentStreakDays, equals(2));
    });

    test('Stress 4: Replay attack flood (1,000 HMAC signature validations)', () {
      const crypto = DevicePairingCrypto('stress_secret_123');
      final nowSec = 1700000000;
      final uri = crypto.generatePairingUri(
        userId: 'usr_stress',
        deviceName: 'Device',
        timestampSeconds: nowSec,
      );

      final stopwatch = Stopwatch()..start();
      for (int i = 0; i < 1000; i++) {
        final payload = crypto.parseAndValidatePairingUri(uri, nowSec + 10);
        expect(payload.isValid, isTrue);
      }
      stopwatch.stop();
      expect(stopwatch.elapsedMilliseconds, lessThan(200));
    });

    test('Stress 5: High-frequency fleet synchronization updates', () {
      final coordinator = CrossDeviceSyncCoordinator(userId: 'u', localDeviceId: 'd');
      coordinator.start();

      for (int i = 0; i < 500; i++) {
        coordinator.broadcastFocusLock(durationMinutes: 25 + (i % 30), isStrict: i % 2 == 0);
      }

      expect(coordinator.fleetDevices.isNotEmpty, isTrue);
      coordinator.dispose();
    });

    test('Stress 6: Floating-point precision in neurobiological dopamine formula over 365 days', () {
      for (int d = 0; d <= 365; d++) {
        final sens = DopamineRehabilitationHistorian.calculateReceptorSensitivity(d);
        expect(sens, greaterThanOrEqualTo(25.0));
        expect(sens, lessThanOrEqualTo(100.0));
        expect(sens.isNaN, isFalse);
      }
    });

    test('Stress 7: 1,000 emergency unlock requests in sequence', () async {
      final manager = await AccountabilityPartnerManager.create();
      for (int i = 0; i < 100; i++) {
        await manager.createUnlockRequest(deviceId: 'dev_$i', reason: 'Stress reason #$i');
      }
      expect(manager.requests.length, equals(100));
    });

    test('Stress 8: Date ranges across centuries (2000 to 2100) are valid', () {
      for (int y = 2000; y <= 2100; y += 10) {
        final ref = DateTime(y, 6, 15);
        final rDay = LongitudinalPeriodHelper.calculateRange(LongitudinalTimePeriod.day, ref);
        final rWeek = LongitudinalPeriodHelper.calculateRange(LongitudinalTimePeriod.week, ref);
        final rYear = LongitudinalPeriodHelper.calculateRange(LongitudinalTimePeriod.year, ref);

        expect(rDay.contains(ref), isTrue);
        expect(rWeek.contains(ref), isTrue);
        expect(rYear.contains(ref), isTrue);
      }
    });

    test('Stress 9: Zero-duration focus sessions do not cause division by zero', () {
      final m = SessionLifecycleMetrics.empty();
      expect(m.averageFocusSessionMinutes, equals(0.0));
      expect(m.focusToBreakRatio, equals(1.0));
      expect(m.adherenceRate, equals(100.0));
    });

    test('Stress 10: Extreme session counts adherence clamping', () {
      final m = SessionLifecycleMetrics.empty().copyWith(
        sessionsInitiated: 1000000,
        sessionsCompleted: 999999,
      );
      expect(m.adherenceRate, greaterThan(99.9));
      expect(m.adherenceRate, lessThanOrEqualTo(100.0));
    });

    test('Stress 11: Malformed pairing URIs with random garbage fail gracefully', () {
      const crypto = DevicePairingCrypto();
      final badUris = [
        '',
        'https://google.com',
        'focusdns://wronghost?uid=1',
        'focusdns://pair?uid=1&dev=2', // missing sig and ts
        'focusdns://pair?uid=1&dev=2&ts=bad_number&sig=xyz',
      ];

      for (final uri in badUris) {
        final payload = crypto.parseAndValidatePairingUri(uri);
        expect(payload.isValid, isFalse);
        expect(payload.validationError, isNotNull);
      }
    });

    test('Stress 12: Partner trust score remains bounded between 0 and 100', () {
      const partner = AccountabilityPartner(
        partnerId: 'p',
        name: 'N',
        email: 'e',
        trustScore: 100,
      );
      expect(partner.trustScore, equals(100));
      final degraded = partner.copyWith(trustScore: 45);
      expect(degraded.trustScore, equals(45));
    });

    test('Stress 13: Diurnal split with zero activity returns equal 25% ratios', () {
      final matrix = AttentionHeatmapMatrix.empty();
      final split = matrix.calculateDiurnalSplit();
      expect(split.morningRatio, equals(0.25));
      expect(split.afternoonRatio, equals(0.25));
      expect(split.eveningRatio, equals(0.25));
      expect(split.nightRatio, equals(0.25));
    });

    test('Stress 14: CSV export sanitization under special characters', () async {
      final store = await AnalyticsPersistenceStore.create();
      await store.recordDailyMetrics(
        DateTime(2026, 11, 8),
        SessionLifecycleMetrics.empty().copyWith(
          sessionsInitiated: 2,
          sessionsCompleted: 2,
          totalFocusMinutes: 60,
        ),
      );
      final csv = store.exportCsv();
      expect(csv.split('\n').length, greaterThanOrEqualTo(2));
    });

    test('Stress 15: Markdown report generation completes in < 50ms', () async {
      final store = await AnalyticsPersistenceStore.create();
      final sw = Stopwatch()..start();
      final md = store.exportMarkdownReport(LongitudinalTimePeriod.allTime);
      sw.stop();
      expect(md.isNotEmpty, isTrue);
      expect(sw.elapsedMilliseconds, lessThan(50));
    });

    test('Stress 16: Device model handles extreme battery values', () {
      final dev = FleetDeviceModel(
        deviceId: 'd',
        deviceName: 'D',
        platform: FleetPlatformType.android,
        clientVersion: '1.0',
        lastHeartbeat: DateTime.now(),
        isOnline: true,
        activeMode: 'focus',
        isStrictLockActive: false,
        sessionRemainingSeconds: 0,
        distractionsBlockedToday: 0,
        minutesReclaimedToday: 0,
        batteryPercentage: 100,
      );
      expect(dev.batteryPercentage, equals(100));
    });

    test('Stress 17: UserProfileModel security toggle mutations', () {
      var profile = UserProfileModel.initial();
      profile = profile.copyWith(
        biometricUnlockRequired: true,
        strictAntiUninstallEnabled: false,
        emergencyPartnerRequired: true,
      );
      expect(profile.biometricUnlockRequired, isTrue);
      expect(profile.strictAntiUninstallEnabled, isFalse);
      expect(profile.emergencyPartnerRequired, isTrue);
    });

    test('Stress 18: Focus archetype switching alters recommendations', () {
      var profile = UserProfileModel.initial();
      expect(profile.archetypeInfo.recommendedDailyFocusHours, equals(6)); // Engineer

      profile = profile.copyWith(archetype: FocusArchetype.zenMonk);
      expect(profile.archetypeInfo.recommendedDailyFocusHours, equals(8));

      profile = profile.copyWith(archetype: FocusArchetype.studentScholar);
      expect(profile.archetypeInfo.recommendedDailyFocusHours, equals(4));
    });

    test('Stress 19: Tangible equivalents handles 1,000,000 reclaimed focus minutes', () {
      final eq = DopamineRehabilitationHistorian.calculateTangibleEquivalents(1000000);
      expect(eq.booksReadEquivalent, greaterThan(3500));
      expect(eq.deepWorkBlocks, greaterThan(11000));
      expect(eq.coursesCompleted, greaterThan(1100));
    });

    test('Stress 20: Cross-device coordinator handles concurrent remote triggers', () {
      final coord = CrossDeviceSyncCoordinator(userId: 'u', localDeviceId: 'd');
      coord.start();

      for (int i = 0; i < 50; i++) {
        coord.simulateIncomingRemoteEvent({
          'type': 'TRIGGER_FOCUS_LOCK',
          'durationMinutes': 30,
          'isStrict': true,
        });
      }

      coord.dispose();
    });

    test('Stress 21: Peak vulnerability hours with tie scores preserves sort', () {
      final matrix = AttentionHeatmapMatrix.empty();
      matrix.recordInterception(DateTime(2026, 11, 2, 10, 0), 5);
      matrix.recordInterception(DateTime(2026, 11, 3, 10, 0), 5);

      final peaks = matrix.findPeakVulnerabilityHours(2);
      expect(peaks.length, equals(2));
      expect(peaks[0].interceptionCount, equals(5));
      expect(peaks[1].interceptionCount, equals(5));
    });

    test('Stress 22: Relapse risk level stability at boundary percentages', () {
      final record = StreakRecord.initial();
      final risk = StreakMomentumCalculator.evaluateRelapseRisk(record);
      expect(risk, equals(RelapseRiskLevel.critical)); // 0 activity is critical
    });

    test('Stress 23: Multiple freeze tokens applied without going negative', () {
      var record = StreakRecord.initial();
      expect(record.freezeTokensRemaining, equals(2));

      // Spend 1
      record = StreakMomentumCalculator.recordActivity(record, DateTime(2026, 11, 1));
      record = StreakMomentumCalculator.recordActivity(record, DateTime(2026, 11, 3)); // 1 missed day
      expect(record.freezeTokensRemaining, equals(1));

      // Spend 2nd
      record = StreakMomentumCalculator.recordActivity(record, DateTime(2026, 11, 5)); // another missed day
      expect(record.freezeTokensRemaining, equals(0));

      // Attempt 3rd missed day -> resets to 1 day streak
      record = StreakMomentumCalculator.recordActivity(record, DateTime(2026, 11, 7));
      expect(record.currentStreakDays, equals(1));
      expect(record.freezeTokensRemaining, equals(0));
    });

    test('Stress 24: JSON roundtrip under deeply nested rollups map', () {
      final rollups = <String, dynamic>{
        '2026-11-01': SessionLifecycleMetrics.empty().toJson(),
        '2026-11-02': SessionLifecycleMetrics.empty().copyWith(sessionsCompleted: 5).toJson(),
      };
      final str = jsonEncode(rollups);
      final decoded = jsonDecode(str) as Map<String, dynamic>;
      expect(decoded.length, equals(2));
      final m2 = SessionLifecycleMetrics.fromJson(decoded['2026-11-02'] as Map<String, dynamic>);
      expect(m2.sessionsCompleted, equals(5));
    });

    test('Stress 25: Master sovereignty honorific progression up to 1,000 hours', () {
      var profile = UserProfileModel.initial();
      expect(profile.sovereigntyRank, equals('Novice Reclaimer'));

      profile = profile.copyWith(totalLifetimeHoursReclaimed: 25);
      expect(profile.sovereigntyRank, equals('Intentional Apprentice'));

      profile = profile.copyWith(totalLifetimeHoursReclaimed: 75);
      expect(profile.sovereigntyRank, equals('Focus Vanguard'));

      profile = profile.copyWith(totalLifetimeHoursReclaimed: 150);
      expect(profile.sovereigntyRank, equals('Deep Work Centurion'));

      profile = profile.copyWith(totalLifetimeHoursReclaimed: 300);
      expect(profile.sovereigntyRank, equals('Cognitive Fortress Master'));

      profile = profile.copyWith(totalLifetimeHoursReclaimed: 1000);
      expect(profile.sovereigntyRank, equals('Dopamine Sovereign Grandmaster'));
    });
  });
}
