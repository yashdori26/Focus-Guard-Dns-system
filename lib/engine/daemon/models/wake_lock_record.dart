import 'package:flutter/foundation.dart';

/// Single wake-lock acquisition or system alarm trigger event.
@immutable
class WakeLockRecord {
  final String recordId;
  final String tag;
  final DateTime acquiredAt;
  final Duration heldDuration;
  final bool isViolation; // True if held > 50ms
  final String component;

  const WakeLockRecord({
    required this.recordId,
    required this.tag,
    required this.acquiredAt,
    required this.heldDuration,
    required this.isViolation,
    required this.component,
  });

  Map<String, dynamic> toJson() => {
        'recordId': recordId,
        'tag': tag,
        'acquiredAt': acquiredAt.toIso8601String(),
        'heldDurationMs': heldDuration.inMilliseconds,
        'isViolation': isViolation,
        'component': component,
      };

  factory WakeLockRecord.fromJson(Map<String, dynamic> json) => WakeLockRecord(
        recordId: json['recordId'] as String,
        tag: json['tag'] as String,
        acquiredAt: DateTime.parse(json['acquiredAt'] as String),
        heldDuration: Duration(milliseconds: json['heldDurationMs'] as int? ?? 0),
        isViolation: json['isViolation'] as bool? ?? false,
        component: json['component'] as String? ?? 'Daemon',
      );
}
