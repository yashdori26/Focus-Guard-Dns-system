import 'package:flutter/foundation.dart';

/// Comprehensive lifecycle telemetry measuring focus sessions, break integrity,
/// adherence ratios, and doomscroll avoidance over longitudinal timeframes.
@immutable
class SessionLifecycleMetrics {
  final int sessionsInitiated;
  final int sessionsCompleted;
  final int sessionsAborted;
  final int strictLocksEnforced;
  final int breakOvershootsPrevented;
  final int frictionPledgesSubmitted;
  final int emergencyRequestsInitiated;
  final int emergencyRequestsApproved;
  final int totalFocusMinutes;
  final int totalBreakMinutes;
  final int totalDistractionInterceptions;
  final int bandwidthBytesSaved;
  final DateTime lastRecordedAt;

  const SessionLifecycleMetrics({
    required this.sessionsInitiated,
    required this.sessionsCompleted,
    required this.sessionsAborted,
    required this.strictLocksEnforced,
    required this.breakOvershootsPrevented,
    required this.frictionPledgesSubmitted,
    required this.emergencyRequestsInitiated,
    required this.emergencyRequestsApproved,
    required this.totalFocusMinutes,
    required this.totalBreakMinutes,
    required this.totalDistractionInterceptions,
    required this.bandwidthBytesSaved,
    required this.lastRecordedAt,
  });

  /// Default empty baseline metrics.
  factory SessionLifecycleMetrics.empty() {
    return SessionLifecycleMetrics(
      sessionsInitiated: 0,
      sessionsCompleted: 0,
      sessionsAborted: 0,
      strictLocksEnforced: 0,
      breakOvershootsPrevented: 0,
      frictionPledgesSubmitted: 0,
      emergencyRequestsInitiated: 0,
      emergencyRequestsApproved: 0,
      totalFocusMinutes: 0,
      totalBreakMinutes: 0,
      totalDistractionInterceptions: 0,
      bandwidthBytesSaved: 0,
      lastRecordedAt: DateTime.now(),
    );
  }

  /// Calculates adherence percentage (0.0% to 100.0%).
  double get adherenceRate {
    if (sessionsInitiated == 0) return 100.0;
    final rate = (sessionsCompleted / sessionsInitiated) * 100.0;
    return rate.clamp(0.0, 100.0);
  }

  /// Calculates average focus session length in minutes.
  double get averageFocusSessionMinutes {
    if (sessionsCompleted == 0) return 0.0;
    return totalFocusMinutes / sessionsCompleted;
  }

  /// Calculates ratio of focus time to break time.
  double get focusToBreakRatio {
    if (totalBreakMinutes == 0) return totalFocusMinutes > 0 ? 10.0 : 1.0;
    return totalFocusMinutes / totalBreakMinutes;
  }

  /// Calculates total hours reclaimed.
  double get totalHoursReclaimed {
    return totalFocusMinutes / 60.0;
  }

  /// Calculates estimated megabytes of video data saved.
  double get megabytesSaved {
    return bandwidthBytesSaved / (1024.0 * 1024.0);
  }

  /// Evaluates discipline rating based on adherence and strict locks.
  String get disciplineRating {
    final rate = adherenceRate;
    if (rate >= 95.0 && strictLocksEnforced >= 10) return 'Dopamine Sovereign';
    if (rate >= 85.0) return 'Deep Work Guardian';
    if (rate >= 70.0) return 'Focused Practitioner';
    if (rate >= 50.0) return 'Emerging Intentionality';
    return 'Rebuilding Baseline';
  }

  /// Combines two metrics objects into an aggregated rollup.
  SessionLifecycleMetrics merge(SessionLifecycleMetrics other) {
    return SessionLifecycleMetrics(
      sessionsInitiated: sessionsInitiated + other.sessionsInitiated,
      sessionsCompleted: sessionsCompleted + other.sessionsCompleted,
      sessionsAborted: sessionsAborted + other.sessionsAborted,
      strictLocksEnforced: strictLocksEnforced + other.strictLocksEnforced,
      breakOvershootsPrevented: breakOvershootsPrevented + other.breakOvershootsPrevented,
      frictionPledgesSubmitted: frictionPledgesSubmitted + other.frictionPledgesSubmitted,
      emergencyRequestsInitiated: emergencyRequestsInitiated + other.emergencyRequestsInitiated,
      emergencyRequestsApproved: emergencyRequestsApproved + other.emergencyRequestsApproved,
      totalFocusMinutes: totalFocusMinutes + other.totalFocusMinutes,
      totalBreakMinutes: totalBreakMinutes + other.totalBreakMinutes,
      totalDistractionInterceptions: totalDistractionInterceptions + other.totalDistractionInterceptions,
      bandwidthBytesSaved: bandwidthBytesSaved + other.bandwidthBytesSaved,
      lastRecordedAt: other.lastRecordedAt.isAfter(lastRecordedAt) ? other.lastRecordedAt : lastRecordedAt,
    );
  }

