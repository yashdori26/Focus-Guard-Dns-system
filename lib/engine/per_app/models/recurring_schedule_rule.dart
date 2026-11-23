import 'package:flutter/foundation.dart';
import 'app_lock_config.dart';

/// Defines a recurring time window during which an application is strictly locked.
@immutable
class RecurringScheduleRule {
  final String id;
  final String appId;
  final String packageName;
  final String label;
  final List<int> daysOfWeek; // 1 = Monday, 7 = Sunday (DateTime.weekday standard)
  final int startMinuteOfDay; // 0 to 1439 (e.g. 540 = 09:00 AM)
  final int endMinuteOfDay; // 0 to 1439 (e.g. 1020 = 05:00 PM)
  final bool isActive;
  final StrictnessTier strictness;

  const RecurringScheduleRule({
    required this.id,
    required this.appId,
    required this.packageName,
    required this.label,
    required this.daysOfWeek,
    required this.startMinuteOfDay,
    required this.endMinuteOfDay,
    this.isActive = true,
    this.strictness = StrictnessTier.strictUnbreakable,
  });

  /// Formatted time strings for display.
  String get startTimeFormatted => _formatMinute(startMinuteOfDay);
  String get endTimeFormatted => _formatMinute(endMinuteOfDay);

  static String _formatMinute(int totalMinutes) {
    final hour = (totalMinutes ~/ 60).clamp(0, 23);
    final minute = (totalMinutes % 60).clamp(0, 59);
    final hStr = hour.toString().padLeft(2, '0');
    final mStr = minute.toString().padLeft(2, '0');
    return '$hStr:$mStr';
  }

  /// Whether a specific timestamp falls inside this schedule's active focus window.
  bool isTimeWithinWindow(DateTime time) {
    if (!isActive) return false;

    // Check if the weekday matches
    if (!daysOfWeek.contains(time.weekday)) {
      // Check cross-midnight rollover from previous day
      if (startMinuteOfDay > endMinuteOfDay) {
        final prevWeekday = time.weekday == 1 ? 7 : time.weekday - 1;
        if (daysOfWeek.contains(prevWeekday)) {
          final currentMinute = time.hour * 60 + time.minute;
          if (currentMinute < endMinuteOfDay) return true;
        }
      }
      return false;
    }

    final currentMinute = time.hour * 60 + time.minute;

    if (startMinuteOfDay <= endMinuteOfDay) {
      // Standard daytime window: e.g. 09:00 (540) to 17:00 (1020)
      return currentMinute >= startMinuteOfDay && currentMinute < endMinuteOfDay;
    } else {
      // Cross-midnight window: e.g. 22:00 (1320) to 06:00 (360)
      return currentMinute >= startMinuteOfDay || currentMinute < endMinuteOfDay;
    }
  }

  RecurringScheduleRule copyWith({
    String? id,
    String? appId,
    String? packageName,
    String? label,
    List<int>? daysOfWeek,
    int? startMinuteOfDay,
    int? endMinuteOfDay,
    bool? isActive,
    StrictnessTier? strictness,
  }) {
    return RecurringScheduleRule(
      id: id ?? this.id,
      appId: appId ?? this.appId,
      packageName: packageName ?? this.packageName,
      label: label ?? this.label,
      daysOfWeek: daysOfWeek ?? this.daysOfWeek,
      startMinuteOfDay: (startMinuteOfDay ?? this.startMinuteOfDay).clamp(0, 1439),
      endMinuteOfDay: (endMinuteOfDay ?? this.endMinuteOfDay).clamp(0, 1439),
      isActive: isActive ?? this.isActive,
      strictness: strictness ?? this.strictness,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'appId': appId,
    'packageName': packageName,
    'label': label,
    'daysOfWeek': daysOfWeek,
    'startMinuteOfDay': startMinuteOfDay,
    'endMinuteOfDay': endMinuteOfDay,
    'isActive': isActive,
    'strictness': strictness.name,
  };

  factory RecurringScheduleRule.fromJson(Map<String, dynamic> json) {
    return RecurringScheduleRule(
      id: json['id'] as String,
      appId: json['appId'] as String,
      packageName: json['packageName'] as String,
      label: json['label'] as String? ?? 'Focus Window',
      daysOfWeek: (json['daysOfWeek'] as List<dynamic>?)?.map((e) => (e as num).toInt()).toList() ?? [1, 2, 3, 4, 5],
      startMinuteOfDay: (json['startMinuteOfDay'] as num?)?.toInt() ?? 540,
      endMinuteOfDay: (json['endMinuteOfDay'] as num?)?.toInt() ?? 1020,
      isActive: json['isActive'] as bool? ?? true,
      strictness: StrictnessTier.values.byName(json['strictness'] as String? ?? 'strictUnbreakable'),
    );
  }
}
