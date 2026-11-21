import 'dart:async';
import 'package:flutter/foundation.dart';
import '../../per_app/core/anti_tamper_clock.dart';
import 'resilient_watchdog_controller.dart';

/// Health status of the background daemon ecosystem.
enum DaemonHealthStatus {
  /// All daemons running normally with verified Doze exemption.
  optimal,

  /// Watchdog or VPN service experienced a restart, recovered successfully.
  healed,

  /// Missing heartbeat pulses; potential OEM task killer interference.
  degraded,

  /// Critical: Service has been killed multiple times within short window.
  critical,
}

/// Snapshot of the live dual-sentinel state.
@immutable
class SentinelSnapshot {
  final bool isVpnRunning;
  final bool isWatchdogRunning;
  final bool isDozeExempted;
  final DaemonHealthStatus healthStatus;
  final DateTime lastHeartbeat;
  final int consecutiveMissedHeartbeats;
  final int totalSelfHealingRestarts;
  final double uptimePercentage;

  const SentinelSnapshot({
    required this.isVpnRunning,
    required this.isWatchdogRunning,
    required this.isDozeExempted,
    required this.healthStatus,
    required this.lastHeartbeat,
    required this.consecutiveMissedHeartbeats,
    required this.totalSelfHealingRestarts,
    required this.uptimePercentage,
  });

  Map<String, dynamic> toJson() => {
        'isVpnRunning': isVpnRunning,
        'isWatchdogRunning': isWatchdogRunning,
        'isDozeExempted': isDozeExempted,
        'healthStatus': healthStatus.name,
        'lastHeartbeat': lastHeartbeat.toIso8601String(),
        'consecutiveMissedHeartbeats': consecutiveMissedHeartbeats,
        'totalSelfHealingRestarts': totalSelfHealingRestarts,
        'uptimePercentage': uptimePercentage,
      };
}

/// Dual-sentinel master coordinator ensuring continuous background protection
/// across deep Doze mode, app standby buckets, and OEM task-killer strikes.
class DozeSentinelCoordinator extends ChangeNotifier {
  final AntiTamperClock _clock;
  final ResilientWatchdogController _watchdog;

  bool _isVpnRunning = false;
  bool _isWatchdogRunning = false;
  bool _isDozeExempted = false;
  DateTime _lastHeartbeat;
  int _consecutiveMissedHeartbeats = 0;
  int _totalRestarts = 0;
  int _totalHeartbeatsChecked = 0;
  int _successfulHeartbeats = 0;

  Timer? _heartbeatTimer;
  final Duration _heartbeatInterval;

  DozeSentinelCoordinator({
    AntiTamperClock? clock,
    ResilientWatchdogController? watchdog,
    Duration heartbeatInterval = const Duration(seconds: 15),
  })  : _clock = clock ?? AntiTamperClock(),
        _watchdog = watchdog ?? ResilientWatchdogController(),
        _heartbeatInterval = heartbeatInterval,
        _lastHeartbeat = (clock ?? AntiTamperClock()).monotonicNow {
    _startHeartbeatMonitor();
  }

  SentinelSnapshot get snapshot => SentinelSnapshot(
        isVpnRunning: _isVpnRunning,
        isWatchdogRunning: _isWatchdogRunning,
        isDozeExempted: _isDozeExempted,
        healthStatus: _evaluateHealthStatus(),
        lastHeartbeat: _lastHeartbeat,
        consecutiveMissedHeartbeats: _consecutiveMissedHeartbeats,
        totalSelfHealingRestarts: _totalRestarts,
        uptimePercentage: calculateUptimePercentage(),
      );

  void _startHeartbeatMonitor() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(_heartbeatInterval, (_) => _checkPulse());
  }

  /// Evaluates health status of the background services.
  DaemonHealthStatus _evaluateHealthStatus() {
    if (_consecutiveMissedHeartbeats >= 4 || _totalRestarts >= 5) {
      return DaemonHealthStatus.critical;
    }
    if (_consecutiveMissedHeartbeats >= 2) {
      return DaemonHealthStatus.degraded;
    }
    if (_totalRestarts > 0) {
      return DaemonHealthStatus.healed;
    }
    return DaemonHealthStatus.optimal;
  }

  /// Calculates system uptime percentage.
  double calculateUptimePercentage() {
    if (_totalHeartbeatsChecked == 0) return 100.0;
    return ((_successfulHeartbeats / _totalHeartbeatsChecked) * 100.0).clamp(0.0, 100.0);
  }

  /// Records a successful heartbeat pulse from the native service.
  void recordHeartbeatPulse() {
    _totalHeartbeatsChecked++;
    _successfulHeartbeats++;
    _consecutiveMissedHeartbeats = 0;
    _lastHeartbeat = _clock.monotonicNow;
    notifyListeners();
  }

  /// Simulates pulse check.
  void _checkPulse() {
    _totalHeartbeatsChecked++;
    final now = _clock.monotonicNow;
    final diff = now.difference(_lastHeartbeat);

    if (diff > (_heartbeatInterval * 2)) {
      _consecutiveMissedHeartbeats++;
      // Trigger self-healing if needed
      if (_isVpnRunning && !_isWatchdogRunning) {
        triggerSelfHealing('Watchdog silent kill detected');
      }
    } else {
      _successfulHeartbeats++;
      _consecutiveMissedHeartbeats = 0;
    }
    notifyListeners();
  }

  /// Triggers self-healing resurrection.
  void triggerSelfHealing(String reason) {
    _totalRestarts++;
    _watchdog.recordResurrection(reason: reason);
    _lastHeartbeat = _clock.monotonicNow;
    _consecutiveMissedHeartbeats = 0;
    notifyListeners();
  }

  /// Updates daemon component operational status.
  void updateStatus({
    bool? isVpnRunning,
    bool? isWatchdogRunning,
    bool? isDozeExempted,
  }) {
    if (isVpnRunning != null) _isVpnRunning = isVpnRunning;
    if (isWatchdogRunning != null) _isWatchdogRunning = isWatchdogRunning;
    if (isDozeExempted != null) _isDozeExempted = isDozeExempted;
    notifyListeners();
  }

  @override
  void dispose() {
    _heartbeatTimer?.cancel();
    super.dispose();
  }
}