  /// Creates a copy with optional parameter overrides.
  SessionLifecycleMetrics copyWith({
    int? sessionsInitiated,
    int? sessionsCompleted,
    int? sessionsAborted,
    int? strictLocksEnforced,
    int? breakOvershootsPrevented,
    int? frictionPledgesSubmitted,
    int? emergencyRequestsInitiated,
    int? emergencyRequestsApproved,
    int? totalFocusMinutes,
    int? totalBreakMinutes,
    int? totalDistractionInterceptions,
    int? bandwidthBytesSaved,
    DateTime? lastRecordedAt,
  }) {
    return SessionLifecycleMetrics(
      sessionsInitiated: sessionsInitiated ?? this.sessionsInitiated,
      sessionsCompleted: sessionsCompleted ?? this.sessionsCompleted,
      sessionsAborted: sessionsAborted ?? this.sessionsAborted,
      strictLocksEnforced: strictLocksEnforced ?? this.strictLocksEnforced,
      breakOvershootsPrevented: breakOvershootsPrevented ?? this.breakOvershootsPrevented,
      frictionPledgesSubmitted: frictionPledgesSubmitted ?? this.frictionPledgesSubmitted,
      emergencyRequestsInitiated: emergencyRequestsInitiated ?? this.emergencyRequestsInitiated,
      emergencyRequestsApproved: emergencyRequestsApproved ?? this.emergencyRequestsApproved,
      totalFocusMinutes: totalFocusMinutes ?? this.totalFocusMinutes,
      totalBreakMinutes: totalBreakMinutes ?? this.totalBreakMinutes,
      totalDistractionInterceptions: totalDistractionInterceptions ?? this.totalDistractionInterceptions,
      bandwidthBytesSaved: bandwidthBytesSaved ?? this.bandwidthBytesSaved,
      lastRecordedAt: lastRecordedAt ?? this.lastRecordedAt,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'sessionsInitiated': sessionsInitiated,
      'sessionsCompleted': sessionsCompleted,
      'sessionsAborted': sessionsAborted,
      'strictLocksEnforced': strictLocksEnforced,
      'breakOvershootsPrevented': breakOvershootsPrevented,
      'frictionPledgesSubmitted': frictionPledgesSubmitted,
      'emergencyRequestsInitiated': emergencyRequestsInitiated,
      'emergencyRequestsApproved': emergencyRequestsApproved,
      'totalFocusMinutes': totalFocusMinutes,
      'totalBreakMinutes': totalBreakMinutes,
      'totalDistractionInterceptions': totalDistractionInterceptions,
      'bandwidthBytesSaved': bandwidthBytesSaved,
      'lastRecordedAt': lastRecordedAt.toIso8601String(),
    };
  }

  factory SessionLifecycleMetrics.fromJson(Map<String, dynamic> json) {
    return SessionLifecycleMetrics(
      sessionsInitiated: json['sessionsInitiated'] as int? ?? 0,
      sessionsCompleted: json['sessionsCompleted'] as int? ?? 0,
      sessionsAborted: json['sessionsAborted'] as int? ?? 0,
      strictLocksEnforced: json['strictLocksEnforced'] as int? ?? 0,
      breakOvershootsPrevented: json['breakOvershootsPrevented'] as int? ?? 0,
      frictionPledgesSubmitted: json['frictionPledgesSubmitted'] as int? ?? 0,
      emergencyRequestsInitiated: json['emergencyRequestsInitiated'] as int? ?? 0,
      emergencyRequestsApproved: json['emergencyRequestsApproved'] as int? ?? 0,
      totalFocusMinutes: json['totalFocusMinutes'] as int? ?? 0,
      totalBreakMinutes: json['totalBreakMinutes'] as int? ?? 0,
      totalDistractionInterceptions: json['totalDistractionInterceptions'] as int? ?? 0,
      bandwidthBytesSaved: json['bandwidthBytesSaved'] as int? ?? 0,
      lastRecordedAt: json['lastRecordedAt'] != null
          ? DateTime.tryParse(json['lastRecordedAt'] as String) ?? DateTime.now()
          : DateTime.now(),
    );
  }

  @override
  String toString() {
    return 'SessionLifecycleMetrics(completed: $sessionsCompleted/$sessionsInitiated, '
        'hours: ${totalHoursReclaimed.toStringAsFixed(1)}h, adherence: ${adherenceRate.toStringAsFixed(1)}%)';
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SessionLifecycleMetrics &&
          runtimeType == other.runtimeType &&
          sessionsInitiated == other.sessionsInitiated &&
          sessionsCompleted == other.sessionsCompleted &&
          sessionsAborted == other.sessionsAborted &&
          strictLocksEnforced == other.strictLocksEnforced &&
          breakOvershootsPrevented == other.breakOvershootsPrevented &&
          frictionPledgesSubmitted == other.frictionPledgesSubmitted &&
          emergencyRequestsInitiated == other.emergencyRequestsInitiated &&
          emergencyRequestsApproved == other.emergencyRequestsApproved &&
          totalFocusMinutes == other.totalFocusMinutes &&
          totalBreakMinutes == other.totalBreakMinutes &&
          totalDistractionInterceptions == other.totalDistractionInterceptions &&
          bandwidthBytesSaved == other.bandwidthBytesSaved;

  @override
  int get hashCode => Object.hash(
        sessionsInitiated,
        sessionsCompleted,
        sessionsAborted,
        strictLocksEnforced,
        breakOvershootsPrevented,
        frictionPledgesSubmitted,
        emergencyRequestsInitiated,
        emergencyRequestsApproved,
        totalFocusMinutes,
        totalBreakMinutes,
        totalDistractionInterceptions,
        bandwidthBytesSaved,
      );
}
