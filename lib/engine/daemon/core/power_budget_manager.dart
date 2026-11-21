import 'dart:async';
import 'package:flutter/foundation.dart';

/// Hardware charging state of the device.
enum BatteryChargingState {
  unplugged,
  chargingAc,
  chargingUsb,
  chargingWireless,
  full,
}

/// Dynamic power mode profile.
enum PowerBudgetTier {
  /// < 15% battery: Maximizes battery life, delays telemetry, strict zero wake-lock.
  criticalSaver,

  /// 15% - 40% battery: Reduced polling, throttled background sync.
  conservative,

  /// 40% - 80% battery: Normal balanced operation.
  balanced,

  /// 80%+ or Charging: Real-time high-fidelity metrics and analytics.
  highFidelity,
}

/// Snapshot of system power budget and governing parameters.
@immutable
class PowerBudgetState {
  final double batteryLevelPercentage;
  final BatteryChargingState chargingState;
  final double batteryTemperatureCelsius;
  final PowerBudgetTier activeTier;
  final Duration telemetrySampleInterval;
  final int activeWakeLockViolations;
  final bool isThermalThrottled;

  const PowerBudgetState({
    required this.batteryLevelPercentage,
    required this.chargingState,
    required this.batteryTemperatureCelsius,
    required this.activeTier,
    required this.telemetrySampleInterval,
    this.activeWakeLockViolations = 0,
    this.isThermalThrottled = false,
  });

  bool get isCharging =>
      chargingState == BatteryChargingState.chargingAc ||
      chargingState == BatteryChargingState.chargingUsb ||
      chargingState == BatteryChargingState.chargingWireless ||
      chargingState == BatteryChargingState.full;

  Map<String, dynamic> toJson() => {
        'batteryLevelPercentage': batteryLevelPercentage,
        'chargingState': chargingState.name,
        'batteryTemperatureCelsius': batteryTemperatureCelsius,
        'activeTier': activeTier.name,
        'telemetrySampleIntervalSeconds': telemetrySampleInterval.inSeconds,
        'activeWakeLockViolations': activeWakeLockViolations,
        'isThermalThrottled': isThermalThrottled,
      };
}

/// Dynamic governor that adjusts background polling and telemetry frequency
/// based on device power budget, battery level, and thermal headroom.
class PowerBudgetManager extends ChangeNotifier {
  PowerBudgetState _state;
  final List<void Function(PowerBudgetState state)> _listeners = [];

  PowerBudgetManager({
    double initialBattery = 75.0,
    BatteryChargingState initialCharging = BatteryChargingState.unplugged,
    double initialTemp = 28.5,
  }) : _state = _computeState(
          batteryLevel: initialBattery,
          chargingState: initialCharging,
          temperature: initialTemp,
          wakeLocks: 0,
        );

  PowerBudgetState get state => _state;

  static PowerBudgetState _computeState({
    required double batteryLevel,
    required BatteryChargingState chargingState,
    required double temperature,
    required int wakeLocks,
  }) {
    final bool isCharging = chargingState != BatteryChargingState.unplugged;
    final bool isThermal = temperature > 42.0;

    PowerBudgetTier tier;
    Duration interval;

    if (isCharging) {
      tier = PowerBudgetTier.highFidelity;
      interval = const Duration(seconds: 10);
    } else if (batteryLevel < 15.0 || isThermal) {
      tier = PowerBudgetTier.criticalSaver;
      interval = const Duration(seconds: 120);
    } else if (batteryLevel < 40.0) {
      tier = PowerBudgetTier.conservative;
      interval = const Duration(seconds: 60);
    } else {
      tier = PowerBudgetTier.balanced;
      interval = const Duration(seconds: 30);
    }

    return PowerBudgetState(
      batteryLevelPercentage: batteryLevel.clamp(0.0, 100.0),
      chargingState: chargingState,
      batteryTemperatureCelsius: temperature,
      activeTier: tier,
      telemetrySampleInterval: interval,
      activeWakeLockViolations: wakeLocks,
      isThermalThrottled: isThermal,
    );
  }

  /// Updates hardware battery metrics and re-evaluates power tier.
  void updateBatteryStatus({
    required double batteryLevel,
    required BatteryChargingState chargingState,
    double temperature = 28.0,
  }) {
    _state = _computeState(
      batteryLevel: batteryLevel,
      chargingState: chargingState,
      temperature: temperature,
      wakeLocks: _state.activeWakeLockViolations,
    );
    notifyListeners();
  }

  /// Records a wake lock tripwire event.
  void recordWakeLockViolation() {
    _state = PowerBudgetState(
      batteryLevelPercentage: _state.batteryLevelPercentage,
      chargingState: _state.chargingState,
      batteryTemperatureCelsius: _state.batteryTemperatureCelsius,
      activeTier: _state.activeTier,
      telemetrySampleInterval: _state.telemetrySampleInterval,
      activeWakeLockViolations: _state.activeWakeLockViolations + 1,
      isThermalThrottled: _state.isThermalThrottled,
    );
    notifyListeners();
  }

  /// Resets wake lock counter.
  void resetWakeLockViolations() {
    _state = PowerBudgetState(
      batteryLevelPercentage: _state.batteryLevelPercentage,
      chargingState: _state.chargingState,
      batteryTemperatureCelsius: _state.batteryTemperatureCelsius,
      activeTier: _state.activeTier,
      telemetrySampleInterval: _state.telemetrySampleInterval,
      activeWakeLockViolations: 0,
      isThermalThrottled: _state.isThermalThrottled,
    );
    notifyListeners();
  }
}
