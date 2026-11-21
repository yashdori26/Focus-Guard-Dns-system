import 'package:flutter_test/flutter_test.dart';
import 'package:focus_dns/engine/daemon/models/battery_profile_config.dart';
import 'package:focus_dns/engine/daemon/models/energy_benchmark_result.dart';
import 'package:focus_dns/engine/daemon/telemetry/battery_drain_profiler.dart';
import 'package:focus_dns/engine/daemon/telemetry/power_historian_recorder.dart';

void main() {
  group('1. BatteryProfileConfig Tests', () {
    test('Preset configurations initialize with expected budgets', () {
      final ultra = BatteryProfileConfig.ultraSaver();
      expect(ultra.mode, equals(BatteryPowerMode.ultraSaver));
      expect(ultra.maxDailyDrainBudgetPercentage, equals(0.5));
      expect(ultra.heartbeatCheckInterval.inSeconds, equals(60));

      final balanced = BatteryProfileConfig.balanced();
      expect(balanced.mode, equals(BatteryPowerMode.balanced));
      expect(balanced.maxDailyDrainBudgetPercentage, equals(1.0));

      final strict = BatteryProfileConfig.highStrictness();
      expect(strict.mode, equals(BatteryPowerMode.highStrictness));
      expect(strict.maxDailyDrainBudgetPercentage, equals(1.5));
    });

    test('BatteryProfileConfig JSON serialization round-trip', () {
      final config = BatteryProfileConfig.balanced();
      final json = config.toJson();
      final reconstructed = BatteryProfileConfig.fromJson(json);

      expect(reconstructed.mode, equals(config.mode));
      expect(reconstructed.maxDailyDrainBudgetPercentage, equals(config.maxDailyDrainBudgetPercentage));
      expect(reconstructed.enableStrictZeroWakeLock, isTrue);
    });
  });

  group('2. BatteryDrainProfiler Equations & Telemetry Tests', () {
    late BatteryDrainProfiler profiler;

    setUp(() {
      profiler = BatteryDrainProfiler(config: BatteryProfileConfig.balanced());
    });

    test('Initial snapshot reflects baseline hardware standby current', () {
      final snapshot = profiler.computeSnapshot();

      expect(snapshot.currentDrawMicroamperes, inInclusiveRange(100.0, 150.0));
      expect(snapshot.projected24hDrainPercentage, inInclusiveRange(0.01, 0.5));
      expect(snapshot.isOptimal, isTrue);
      expect(snapshot.activeWakeLocks, equals(0));
    });

    test('Sinkholed packets consume significantly less energy than forwarded packets', () {
      // Benchmark 10,000 pure sinkholed packets (no modem transmission)
      profiler.recordPacketBatch(
        totalInBatch: 10000,
        sinkholedInBatch: 10000,
        zeroCopyHitsInBatch: 10000,
      );
      final sinkholedSnapshot = profiler.computeSnapshot();

      profiler.resetCounters();

      // Benchmark 10,000 pure forwarded packets (activates cellular/Wi-Fi modem)
      profiler.recordPacketBatch(
        totalInBatch: 10000,
        sinkholedInBatch: 0,
        zeroCopyHitsInBatch: 10000,
      );
      final forwardedSnapshot = profiler.computeSnapshot();

      // Forwarded packets must have higher current draw due to radio transmission
      expect(
        forwardedSnapshot.currentDrawMicroamperes,
        greaterThan(sinkholedSnapshot.currentDrawMicroamperes),
      );
      expect(
        forwardedSnapshot.projected24hDrainPercentage,
        greaterThan(sinkholedSnapshot.projected24hDrainPercentage),
      );
    });

    test('EnergyProfileSnapshot JSON serialization round-trip', () {
      profiler.recordPacketBatch(totalInBatch: 500, sinkholedInBatch: 300, zeroCopyHitsInBatch: 500);
      final snapshot = profiler.computeSnapshot();
      final json = snapshot.toJson();

      expect(json['totalPacketsProcessed'], equals(500));
      expect(json['sinkholedPackets'], equals(300));
      expect(json['projected24hDrainPercentage'], isNotNull);
    });
  });

  group('3. PowerHistorianRecorder Tests', () {
    test('Initializes with 24-hour default rolling history', () {
      final historian = PowerHistorianRecorder();
      expect(historian.history.length, equals(24));
      expect(historian.total24HourDrain, inInclusiveRange(0.2, 1.2));
    });

    test('Appends hourly snapshots maintaining rolling 24-entry window', () {
      final historian = PowerHistorianRecorder();
      historian.clearHistory();

      for (int i = 0; i < 30; i++) {
        historian.recordHourlySnapshot(
          hourlyDrainPct: 0.04,
          packets: 150,
          sinkholes: 80,
          wasCharging: false,
        );
      }

      expect(historian.history.length, equals(24));
      expect(historian.total24HourDrain, closeTo(0.04 * 24, 0.001));
    });

    test('PowerHistoryEntry JSON serialization round-trip', () {
      final entry = PowerHistoryEntry(
        timestamp: DateTime.now(),
        hourOfDay: 14,
        hourlyDrainPercentage: 0.042,
        packetCount: 180,
        sinkholeCount: 95,
        wasCharging: false,
      );

      final json = entry.toJson();
      final reconstructed = PowerHistoryEntry.fromJson(json);

      expect(reconstructed.hourOfDay, equals(14));
      expect(reconstructed.hourlyDrainPercentage, equals(0.042));
      expect(reconstructed.packetCount, equals(180));
    });
  });

  group('4. EnergyBenchmarkResult Model Tests', () {
    test('EnergyBenchmarkResult serialization and thresholds', () {
      final point = BenchmarkPoint(
        packetBatchSize: 1000,
        elapsedExecutionTime: const Duration(milliseconds: 45),
        averageLatencyMicroseconds: 45.0,
        simulatedMicroampereHours: 0.012,
        zeroCopyHits: 1000,
        gcAllocations: 0,
      );

      final result = EnergyBenchmarkResult(
        benchmarkId: 'bench_123',
        executedAt: DateTime.now(),
        totalPacketsSimulated: 1000,
        totalDuration: const Duration(milliseconds: 45),
        projected24hDrainPercentage: 0.88,
        passedZeroDrainThreshold: true,
        points: [point],
      );

      final json = result.toJson();
      expect(json['benchmarkId'], equals('bench_123'));
      expect(json['passedZeroDrainThreshold'], isTrue);
      expect((json['points'] as List).length, equals(1));
    });
  });
}
