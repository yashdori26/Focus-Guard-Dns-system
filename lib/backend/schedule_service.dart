import 'dart:async';
import 'package:flutter/services.dart';

/**
 * FocusScheduleIntervalModel
 * ==========================
 * Model representing a recurring focus window on the calendar.
 */
class FocusScheduleIntervalModel {
  final String intervalId;
  final String title;
  final int startHour;
  final int startMinute;
  final int endHour;
  final int endMinute;
  final List<int> daysOfWeek; // 1=Mon, 7=Sun
  final bool enforceLock;

  const FocusScheduleIntervalModel({
    required this.intervalId,
    required this.title,
    required this.startHour,
    required this.startMinute,
    required this.endHour,
    required this.endMinute,
    this.daysOfWeek = const [1, 2, 3, 4, 5],
    this.enforceLock = true,
  });

  String get startTimeFormatted =>
      '${startHour.toString().padLeft(2, '0')}:${startMinute.toString().padLeft(2, '0')}';
  String get endTimeFormatted =>
      '${endHour.toString().padLeft(2, '0')}:${endMinute.toString().padLeft(2, '0')}';

  factory FocusScheduleIntervalModel.fromMap(Map<dynamic, dynamic> map) {
    final rawDays = map['daysOfWeek'] as List<dynamic>? ?? [1, 2, 3, 4, 5];
    return FocusScheduleIntervalModel(
      intervalId: map['intervalId']?.toString() ?? '',
      title: map['title']?.toString() ?? '',
      startHour: (map['startHour'] as num?)?.toInt() ?? 9,
      startMinute: (map['startMinute'] as num?)?.toInt() ?? 0,
      endHour: (map['endHour'] as num?)?.toInt() ?? 17,
      endMinute: (map['endMinute'] as num?)?.toInt() ?? 0,
      daysOfWeek: rawDays.map((e) => (e as num).toInt()).toList(),
      enforceLock: map['enforceLock'] != false,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'intervalId': intervalId,
      'title': title,
      'startHour': startHour,
      'startMinute': startMinute,
      'endHour': endHour,
      'endMinute': endMinute,
      'daysOfWeek': daysOfWeek,
      'enforceLock': enforceLock,
    };
  }
}

/**
 * ScheduleStatusModel
 * ===================
 * Current live schedule evaluation status.
 */
class ScheduleStatusModel {
  final bool inFocusWindow;
  final String activeWindowTitle;
  final bool canUninstallApp;
  final bool emergencyExemptionActive;
  final int dayOfWeek;
  final int currentMinutes;

  const ScheduleStatusModel({
    this.inFocusWindow = false,
    this.activeWindowTitle = 'None (Outside Schedule)',
    this.canUninstallApp = true,
    this.emergencyExemptionActive = true,
    this.dayOfWeek = 1,
    this.currentMinutes = 540,
  });

  factory ScheduleStatusModel.fromMap(Map<dynamic, dynamic> map) {
    return ScheduleStatusModel(
      inFocusWindow: map['inFocusWindow'] == true,
      activeWindowTitle: map['activeWindowTitle']?.toString() ?? 'None (Outside Schedule)',
      canUninstallApp: map['canUninstallApp'] != false,
      emergencyExemptionActive: map['emergencyExemptionActive'] != false,
      dayOfWeek: (map['dayOfWeek'] as num?)?.toInt() ?? 1,
      currentMinutes: (map['currentMinutes'] as num?)?.toInt() ?? 540,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'inFocusWindow': inFocusWindow,
      'activeWindowTitle': activeWindowTitle,
      'canUninstallApp': canUninstallApp,
      'emergencyExemptionActive': emergencyExemptionActive,
      'dayOfWeek': dayOfWeek,
      'currentMinutes': currentMinutes,
    };
  }
}

/**
 * FocusScheduleService
 * ====================
 * Client interface for recurring enterprise calendar focus schedule management.
 */
class FocusScheduleService {
  static const MethodChannel _channel = MethodChannel('focus_dns/schedule');

  static ScheduleStatusModel _simulatedStatus = const ScheduleStatusModel(
    inFocusWindow: false,
    activeWindowTitle: 'None (Outside Schedule)',
    canUninstallApp: true,
    emergencyExemptionActive: true,
    dayOfWeek: 1,
    currentMinutes: 600,
  );

  static final List<FocusScheduleIntervalModel> _simulatedIntervals = [
    const FocusScheduleIntervalModel(
      intervalId: 'interval_default_work',
      title: 'Enterprise Business Focus Hours',
      startHour: 9,
      startMinute: 0,
      endHour: 17,
      endMinute: 0,
      daysOfWeek: [1, 2, 3, 4, 5],
      enforceLock: true,
    ),
    const FocusScheduleIntervalModel(
      intervalId: 'interval_evening_study',
      title: 'Evening Deep Study Window',
      startHour: 19,
      startMinute: 0,
      endHour: 21,
      endMinute: 30,
      daysOfWeek: [1, 2, 3, 4],
      enforceLock: true,
    ),
  ];

  static void setSimulatedStatus(ScheduleStatusModel status) {
    _simulatedStatus = status;
  }

  /// Evaluates current schedule against device clock.
  static Future<ScheduleStatusModel> evaluateSchedule({int? dayOfWeek, int? hour, int? minute}) async {
    try {
      final res = await _channel.invokeMethod<Map<dynamic, dynamic>>(
        'evaluateSchedule',
        {
          if (dayOfWeek != null) 'dayOfWeek': dayOfWeek,
          if (hour != null) 'hour': hour,
          if (minute != null) 'minute': minute,
        },
      );
      if (res != null) {
        return ScheduleStatusModel.fromMap(res);
      }
    } catch (_) {}

    if (hour != null && minute != null) {
      final curMin = hour * 60 + minute;
      bool inside = false;
      String activeTitle = 'None (Outside Schedule)';
      for (final interval in _simulatedIntervals) {
        final startMin = interval.startHour * 60 + interval.startMinute;
        final endMin = interval.endHour * 60 + interval.endMinute;
        if (curMin >= startMin && curMin < endMin) {
          inside = true;
          activeTitle = interval.title;
          break;
        }
      }
      _simulatedStatus = ScheduleStatusModel(
        inFocusWindow: inside,
        activeWindowTitle: activeTitle,
        canUninstallApp: !inside,
        emergencyExemptionActive: true,
        dayOfWeek: dayOfWeek ?? 1,
        currentMinutes: curMin,
      );
    }

    return _simulatedStatus;
  }

  /// Fetches registered recurring schedule intervals.
  static Future<List<FocusScheduleIntervalModel>> getScheduleIntervals() async {
    try {
      final res = await _channel.invokeMethod<List<dynamic>>('getIntervals');
      if (res != null) {
        return res.map((e) => FocusScheduleIntervalModel.fromMap(e as Map)).toList();
      }
    } catch (_) {}
    return _simulatedIntervals;
  }

  /// Triggers standard emergency call 112 (always exempt).
  static Future<bool> triggerEmergencyCall() async {
    try {
      final res = await _channel.invokeMethod<bool>('triggerEmergencyCall');
      if (res != null) return res;
    } catch (_) {}
    return true;
  }
}
