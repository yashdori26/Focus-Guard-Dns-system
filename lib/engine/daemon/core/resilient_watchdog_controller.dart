import 'package:flutter/foundation.dart';

/// Single log entry for a background self-healing or resurrection event.
@immutable
class ResurrectionEvent {
  final DateTime timestamp;
  final String reason;
  final int attemptNumber;
  final Duration backoffDuration;

  const ResurrectionEvent({
    required this.timestamp,
    required this.reason,
    required this.attemptNumber,
    required this.backoffDuration,
  });

  Map<String, dynamic> toJson() => {
        'timestamp': timestamp.toIso8601String(),
        'reason': reason,
        'attemptNumber': attemptNumber,
        'backoffDurationMs': backoffDuration.inMilliseconds,
      };
}

/// Controller managing silent process resurrection, crash-loop backoff delays,
/// and stability audit logs.
class ResilientWatchdogController extends ChangeNotifier {
  final List<ResurrectionEvent> _history = [];
  int _consecutiveFailures = 0;
  DateTime? _lastFailureTimestamp;

  List<ResurrectionEvent> get history => List.unmodifiable(_history);
  int get consecutiveFailures => _consecutiveFailures;
  DateTime? get lastFailureTimestamp => _lastFailureTimestamp;

  /// Calculates next backoff duration using exponential curve: min(2^(n) * 100ms, 30s)
  Duration calculateBackoff() {
    if (_consecutiveFailures <= 0) return Duration.zero;
    final int seconds = (1 << _consecutiveFailures).clamp(1, 30);
    return Duration(seconds: seconds);
  }

  /// Records a self-healing resurrection event.
  void recordResurrection({required String reason}) {
    _consecutiveFailures++;
    _lastFailureTimestamp = DateTime.now();

    final backoff = calculateBackoff();
    final event = ResurrectionEvent(
      timestamp: _lastFailureTimestamp!,
      reason: reason,
      attemptNumber: _consecutiveFailures,
      backoffDuration: backoff,
    );

    _history.add(event);
    if (_history.length > 100) {
      _history.removeAt(0);
    }

    notifyListeners();
  }

  /// Resets consecutive failure counter when stable operation is achieved for > 5 minutes.
  void markStable() {
    if (_consecutiveFailures > 0) {
      _consecutiveFailures = 0;
      notifyListeners();
    }
  }

  /// Clears event log for testing.
  void clearHistory() {
    _history.clear();
    _consecutiveFailures = 0;
    _lastFailureTimestamp = null;
    notifyListeners();
  }
}
