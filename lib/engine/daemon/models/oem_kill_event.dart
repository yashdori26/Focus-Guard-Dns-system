import 'package:flutter/foundation.dart';

/// Represents a detected background kill or OS process destruction event.
@immutable
class OemKillEvent {
  final String eventId;
  final DateTime timestamp;
  final String processName;
  final String presumedCulprit; // e.g. "MIUI PowerKeeper", "Samsung Sleeping Apps"
  final Duration downtimeDuration;
  final bool recoveredSuccessfully;
  final String exitReason;

  const OemKillEvent({
    required this.eventId,
    required this.timestamp,
    required this.processName,
    required this.presumedCulprit,
    required this.downtimeDuration,
    required this.recoveredSuccessfully,
    required this.exitReason,
  });

  Map<String, dynamic> toJson() => {
        'eventId': eventId,
        'timestamp': timestamp.toIso8601String(),
        'processName': processName,
        'presumedCulprit': presumedCulprit,
        'downtimeDurationMs': downtimeDuration.inMilliseconds,
        'recoveredSuccessfully': recoveredSuccessfully,
        'exitReason': exitReason,
      };

  factory OemKillEvent.fromJson(Map<String, dynamic> json) => OemKillEvent(
        eventId: json['eventId'] as String,
        timestamp: DateTime.parse(json['timestamp'] as String),
        processName: json['processName'] as String,
        presumedCulprit: json['presumedCulprit'] as String,
        downtimeDuration: Duration(milliseconds: json['downtimeDurationMs'] as int? ?? 0),
        recoveredSuccessfully: json['recoveredSuccessfully'] as bool? ?? true,
        exitReason: json['exitReason'] as String? ?? 'SIGKILL',
      );
}
