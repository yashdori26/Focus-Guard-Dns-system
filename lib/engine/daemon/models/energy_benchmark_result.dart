import 'package:flutter/foundation.dart';

/// Single test point in the battery stress benchmark.
@immutable
class BenchmarkPoint {
  final int packetBatchSize;
  final Duration elapsedExecutionTime;
  final double averageLatencyMicroseconds;
  final double simulatedMicroampereHours;
  final int zeroCopyHits;
  final int gcAllocations;

  const BenchmarkPoint({
    required this.packetBatchSize,
    required this.elapsedExecutionTime,
    required this.averageLatencyMicroseconds,
    required this.simulatedMicroampereHours,
    required this.zeroCopyHits,
    required this.gcAllocations,
  });

  Map<String, dynamic> toJson() => {
        'packetBatchSize': packetBatchSize,
        'elapsedExecutionTimeMs': elapsedExecutionTime.inMilliseconds,
        'averageLatencyMicroseconds': averageLatencyMicroseconds,
        'simulatedMicroampereHours': simulatedMicroampereHours,
        'zeroCopyHits': zeroCopyHits,
        'gcAllocations': gcAllocations,
      };
}

/// Comprehensive benchmark results across 10 stress levels (100 to 100,000 queries).
@immutable
class EnergyBenchmarkResult {
  final String benchmarkId;
  final DateTime executedAt;
  final int totalPacketsSimulated;
  final Duration totalDuration;
  final double projected24hDrainPercentage;
  final bool passedZeroDrainThreshold; // True if projected < 1.0%/day
  final List<BenchmarkPoint> points;

  const EnergyBenchmarkResult({
    required this.benchmarkId,
    required this.executedAt,
    required this.totalPacketsSimulated,
    required this.totalDuration,
    required this.projected24hDrainPercentage,
    required this.passedZeroDrainThreshold,
    required this.points,
  });

  Map<String, dynamic> toJson() => {
        'benchmarkId': benchmarkId,
        'executedAt': executedAt.toIso8601String(),
        'totalPacketsSimulated': totalPacketsSimulated,
        'totalDurationMs': totalDuration.inMilliseconds,
        'projected24hDrainPercentage': projected24hDrainPercentage,
        'passedZeroDrainThreshold': passedZeroDrainThreshold,
        'points': points.map((p) => p.toJson()).toList(),
      };
}
