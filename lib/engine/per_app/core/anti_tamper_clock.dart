import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// High-precision clock that anchors to monotonic hardware ticks to detect and defeat system clock rollback attempts.
class AntiTamperClock {
  final Stopwatch _stopwatch = Stopwatch();
  late DateTime _anchorWallTime;
  int _tamperingStrikeCount = 0;
  DateTime? _lastTamperingDetectedAt;
  bool _isNetworkSynced = false;

  AntiTamperClock({DateTime? initialAnchor}) {
    _anchorWallTime = initialAnchor ?? DateTime.now();
    _stopwatch.start();
  }

  int get tamperingStrikeCount => _tamperingStrikeCount;
  DateTime? get lastTamperingDetectedAt => _lastTamperingDetectedAt;
  bool get isNetworkSynced => _isNetworkSynced;

  /// Returns the current monotonic-stabilized timestamp immune to wall clock rollback.
  DateTime get monotonicNow {
    final elapsedMicros = _stopwatch.elapsedMicroseconds;
    return _anchorWallTime.add(Duration(microseconds: elapsedMicros));
  }

  /// Inspects the device wall clock against monotonic elapsed time.
  /// If the wall clock was wound back or abruptly skipped forward, flags a tamper strike.
  bool verifyAgainstWallClock(DateTime systemWallClock) {
    final expected = monotonicNow;
    final driftSeconds = systemWallClock.difference(expected).inSeconds.abs();

    // If clock drifted more than 3 minutes (180s) away from monotonic progression
    if (driftSeconds > 180) {
      _tamperingStrikeCount++;
      _lastTamperingDetectedAt = systemWallClock;
      debugPrint('[AntiTamperClock] TAMPERING DETECTED! Clock drift: ${driftSeconds}s. Strikes: $_tamperingStrikeCount');
      return false;
    }
    return true;
  }

  /// Queries a trusted HTTP endpoint date header or NTP fallback to calibrate the anchor.
  Future<bool> syncWithNetworkTime() async {
    try {
      final response = await http.head(Uri.parse('https://www.google.com')).timeout(const Duration(seconds: 4));
      final dateHeader = response.headers['date'];
      if (dateHeader != null) {
        final netDate = DateTime.tryParse(dateHeader);
        if (netDate != null) {
          final oldAnchor = _anchorWallTime;
          _anchorWallTime = netDate.subtract(Duration(microseconds: _stopwatch.elapsedMicroseconds));
          _isNetworkSynced = true;
          debugPrint('[AntiTamperClock] Synchronized anchor to network time. Shift: ${netDate.difference(oldAnchor).inSeconds}s');
          return true;
        }
      }
    } catch (e) {
      debugPrint('[AntiTamperClock] Network time sync failed: $e (using monotonic hardware anchor)');
    }
    return false;
  }

  /// For testing: simulate a manual time shift on the anchor.
  @visibleForTesting
  void shiftAnchorForTesting(Duration delta) {
    _anchorWallTime = _anchorWallTime.add(delta);
  }
}
