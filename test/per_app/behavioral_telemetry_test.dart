import 'package:flutter_test/flutter_test.dart';
import 'package:focus_dns/engine/per_app/telemetry/per_app_behavioral_telemetry_engine.dart';

void main() {
  group('PerAppBehavioralTelemetryEngine Tests', () {
    test('1. Dopamine Addiction Velocity Index computes 0 for zero usage', () {
      final davi = PerAppBehavioralTelemetryEngine.computeDopamineVelocityIndex(
        totalLaunches: 0,
        totalForegroundSeconds: 0,
        totalBlockedAttempts: 0,
        hourlyUsageSeconds: List.filled(24, 0),
      );
      expect(davi, equals(0.0));
    });

    test('2. Compulsive launch patterns and night usage elevate DAVI score', () {
      final nightHeavy = List.filled(24, 0);
      nightHeavy[23] = 3600; // 1h at 11 PM
      nightHeavy[1] = 1800; // 30m at 1 AM

      final davi = PerAppBehavioralTelemetryEngine.computeDopamineVelocityIndex(
        totalLaunches: 35,
        totalForegroundSeconds: 5400,
        totalBlockedAttempts: 8,
        hourlyUsageSeconds: nightHeavy,
      );

      expect(davi, greaterThan(70.0));
      final diagnosis = PerAppBehavioralTelemetryEngine.generateBehavioralDiagnosis(davi);
      expect(diagnosis, contains('Critical Dopamine Trap'));
    });

    test('3. calculateReclaimedHours accurately measures reclaimed time', () {
      // Baseline 4 hours (14400s), actual 1 hour (3600s) -> 3 hours reclaimed
      final reclaimed = PerAppBehavioralTelemetryEngine.calculateReclaimedHours(
        baselineDailySeconds: 14400,
        actualForegroundSeconds: 3600,
      );
      expect(reclaimed, equals(3.0));

      // If actual exceeds baseline, reclaimed is 0
      final overspent = PerAppBehavioralTelemetryEngine.calculateReclaimedHours(
        baselineDailySeconds: 3600,
        actualForegroundSeconds: 7200,
      );
      expect(overspent, equals(0.0));
    });

    test('4. computeComplianceRate applies penalties for emergency unlocks', () {
      // 10 attempts, 10 successes, 0 unlocks -> 100%
      final perfect = PerAppBehavioralTelemetryEngine.computeComplianceRate(
        successfulFocusSessions: 10,
        totalSessionAttempts: 10,
        emergencyUnlocksUsed: 0,
      );
      expect(perfect, equals(100.0));

      // 10 attempts, 8 successes, 2 emergency unlocks -> (80% - 30%) = 50%
      final penalized = PerAppBehavioralTelemetryEngine.computeComplianceRate(
        successfulFocusSessions: 8,
        totalSessionAttempts: 10,
        emergencyUnlocksUsed: 2,
      );
      expect(penalized, equals(50.0));
    });

    test('5. generateBehavioralDiagnosis returns accurate advice across tiers', () {
      expect(PerAppBehavioralTelemetryEngine.generateBehavioralDiagnosis(15.0), contains('Optimal Cognitive Serenity'));
      expect(PerAppBehavioralTelemetryEngine.generateBehavioralDiagnosis(35.0), contains('Balanced Digital Hygiene'));
      expect(PerAppBehavioralTelemetryEngine.generateBehavioralDiagnosis(60.0), contains('Elevated Craving Index'));
      expect(PerAppBehavioralTelemetryEngine.generateBehavioralDiagnosis(90.0), contains('Critical Dopamine Trap'));
    });
  });
}
