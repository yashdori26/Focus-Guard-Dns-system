import 'package:flutter/foundation.dart';

/// Represents a discrete foreground usage interval for an application.
@immutable
class AppSessionInterval {
  final DateTime startTime;
  final DateTime endTime;
  final int durationSeconds;

  const AppSessionInterval({
    required this.startTime,
    required this.endTime,
    required this.durationSeconds,
  });

  Map<String, dynamic> toJson() => {
    'startTime': startTime.toIso8601String(),
    'endTime': endTime.toIso8601String(),
    'durationSeconds': durationSeconds,
  };

  factory AppSessionInterval.fromJson(Map<String, dynamic> json) {
    return AppSessionInterval(
      startTime: DateTime.parse(json['startTime'] as String),
      endTime: DateTime.parse(json['endTime'] as String),
      durationSeconds: (json['durationSeconds'] as num).toInt(),
    );
  }
}

/// Comprehensive daily telemetry record tracking usage metrics, launches, and blocked attempts.
@immutable
class AppDailyUsageRecord {
  final String appId;
  final String packageName;
  final String dateKey; // Format: YYYY-MM-DD
  final int totalForegroundSeconds;
  final int totalLaunches;
  final int totalBlockedInterventions;
  final int estimatedDopamineScore;
  final List<int> hourlyUsageSeconds; // 24 slots (0..23)
  final List<AppSessionInterval> sessions;

  const AppDailyUsageRecord({
    required this.appId,
    required this.packageName,
    required this.dateKey,
    this.totalForegroundSeconds = 0,
    this.totalLaunches = 0,
    this.totalBlockedInterventions = 0,
    this.estimatedDopamineScore = 50,
    this.hourlyUsageSeconds = const [
      0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
      0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
    ],
    this.sessions = const [],
  });

  int get totalMinutes => (totalForegroundSeconds / 60).round();

  AppDailyUsageRecord copyWith({
    String? appId,
    String? packageName,
    String? dateKey,
    int? totalForegroundSeconds,
    int? totalLaunches,
    int? totalBlockedInterventions,
    int? estimatedDopamineScore,
    List<int>? hourlyUsageSeconds,
    List<AppSessionInterval>? sessions,
  }) {
    return AppDailyUsageRecord(
      appId: appId ?? this.appId,
      packageName: packageName ?? this.packageName,
      dateKey: dateKey ?? this.dateKey,
      totalForegroundSeconds: totalForegroundSeconds ?? this.totalForegroundSeconds,
      totalLaunches: totalLaunches ?? this.totalLaunches,
      totalBlockedInterventions: totalBlockedInterventions ?? this.totalBlockedInterventions,
      estimatedDopamineScore: estimatedDopamineScore ?? this.estimatedDopamineScore,
      hourlyUsageSeconds: hourlyUsageSeconds ?? this.hourlyUsageSeconds,
      sessions: sessions ?? this.sessions,
    );
  }

  /// Appends foreground usage duration to the appropriate hour and records the session.
  AppDailyUsageRecord addUsage({
    required int durationSec,
    required DateTime timestamp,
  }) {
    final hour = timestamp.hour.clamp(0, 23);
    final updatedHourly = List<int>.from(hourlyUsageSeconds);
    updatedHourly[hour] += durationSec;

    final newSession = AppSessionInterval(
      startTime: timestamp.subtract(Duration(seconds: durationSec)),
      endTime: timestamp,
      durationSeconds: durationSec,
    );

    return copyWith(
      totalForegroundSeconds: totalForegroundSeconds + durationSec,
      hourlyUsageSeconds: updatedHourly,
      sessions: [...sessions, newSession],
    );
  }

  /// Increments launch count.
  AppDailyUsageRecord incrementLaunches() {
    return copyWith(totalLaunches: totalLaunches + 1);
  }

  /// Increments blocked intervention count.
  AppDailyUsageRecord incrementBlocked() {
    return copyWith(totalBlockedInterventions: totalBlockedInterventions + 1);
  }

  Map<String, dynamic> toJson() => {
    'appId': appId,
    'packageName': packageName,
    'dateKey': dateKey,
    'totalForegroundSeconds': totalForegroundSeconds,
    'totalLaunches': totalLaunches,
    'totalBlockedInterventions': totalBlockedInterventions,
    'estimatedDopamineScore': estimatedDopamineScore,
    'hourlyUsageSeconds': hourlyUsageSeconds,
    'sessions': sessions.map((s) => s.toJson()).toList(),
  };

  factory AppDailyUsageRecord.fromJson(Map<String, dynamic> json) {
    return AppDailyUsageRecord(
      appId: json['appId'] as String,
      packageName: json['packageName'] as String,
      dateKey: json['dateKey'] as String,
      totalForegroundSeconds: (json['totalForegroundSeconds'] as num?)?.toInt() ?? 0,
      totalLaunches: (json['totalLaunches'] as num?)?.toInt() ?? 0,
      totalBlockedInterventions: (json['totalBlockedInterventions'] as num?)?.toInt() ?? 0,
      estimatedDopamineScore: (json['estimatedDopamineScore'] as num?)?.toInt() ?? 50,
      hourlyUsageSeconds: (json['hourlyUsageSeconds'] as List<dynamic>?)
              ?.map((e) => (e as num).toInt())
              .toList() ??
          List.filled(24, 0),
      sessions: (json['sessions'] as List<dynamic>?)
              ?.map((e) => AppSessionInterval.fromJson(e as Map<String, dynamic>))
              .toList() ??
          const [],
    );
  }
}
