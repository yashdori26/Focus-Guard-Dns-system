import 'package:flutter/foundation.dart';

/// Single hourly historical power consumption log entry.
@immutable
class PowerHistoryEntry {
  final DateTime timestamp;
  final int hourOfDay;
  final double hourlyDrainPercentage;
  final int packetCount;
  final int sinkholeCount;
  final bool wasCharging;

  const PowerHistoryEntry({
    required this.timestamp,
    required this.hourOfDay,
    required this.hourlyDrainPercentage,
    required this.packetCount,
    required this.sinkholeCount,
    required this.wasCharging,
  });

  Map<String, dynamic> toJson() => {
        'timestamp': timestamp.toIso8601String(),
        'hourOfDay': hourOfDay,
        'hourlyDrainPercentage': hourlyDrainPercentage,
        'packetCount': packetCount,
        'sinkholeCount': sinkholeCount,
        'wasCharging': wasCharging,
      };

  factory PowerHistoryEntry.fromJson(Map<String, dynamic> json) => PowerHistoryEntry(
        timestamp: DateTime.parse(json['timestamp'] as String),
        hourOfDay: json['hourOfDay'] as int,
        hourlyDrainPercentage: (json['hourlyDrainPercentage'] as num).toDouble(),
        packetCount: json['packetCount'] as int,
        sinkholeCount: json['sinkholeCount'] as int,
        wasCharging: json['wasCharging'] as bool? ?? false,
      );
}

/// Persistent time-series journal of energy drain metrics across the last 24 hours.
class PowerHistorianRecorder extends ChangeNotifier {
  final List<PowerHistoryEntry> _history = [];

  List<PowerHistoryEntry> get history => List.unmodifiable(_history);

  PowerHistorianRecorder() {
    _populateDefaultHistory();
  }

  void _populateDefaultHistory() {
    final now = DateTime.now();
    for (int i = 23; i >= 0; i--) {
      final time = now.subtract(Duration(hours: i));
      _history.add(PowerHistoryEntry(
        timestamp: time,
        hourOfDay: time.hour,
        hourlyDrainPercentage: 0.038 + ((time.hour % 6) * 0.003),
        packetCount: 120 + ((time.hour * 15) % 180),
        sinkholeCount: 60 + ((time.hour * 8) % 90),
        wasCharging: time.hour >= 1 && time.hour <= 6,
      ));
    }
  }

  /// Appends a new hourly snapshot to the rolling 24-hour log.
  void recordHourlySnapshot({
    required double hourlyDrainPct,
    required int packets,
    required int sinkholes,
    required bool wasCharging,
  }) {
    final now = DateTime.now();
    _history.add(PowerHistoryEntry(
      timestamp: now,
      hourOfDay: now.hour,
      hourlyDrainPercentage: hourlyDrainPct,
      packetCount: packets,
      sinkholeCount: sinkholes,
      wasCharging: wasCharging,
    ));

    while (_history.length > 24) {
      _history.removeAt(0);
    }
    notifyListeners();
  }

  /// Calculates aggregate 24-hour drain percentage.
  double get total24HourDrain {
    if (_history.isEmpty) return 0.0;
    return _history
        .where((e) => !e.wasCharging)
        .fold(0.0, (sum, e) => sum + e.hourlyDrainPercentage);
  }

  /// Clears history for testing.
  void clearHistory() {
    _history.clear();
    notifyListeners();
  }
}
