import 'package:flutter/foundation.dart';
import '../models/recurring_schedule_rule.dart';

/// Evaluates calendar-based recurring schedule rules and determines active time-window locks.
class PerAppRecurringEngine {
  final Map<String, RecurringScheduleRule> _rules = {};

  List<RecurringScheduleRule> get allRules => _rules.values.toList();
  Map<String, RecurringScheduleRule> get rulesMap => Map.unmodifiable(_rules);

  /// Registers a recurring schedule rule.
  void addRule(RecurringScheduleRule rule) {
    _rules[rule.id] = rule;
  }

  /// Removes a rule by ID.
  void removeRule(String ruleId) {
    _rules.remove(ruleId);
  }

  /// Updates an existing rule.
  void updateRule(RecurringScheduleRule rule) {
    _rules[rule.id] = rule;
  }

  /// Returns all rules registered for a given application ID.
  List<RecurringScheduleRule> getRulesForApp(String appId) {
    return _rules.values.where((r) => r.appId == appId).toList();
  }

  /// Evaluates whether an application is currently within an active scheduled lock window.
  bool isAppScheduledForLock(String appId, DateTime time) {
    final appRules = getRulesForApp(appId);
    for (final rule in appRules) {
      if (rule.isActive && rule.isTimeWithinWindow(time)) {
        return true;
      }
    }
    return false;
  }

  /// Evaluates all rules against current time and returns set of appIds that must be locked.
  Set<String> evaluateActiveAppIds(DateTime time) {
    final activeAppIds = <String>{};
    for (final rule in _rules.values) {
      if (rule.isActive && rule.isTimeWithinWindow(time)) {
        activeAppIds.add(rule.appId);
      }
    }
    return activeAppIds;
  }

  /// Computes the exact timestamp of the nearest upcoming boundary transition (start or end of any rule).
  DateTime? getNextTransitionTime(DateTime now) {
    if (_rules.isEmpty) return null;

    DateTime? nearest;
    final currentMinute = now.hour * 60 + now.minute;

    for (final rule in _rules.values) {
      if (!rule.isActive) continue;

      for (int dayOffset = 0; dayOffset <= 7; dayOffset++) {
        final targetDate = now.add(Duration(days: dayOffset));
        final targetWeekday = targetDate.weekday;

        if (rule.daysOfWeek.contains(targetWeekday)) {
          // Check start minute
          final startCandidate = DateTime(
            targetDate.year,
            targetDate.month,
            targetDate.day,
            rule.startMinuteOfDay ~/ 60,
            rule.startMinuteOfDay % 60,
          );
          if (startCandidate.isAfter(now)) {
            if (nearest == null || startCandidate.isBefore(nearest)) {
              nearest = startCandidate;
            }
          }

          // Check end minute
          final endCandidate = DateTime(
            targetDate.year,
            targetDate.month,
            targetDate.day,
            rule.endMinuteOfDay ~/ 60,
            rule.endMinuteOfDay % 60,
          );
          if (endCandidate.isAfter(now)) {
            if (nearest == null || endCandidate.isBefore(nearest)) {
              nearest = endCandidate;
            }
          }
        }
      }
    }
    return nearest;
  }
}
