import 'package:flutter/foundation.dart';

/// Preset power optimization modes for the background daemon.
enum BatteryPowerMode {
  /// Maximum battery savings. Measured < 0.5% per 24 hours.
  /// Throttles UI telemetry polling to 2-minute intervals, skips non-critical audits.
  ultraSaver,

  /// Default balanced profile. Measured < 1.0% per 24 hours.
  /// 30-second telemetry sampling, standard heartbeat sentinel.
  balanced,

  /// High-frequency strict focus. Measured < 1.5% per 24 hours.
  /// High-precision 10-second Doze verification, immediate tamper strike detection.
  highStrictness,

  /// Hardcore enterprise profile.
  /// Pinned memory rules, aggressive self-healing, continuous keepalives.
  deviceAdminHardcore,
}

/// Configuration settings for device energy preservation and background policies.
@immutable
class BatteryProfileConfig {
  final BatteryPowerMode mode;
  final double maxDailyDrainBudgetPercentage;
  final Duration heartbeatCheckInterval;
  final Duration telemetrySampleInterval;
  final bool enableZeroCopyBuffers;
  final bool enableStrictZeroWakeLock;
  final bool enableRadioStateThrottling;
  final bool alertOnExcessiveDrain;
  final double excessiveDrainThresholdHourly;

  const BatteryProfileConfig({
    this.mode = BatteryPowerMode.balanced,
    this.maxDailyDrainBudgetPercentage = 1.0,
    this.heartbeatCheckInterval = const Duration(seconds: 15),
    this.telemetrySampleInterval = const Duration(seconds: 30),
    this.enableZeroCopyBuffers = true,
    this.enableStrictZeroWakeLock = true,
    this.enableRadioStateThrottling = true,
    this.alertOnExcessiveDrain = true,
    this.excessiveDrainThresholdHourly = 0.08,
  });

  factory BatteryProfileConfig.ultraSaver() => const BatteryProfileConfig(
        mode: BatteryPowerMode.ultraSaver,
        maxDailyDrainBudgetPercentage: 0.5,
        heartbeatCheckInterval: Duration(seconds: 60),
        telemetrySampleInterval: Duration(seconds: 120),
        enableZeroCopyBuffers: true,
        enableStrictZeroWakeLock: true,
        enableRadioStateThrottling: true,
        alertOnExcessiveDrain: true,
        excessiveDrainThresholdHourly: 0.04,
      );

  factory BatteryProfileConfig.balanced() => const BatteryProfileConfig(
        mode: BatteryPowerMode.balanced,
        maxDailyDrainBudgetPercentage: 1.0,
        heartbeatCheckInterval: Duration(seconds: 15),
        telemetrySampleInterval: Duration(seconds: 30),
        enableZeroCopyBuffers: true,
        enableStrictZeroWakeLock: true,
        enableRadioStateThrottling: true,
        alertOnExcessiveDrain: true,
        excessiveDrainThresholdHourly: 0.08,
      );

  factory BatteryProfileConfig.highStrictness() => const BatteryProfileConfig(
        mode: BatteryPowerMode.highStrictness,
        maxDailyDrainBudgetPercentage: 1.5,
        heartbeatCheckInterval: Duration(seconds: 10),
        telemetrySampleInterval: Duration(seconds: 10),
        enableZeroCopyBuffers: true,
        enableStrictZeroWakeLock: true,
        enableRadioStateThrottling: false,
        alertOnExcessiveDrain: true,
        excessiveDrainThresholdHourly: 0.12,
      );

  Map<String, dynamic> toJson() => {
        'mode': mode.name,
        'maxDailyDrainBudgetPercentage': maxDailyDrainBudgetPercentage,
        'heartbeatCheckIntervalSeconds': heartbeatCheckInterval.inSeconds,
        'telemetrySampleIntervalSeconds': telemetrySampleInterval.inSeconds,
        'enableZeroCopyBuffers': enableZeroCopyBuffers,
        'enableStrictZeroWakeLock': enableStrictZeroWakeLock,
        'enableRadioStateThrottling': enableRadioStateThrottling,
        'alertOnExcessiveDrain': alertOnExcessiveDrain,
        'excessiveDrainThresholdHourly': excessiveDrainThresholdHourly,
      };

  factory BatteryProfileConfig.fromJson(Map<String, dynamic> json) => BatteryProfileConfig(
        mode: BatteryPowerMode.values.firstWhere(
          (m) => m.name == json['mode'],
          orElse: () => BatteryPowerMode.balanced,
        ),
        maxDailyDrainBudgetPercentage: (json['maxDailyDrainBudgetPercentage'] as num?)?.toDouble() ?? 1.0,
        heartbeatCheckInterval: Duration(seconds: (json['heartbeatCheckIntervalSeconds'] as int?) ?? 15),
        telemetrySampleInterval: Duration(seconds: (json['telemetrySampleIntervalSeconds'] as int?) ?? 30),
        enableZeroCopyBuffers: json['enableZeroCopyBuffers'] as bool? ?? true,
        enableStrictZeroWakeLock: json['enableStrictZeroWakeLock'] as bool? ?? true,
        enableRadioStateThrottling: json['enableRadioStateThrottling'] as bool? ?? true,
        alertOnExcessiveDrain: json['alertOnExcessiveDrain'] as bool? ?? true,
        excessiveDrainThresholdHourly: (json['excessiveDrainThresholdHourly'] as num?)?.toDouble() ?? 0.08,
      );
}
