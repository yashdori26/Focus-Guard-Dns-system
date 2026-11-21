import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:focus_dns/engine/daemon/core/doze_sentinel_coordinator.dart';
import 'package:focus_dns/engine/daemon/core/power_budget_manager.dart';
import 'package:focus_dns/engine/daemon/core/resilient_watchdog_controller.dart';
import 'package:focus_dns/engine/daemon/core/ring_buffer_pool.dart';
import 'package:focus_dns/engine/daemon/core/zero_battery_dns_processor.dart';
import 'package:focus_dns/engine/daemon/models/battery_profile_config.dart';
import 'package:focus_dns/engine/daemon/oem/oem_device_profiles.dart';
import 'package:focus_dns/engine/daemon/oem/oem_registry.dart';
import 'package:focus_dns/engine/daemon/telemetry/battery_drain_profiler.dart';
import 'package:focus_dns/engine/daemon/telemetry/energy_anomaly_detector.dart';
import 'package:focus_dns/engine/daemon/telemetry/oem_resilience_auditor.dart';
import 'package:focus_dns/engine/daemon/telemetry/power_historian_recorder.dart';
import 'package:focus_dns/engine/per_app/core/anti_tamper_clock.dart';

void main() {
  group('Zero-Battery Daemon Extreme Stress & Edge Cases (1-25)', () {
    // 1. Rapid consecutive process kill simulation
    test('1. Rapid consecutive process kill triggers exponential backoff up to 30s', () {
      final watchdog = ResilientWatchdogController();
      for (int i = 0; i < 20; i++) {
        watchdog.recordResurrection(reason: 'Process killed');
      }
      expect(watchdog.consecutiveFailures, equals(20));
      expect(watchdog.calculateBackoff(), equals(const Duration(seconds: 30)));
    });

    // 2. Sudden thermal throttle state change
    test('2. High battery temperature (> 42°C) automatically forces critical saver tier', () {
      final manager = PowerBudgetManager(initialBattery: 90.0, initialTemp: 28.0);
      expect(manager.state.activeTier, equals(PowerBudgetTier.balanced));

      // Overheat!
      manager.updateBatteryStatus(
        batteryLevel: 90.0,
        chargingState: BatteryChargingState.unplugged,
        temperature: 45.0,
      );

      expect(manager.state.isThermalThrottled, isTrue);
      expect(manager.state.activeTier, equals(PowerBudgetTier.criticalSaver));
      expect(manager.state.telemetrySampleInterval.inSeconds, equals(120));
    });

    // 3. Zero-battery power tier drop (< 15%)
    test('3. Battery level dropping below 15% forces criticalSaver tier', () {
      final manager = PowerBudgetManager(initialBattery: 50.0);
      expect(manager.state.activeTier, equals(PowerBudgetTier.balanced));

      manager.updateBatteryStatus(
        batteryLevel: 12.0,
        chargingState: BatteryChargingState.unplugged,
      );
      expect(manager.state.activeTier, equals(PowerBudgetTier.criticalSaver));
    });

    // 4. Power tier transition while charging
    test('4. Connecting charger elevates power tier to highFidelity', () {
      final manager = PowerBudgetManager(initialBattery: 10.0);
      expect(manager.state.activeTier, equals(PowerBudgetTier.criticalSaver));

      manager.updateBatteryStatus(
        batteryLevel: 10.0,
        chargingState: BatteryChargingState.chargingAc,
      );
      expect(manager.state.isCharging, isTrue);
      expect(manager.state.activeTier, equals(PowerBudgetTier.highFidelity));
      expect(manager.state.telemetrySampleInterval.inSeconds, equals(10));
    });

    // 5. Burst of 10,000 queries with 100% buffer recycling
    test('5. High query burst preserves 100% buffer recycling ratio without leaks', () {
      final pool = RingBufferPool(capacity: 16);
      final processor = ZeroBatteryDnsProcessor(
        bufferPool: pool,
        isDomainBlocked: (d) => d.contains('block'),
      );

      final raw = Uint8List.fromList([
        0x12, 0x34, 0x01, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
        0x05, 0x62, 0x6c, 0x6f, 0x63, 0x6b, 0x03, 0x63, 0x6f, 0x6d, 0x00,
        0x00, 0x01, 0x00, 0x01,
      ]);

      for (int i = 0; i < 5000; i++) {
        final res = processor.processInboundPacket(raw, raw.length);
        res?.release();
      }

      final telemetry = pool.getTelemetry();
      expect(telemetry.totalAcquisitions, equals(5000));
      expect(telemetry.totalRecycles, equals(5000));
      expect(telemetry.activeLeases, equals(0));
      expect(telemetry.reuseRatio, equals(1.0));
    });

    // 6. Buffer exhaustion under extreme load
    test('6. Buffer exhaustion allocates transient buffers safely', () {
      final pool = RingBufferPool(capacity: 2);
      final leases = <PooledBuffer>[];

      for (int i = 0; i < 5; i++) {
        leases.add(pool.acquire());
      }

      expect(pool.getTelemetry().poolExhaustionEvents, equals(3));

      for (final buf in leases) {
        buf.release();
      }

      expect(pool.availableCount, equals(2));
      expect(pool.leasedCount, equals(0));
    });

    // 7. Corrupted DNS headers (all 0s)
    test('7. Corrupted all-zero packet rejected cleanly', () {
      final processor = ZeroBatteryDnsProcessor(isDomainBlocked: (_) => false);
      final zeroes = Uint8List(32);
      expect(processor.parseQuery(zeroes, zeroes.length), isNull);
    });

    // 8. Compression pointer loop attack prevention
    test('8. Malformed compression pointer sequence terminates cleanly without infinite loop', () {
      final processor = ZeroBatteryDnsProcessor(isDomainBlocked: (_) => false);
      final raw = Uint8List.fromList([
        0xAA, 0xBB, 0x01, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
        0xC0, 0x0C, // Pointer pointing to itself!
        0x00, 0x01, 0x00, 0x01,
      ]);

      // Must not hang or timeout
      final payload = processor.parseQuery(raw, raw.length);
      expect(payload, isNotNull);
    });

    // 9. Deep Doze alarm trigger during midnight rollover
    test('9. DozeSentinelCoordinator tracks heartbeat and updates timestamp', () {
      final coordinator = DozeSentinelCoordinator(heartbeatInterval: const Duration(seconds: 1));
      coordinator.recordHeartbeatPulse();

      expect(coordinator.snapshot.lastHeartbeat, isNotNull);
      coordinator.dispose();
    });

    // 10. Watchdog exponential backoff ceiling at 30 seconds
    test('10. Backoff duration never exceeds 30 seconds regardless of failure count', () {
      final watchdog = ResilientWatchdogController();
      for (int i = 0; i < 50; i++) {
        watchdog.recordResurrection(reason: 'Crash');
      }
      expect(watchdog.calculateBackoff().inSeconds, equals(30));
    });

    // 11. Stability mark after 5 minutes
    test('11. Marking stable clears consecutive failure count', () {
      final watchdog = ResilientWatchdogController();
      watchdog.recordResurrection(reason: 'Fail 1');
      watchdog.recordResurrection(reason: 'Fail 2');
      expect(watchdog.consecutiveFailures, equals(2));

      watchdog.markStable();
      expect(watchdog.consecutiveFailures, equals(0));
    });

    // 12. OEM device probe with missing build properties
    test('12. Empty device probe falls back to Generic AOSP gracefully', () {
      final profile = OemDeviceProfiles.resolveProfile(manufacturer: '', brand: '');
      expect(profile.family, equals(OemFamily.genericAosp));
    });

    // 13. Multiple consecutive missed heartbeats
    test('13. Health status transitions from optimal to healed when self-healing is invoked', () {
      final coordinator = DozeSentinelCoordinator();
      expect(coordinator.snapshot.healthStatus, equals(DaemonHealthStatus.optimal));

      coordinator.triggerSelfHealing('Watchdog heartbeat pulse timeout');
      expect(coordinator.snapshot.healthStatus, equals(DaemonHealthStatus.healed));
      coordinator.dispose();
    });

    // 14. Anomaly detector catching extreme battery spikes
    test('14. Anomaly detector flags sudden 0.25%/hr drain rate spike', () {
      final detector = EnergyAnomalyDetector();
      detector.inspectMetrics(currentHourlyDrainPct: 0.25, queriesInLastMinute: 50, activeWakeLocks: 0);

      expect(detector.alerts.length, equals(1));
      expect(detector.alerts.first.severity, equals(AnomalySeverity.critical));
    });

    // 15. Anomaly detector catching 1,000 queries/min flood loop
    test('15. Anomaly detector flags 1,200 queries/min rogue retry loop', () {
      final detector = EnergyAnomalyDetector();
      detector.inspectMetrics(currentHourlyDrainPct: 0.04, queriesInLastMinute: 1200, activeWakeLocks: 0);

      expect(detector.alerts.length, equals(1));
      expect(detector.alerts.first.title, contains('Query Loop'));
    });

    // 16. Wake-lock duration violation tripping alert
    test('16. Active wake-lock trips critical policy breach alert', () {
      final detector = EnergyAnomalyDetector();
      detector.inspectMetrics(currentHourlyDrainPct: 0.04, queriesInLastMinute: 50, activeWakeLocks: 1);

      expect(detector.alerts.length, equals(1));
      expect(detector.alerts.first.title, contains('Wake-Lock Policy Breach'));
    });

    // 17. OemResilienceAuditor edge score boundary capping at 100
    test('17. Scorecard score never exceeds 100 points', () {
      const probe = DeviceHardwareProbe(
        manufacturer: 'Google',
        brand: 'Pixel',
        model: 'Pixel 8',
        hardware: 'shiba',
        buildFingerprint: 'google/shiba',
        romVersion: 'Android 14',
        sdkInt: 34,
        isDozeExempted: true,
        isAutostartGranted: true,
        isLockedInRecents: true,
      );
      final scorecard = OemResilienceAuditor.auditDevice(profile: OemDeviceProfiles.pixel, probe: probe);
      expect(scorecard.totalScore, lessThanOrEqualTo(100));
    });

    // 18. OemResilienceAuditor edge score boundary floor at 0
    test('18. Scorecard score never drops below 0 points', () {
      const probe = DeviceHardwareProbe(
        manufacturer: 'Unknown',
        brand: 'Unknown',
        model: 'Generic',
        hardware: 'generic',
        buildFingerprint: '',
        romVersion: '',
        sdkInt: 21,
        isDozeExempted: false,
        isAutostartGranted: false,
        isLockedInRecents: false,
      );
      final scorecard = OemResilienceAuditor.auditDevice(profile: OemDeviceProfiles.genericAosp, probe: probe);
      expect(scorecard.totalScore, greaterThanOrEqualTo(0));
    });

    // 19. PowerHistorian rolling buffer eviction at 24 entries
    test('19. PowerHistorian limits history buffer to 24 entries', () {
      final historian = PowerHistorianRecorder();
      historian.clearHistory();

      for (int i = 0; i < 50; i++) {
        historian.recordHourlySnapshot(hourlyDrainPct: 0.04, packets: 100, sinkholes: 50, wasCharging: false);
      }
      expect(historian.history.length, equals(24));
    });

    // 20. PowerHistorian non-charging drain summation
    test('20. PowerHistorian excludes charging intervals from total drain calculation', () {
      final historian = PowerHistorianRecorder();
      historian.clearHistory();

      historian.recordHourlySnapshot(hourlyDrainPct: 0.05, packets: 100, sinkholes: 50, wasCharging: false);
      historian.recordHourlySnapshot(hourlyDrainPct: 0.05, packets: 100, sinkholes: 50, wasCharging: false);
      historian.recordHourlySnapshot(hourlyDrainPct: 0.00, packets: 100, sinkholes: 50, wasCharging: true);

      expect(historian.total24HourDrain, closeTo(0.10, 0.001));
    });

    // 21. Dynamic packet throughput calculation
    test('21. Profiler correctly computes hit ratio with 0 packets', () {
      final profiler = BatteryDrainProfiler();
      final snapshot = profiler.computeSnapshot();
      expect(snapshot.zeroCopyBufferHitRatio, equals(1.0));
    });

    // 22. DirectByteBuffer zero-copy reuse ratio verification
    test('22. RingBufferPool resetMetrics resets all acquisition counters', () {
      final pool = RingBufferPool(capacity: 4);
      final buf = pool.acquire();
      buf.release();

      expect(pool.getTelemetry().totalAcquisitions, equals(1));
      pool.resetMetrics();
      expect(pool.getTelemetry().totalAcquisitions, equals(0));
    });

    // 23. PowerBudgetManager wake-lock violation counter increment and reset
    test('23. PowerBudgetManager tracks and resets wake lock violations', () {
      final manager = PowerBudgetManager();
      expect(manager.state.activeWakeLockViolations, equals(0));

      manager.recordWakeLockViolation();
      manager.recordWakeLockViolation();
      expect(manager.state.activeWakeLockViolations, equals(2));

      manager.resetWakeLockViolations();
      expect(manager.state.activeWakeLockViolations, equals(0));
    });

    // 24. DeviceBootReceiver action matching logic
    test('24. OemDeviceProfile correctly matches various case-insensitive brand names', () {
      final profile = OemDeviceProfiles.xiaomi;
      expect(profile.matchesDevice(manufacturer: 'XIAOMI', brand: 'POCO'), isTrue);
      expect(profile.matchesDevice(manufacturer: 'redmi', brand: 'redmi'), isTrue);
      expect(profile.matchesDevice(manufacturer: 'BlackShark', brand: 'BlackShark'), isTrue);
      expect(profile.matchesDevice(manufacturer: 'Samsung', brand: 'Galaxy'), isFalse);
    });

    // 25. End-to-end full daemon lifecycle stress loop
    test('25. End-to-end daemon lifecycle processes packets, audits power, and updates coordinator', () {
      final clock = AntiTamperClock();
      final pool = RingBufferPool(capacity: 16);
      final profiler = BatteryDrainProfiler();
      final coordinator = DozeSentinelCoordinator(clock: clock);

      final processor = ZeroBatteryDnsProcessor(
        bufferPool: pool,
        isDomainBlocked: (d) => d == 'ads.tracker.com',
      );

      final rawBlock = Uint8List.fromList([
        0x11, 0x22, 0x01, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
        0x03, 0x61, 0x64, 0x73, 0x07, 0x74, 0x72, 0x61, 0x63, 0x6b, 0x65, 0x72, 0x03, 0x63, 0x6f, 0x6d, 0x00,
        0x00, 0x01, 0x00, 0x01,
      ]);

      // Process 50 blocked queries
      for (int i = 0; i < 50; i++) {
        final res = processor.processInboundPacket(rawBlock, rawBlock.length);
        expect(res, isNotNull);
        res?.release();
      }

      profiler.recordPacketBatch(
        totalInBatch: 50,
        sinkholedInBatch: 50,
        zeroCopyHitsInBatch: 50,
      );

      coordinator.recordHeartbeatPulse();

      final snapshot = profiler.computeSnapshot();
      expect(snapshot.sinkholedPackets, equals(50));
      expect(snapshot.projected24hDrainPercentage, lessThan(1.0));
      expect(coordinator.snapshot.healthStatus, equals(DaemonHealthStatus.optimal));

      coordinator.dispose();
    });
  });
}
