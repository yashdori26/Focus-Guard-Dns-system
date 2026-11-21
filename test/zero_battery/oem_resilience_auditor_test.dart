import 'package:flutter_test/flutter_test.dart';
import 'package:focus_dns/engine/daemon/oem/oem_device_profiles.dart';
import 'package:focus_dns/engine/daemon/oem/oem_registry.dart';
import 'package:focus_dns/engine/daemon/telemetry/energy_anomaly_detector.dart';
import 'package:focus_dns/engine/daemon/telemetry/oem_resilience_auditor.dart';

void main() {
  group('1. OemResilienceAuditor Multi-Vector Scoring Tests', () {
    test('Unshielded Xiaomi device audits as vulnerable tier', () {
      final probe = DeviceHardwareProbe.mockXiaomi();
      final scorecard = OemResilienceAuditor.auditDevice(
        profile: OemDeviceProfiles.xiaomi,
        probe: probe,
      );

      // No autostart (0), no Doze (0), no recents (0), perms (15) -> 15 pts
      expect(scorecard.totalScore, equals(15));
      expect(scorecard.tier, equals(ResilienceTier.vulnerable));
      expect(scorecard.outstandingVulnerabilities.length, greaterThanOrEqualTo(3));
    });

    test('Partially shielded device audits as partiallyShielded or hardened tier', () {
      const probe = DeviceHardwareProbe(
        manufacturer: 'Xiaomi',
        brand: 'Redmi',
        model: 'Redmi Note 13',
        hardware: 'garnet',
        buildFingerprint: 'xiaomi/garnet',
        romVersion: 'HyperOS 1.0',
        sdkInt: 34,
        isDozeExempted: true, // +30
        isAutostartGranted: true, // +35
        isLockedInRecents: false, // 0
      );
      final scorecard = OemResilienceAuditor.auditDevice(
        profile: OemDeviceProfiles.xiaomi,
        probe: probe,
      );

      // 30 (Doze) + 35 (Autostart) + 0 + 15 (Perms) = 80 pts
      expect(scorecard.totalScore, equals(80));
      expect(scorecard.tier, equals(ResilienceTier.hardened));
      expect(scorecard.verifiedShields.length, greaterThanOrEqualTo(2));
    });

    test('Fully shielded device achieves unbreakable tier (100 pts)', () {
      const probe = DeviceHardwareProbe(
        manufacturer: 'Xiaomi',
        brand: 'POCO',
        model: 'F5',
        hardware: 'marble',
        buildFingerprint: 'poco/marble',
        romVersion: 'HyperOS 1.0',
        sdkInt: 34,
        isDozeExempted: true, // +30
        isAutostartGranted: true, // +35
        isLockedInRecents: true, // +20
      );
      final scorecard = OemResilienceAuditor.auditDevice(
        profile: OemDeviceProfiles.xiaomi,
        probe: probe,
      );

      // 30 + 35 + 20 + 15 = 100 pts
      expect(scorecard.totalScore, equals(100));
      expect(scorecard.tier, equals(ResilienceTier.unbreakable));
      expect(scorecard.outstandingVulnerabilities, isEmpty);
    });

    test('OemAuditScorecard JSON serialization round-trip', () {
      final probe = DeviceHardwareProbe.mockGeneric();
      final scorecard = OemResilienceAuditor.auditDevice(
        profile: OemDeviceProfiles.pixel,
        probe: probe,
      );

      final json = scorecard.toJson();
      expect(json['totalScore'], equals(100));
      expect(json['tier'], equals('unbreakable'));
    });
  });

  group('2. EnergyAnomalyDetector Statistical Outlier Tests', () {
    late EnergyAnomalyDetector detector;

    setUp(() {
      detector = EnergyAnomalyDetector(
        hourlyDrainThreshold: 0.08,
        queryBurstThresholdPerMinute: 300,
      );
    });

    test('Normal baseline metrics generate zero alerts', () {
      detector.inspectMetrics(
        currentHourlyDrainPct: 0.042,
        queriesInLastMinute: 45,
        activeWakeLocks: 0,
      );

      expect(detector.alerts, isEmpty);
    });

    test('Excessive drain rate spikes trigger critical anomaly alert', () {
      detector.inspectMetrics(
        currentHourlyDrainPct: 0.18, // More than double the threshold
        queriesInLastMinute: 80,
        activeWakeLocks: 0,
      );

      expect(detector.alerts.length, equals(1));
      expect(detector.alerts.first.severity, equals(AnomalySeverity.critical));
      expect(detector.alerts.first.title, contains('Elevated Energy Consumption'));
    });

    test('Rogue app infinite query loop triggers query burst alert', () {
      detector.inspectMetrics(
        currentHourlyDrainPct: 0.045,
        queriesInLastMinute: 650, // Massive loop
        activeWakeLocks: 0,
      );

      expect(detector.alerts.length, equals(1));
      expect(detector.alerts.first.title, contains('Query Loop'));
    });

    test('Wake lock violation generates critical policy breach alert', () {
      detector.inspectMetrics(
        currentHourlyDrainPct: 0.045,
        queriesInLastMinute: 50,
        activeWakeLocks: 2,
      );

      expect(detector.alerts.length, equals(1));
      expect(detector.alerts.first.severity, equals(AnomalySeverity.critical));
      expect(detector.alerts.first.title, contains('Wake-Lock Policy Breach'));
    });

    test('Clearing alerts empties alert collection', () {
      detector.inspectMetrics(currentHourlyDrainPct: 0.25, queriesInLastMinute: 500, activeWakeLocks: 1);
      expect(detector.alerts.length, greaterThan(0));

      detector.clearAlerts();
      expect(detector.alerts, isEmpty);
    });
  });
}
