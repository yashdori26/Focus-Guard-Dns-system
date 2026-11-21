import 'package:flutter/foundation.dart';

/// Severity of an energy anomaly alert.
enum AnomalySeverity {
  info,
  warning,
  critical,
}

/// Structured anomaly report.
@immutable
class EnergyAnomalyAlert {
  final String alertId;
  final DateTime timestamp;
  final AnomalySeverity severity;
  final String title;
  final String description;
  final String recommendedRemediation;
  final double metricValue;

  const EnergyAnomalyAlert({
    required this.alertId,
    required this.timestamp,
    required this.severity,
    required this.title,
    required this.description,
    required this.recommendedRemediation,
    required this.metricValue,
  });

  Map<String, dynamic> toJson() => {
        'alertId': alertId,
        'timestamp': timestamp.toIso8601String(),
        'severity': severity.name,
        'title': title,
        'description': description,
        'recommendedRemediation': recommendedRemediation,
        'metricValue': metricValue,
      };
}

/// Statistical anomaly detector identifying abnormal battery drain spikes,
/// infinite packet loops, and rogue background wakeups.
class EnergyAnomalyDetector extends ChangeNotifier {
  final List<EnergyAnomalyAlert> _alerts = [];
  final double hourlyDrainThreshold;
  final int queryBurstThresholdPerMinute;

  EnergyAnomalyDetector({
    this.hourlyDrainThreshold = 0.08, // > 0.08% / hr is anomalous
    this.queryBurstThresholdPerMinute = 300, // > 300 queries/min is an app loop
  });

  List<EnergyAnomalyAlert> get alerts => List.unmodifiable(_alerts);

  /// Inspects current metrics for anomalous behavior.
  void inspectMetrics({
    required double currentHourlyDrainPct,
    required int queriesInLastMinute,
    required int activeWakeLocks,
  }) {
    final now = DateTime.now();

    // 1. Drain rate anomaly
    if (currentHourlyDrainPct > hourlyDrainThreshold) {
      _addAlert(EnergyAnomalyAlert(
        alertId: 'drain_spike_${now.millisecondsSinceEpoch}',
        timestamp: now,
        severity: currentHourlyDrainPct > (hourlyDrainThreshold * 2)
            ? AnomalySeverity.critical
            : AnomalySeverity.warning,
        title: 'Elevated Energy Consumption Detected',
        description:
            'Hourly battery drain spiked to ${(currentHourlyDrainPct).toStringAsFixed(3)}%/hr (normal is < 0.045%/hr).',
        recommendedRemediation:
            'Verify that non-DNS traffic is not being routed through the tunnel.',
        metricValue: currentHourlyDrainPct,
      ));
    }

    // 2. Query burst / retry loop anomaly
    if (queriesInLastMinute > queryBurstThresholdPerMinute) {
      _addAlert(EnergyAnomalyAlert(
        alertId: 'query_burst_${now.millisecondsSinceEpoch}',
        timestamp: now,
        severity: AnomalySeverity.warning,
        title: 'Rogue App Query Loop Detected',
        description:
            '$queriesInLastMinute DNS queries intercepted in the last 60 seconds.',
        recommendedRemediation:
            'A blocked app is repeatedly retrying network requests. Ensure local NXDOMAIN sinkholing is active.',
        metricValue: queriesInLastMinute.toDouble(),
      ));
    }

    // 3. Wake lock violation
    if (activeWakeLocks > 0) {
      _addAlert(EnergyAnomalyAlert(
        alertId: 'wakelock_violation_${now.millisecondsSinceEpoch}',
        timestamp: now,
        severity: AnomalySeverity.critical,
        title: 'Zero Wake-Lock Policy Breach',
        description: '$activeWakeLocks partial wake-locks currently active.',
        recommendedRemediation:
            'Terminate background wake-locks immediately to preserve deep sleep state.',
        metricValue: activeWakeLocks.toDouble(),
      ));
    }
  }

  void _addAlert(EnergyAnomalyAlert alert) {
    _alerts.insert(0, alert);
    if (_alerts.length > 50) {
      _alerts.removeLast();
    }
    notifyListeners();
  }

  /// Clears alerts for testing.
  void clearAlerts() {
    _alerts.clear();
    notifyListeners();
  }
}
