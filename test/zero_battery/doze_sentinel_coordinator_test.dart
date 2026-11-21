import 'package:flutter_test/flutter_test.dart';
import 'package:focus_dns/engine/daemon/core/doze_sentinel_coordinator.dart';
import 'package:focus_dns/engine/daemon/core/resilient_watchdog_controller.dart';
import 'package:focus_dns/engine/per_app/core/anti_tamper_clock.dart';

void main() {
  group('1. ResilientWatchdogController Backoff & Resurrection Tests', () {
    late ResilientWatchdogController watchdog;

    setUp(() {
      watchdog = ResilientWatchdogController();
    });

    test('Initial state has zero failures and no backoff', () {
      expect(watchdog.consecutiveFailures, equals(0));
      expect(watchdog.calculateBackoff(), equals(Duration.zero));
      expect(watchdog.history, isEmpty);
    });

    test('Calculates exponential backoff capped at 30 seconds', () {
      // 1st failure: 2^1 = 2s
      watchdog.recordResurrection(reason: 'Process killed by LMK');
      expect(watchdog.consecutiveFailures, equals(1));
      expect(watchdog.calculateBackoff(), equals(const Duration(seconds: 2)));

      // Multiple failures cap at 30s
      for (int i = 0; i < 10; i++) {
        watchdog.recordResurrection(reason: 'SIGKILL');
      }
      expect(watchdog.calculateBackoff(), equals(const Duration(seconds: 30)));
    });

    test('Marking stable resets failure counter', () {
      watchdog.recordResurrection(reason: 'Test kill');
      expect(watchdog.consecutiveFailures, equals(1));

      watchdog.markStable();
      expect(watchdog.consecutiveFailures, equals(0));
      expect(watchdog.calculateBackoff(), equals(Duration.zero));
    });

    test('ResurrectionEvent JSON serialization round-trip', () {
      watchdog.recordResurrection(reason: 'MIUI PowerKeeper strike');
      final event = watchdog.history.first;
      final json = event.toJson();

      expect(json['reason'], equals('MIUI PowerKeeper strike'));
      expect(json['attemptNumber'], equals(1));
    });
  });

  group('2. DozeSentinelCoordinator Dual-Sentinel Tests', () {
    late AntiTamperClock clock;
    late ResilientWatchdogController watchdog;
    late DozeSentinelCoordinator coordinator;

    setUp(() {
      clock = AntiTamperClock();
      watchdog = ResilientWatchdogController();
      coordinator = DozeSentinelCoordinator(
        clock: clock,
        watchdog: watchdog,
        heartbeatInterval: const Duration(seconds: 5),
      );
    });

    tearDown(() {
      coordinator.dispose();
    });

    test('Initial snapshot has optimal health and 100% uptime', () {
      final snapshot = coordinator.snapshot;
      expect(snapshot.healthStatus, equals(DaemonHealthStatus.optimal));
      expect(snapshot.uptimePercentage, equals(100.0));
      expect(snapshot.consecutiveMissedHeartbeats, equals(0));
    });

    test('Heartbeat pulse updates last heartbeat and increments uptime', () {
      coordinator.recordHeartbeatPulse();
      coordinator.recordHeartbeatPulse();

      final snapshot = coordinator.snapshot;
      expect(snapshot.uptimePercentage, equals(100.0));
      expect(snapshot.consecutiveMissedHeartbeats, equals(0));
    });

    test('Self-healing resurrection changes health to healed status', () {
      coordinator.triggerSelfHealing('Watchdog heartbeat timeout');

      final snapshot = coordinator.snapshot;
      expect(snapshot.totalSelfHealingRestarts, equals(1));
      expect(snapshot.healthStatus, equals(DaemonHealthStatus.healed));
      expect(watchdog.history.length, equals(1));
    });

    test('UpdateStatus updates VPN and Doze flags atomically', () {
      coordinator.updateStatus(
        isVpnRunning: true,
        isWatchdogRunning: true,
        isDozeExempted: true,
      );

      final snapshot = coordinator.snapshot;
      expect(snapshot.isVpnRunning, isTrue);
      expect(snapshot.isWatchdogRunning, isTrue);
      expect(snapshot.isDozeExempted, isTrue);
    });

    test('SentinelSnapshot JSON serialization round-trip', () {
      final snapshot = coordinator.snapshot;
      final json = snapshot.toJson();

      expect(json['healthStatus'], equals('optimal'));
      expect(json['uptimePercentage'], equals(100.0));
      expect(json['totalSelfHealingRestarts'], equals(0));
    });
  });
}
