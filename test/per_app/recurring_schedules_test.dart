import 'package:flutter_test/flutter_test.dart';
import 'package:focus_dns/engine/per_app/core/per_app_recurring_engine.dart';
import 'package:focus_dns/engine/per_app/models/recurring_schedule_rule.dart';

void main() {
  group('RecurringSchedules & Engine Tests', () {
    test('1. Standard daytime schedule window evaluates correctly across weekdays', () {
      const rule = RecurringScheduleRule(
        id: 'workday',
        appId: 'instagram',
        packageName: 'com.instagram.android',
        label: 'Workday Focus',
        daysOfWeek: [1, 2, 3, 4, 5], // Mon to Fri
        startMinuteOfDay: 540, // 09:00 AM
        endMinuteOfDay: 1020, // 05:00 PM
      );

      // Tuesday (weekday 2) at 10:30 AM (630 min) -> in window
      final tuesdayWork = DateTime(2026, 11, 10, 10, 30);
      expect(tuesdayWork.weekday, equals(2));
      expect(rule.isTimeWithinWindow(tuesdayWork), isTrue);

      // Tuesday at 08:30 AM (510 min) -> before window
      final tuesdayEarly = DateTime(2026, 11, 10, 8, 30);
      expect(rule.isTimeWithinWindow(tuesdayEarly), isFalse);

      // Tuesday at 05:30 PM (1050 min) -> after window
      final tuesdayLate = DateTime(2026, 11, 10, 17, 30);
      expect(rule.isTimeWithinWindow(tuesdayLate), isFalse);

      // Sunday (weekday 7) at 10:30 AM -> weekend day not in daysOfWeek
      final sundayWork = DateTime(2026, 11, 8, 10, 30);
      expect(sundayWork.weekday, equals(7));
      expect(rule.isTimeWithinWindow(sundayWork), isFalse);
    });

    test('2. Cross-midnight schedule evaluates late night and rollover morning', () {
      const nightRule = RecurringScheduleRule(
        id: 'night_fast',
        appId: 'tiktok',
        packageName: 'com.zhiliaoapp.musically',
        label: 'Night Digital Fast',
        daysOfWeek: [5], // Friday night only
        startMinuteOfDay: 1320, // 10:00 PM (22:00)
        endMinuteOfDay: 360, // 06:00 AM
      );

      // Friday (weekday 5) at 11:15 PM -> in window
      final fridayNight = DateTime(2026, 11, 13, 23, 15);
      expect(fridayNight.weekday, equals(5));
      expect(nightRule.isTimeWithinWindow(fridayNight), isTrue);

      // Saturday (weekday 6) at 03:30 AM -> rollover from Friday -> in window
      final saturdayEarly = DateTime(2026, 11, 14, 3, 30);
      expect(saturdayEarly.weekday, equals(6));
      expect(nightRule.isTimeWithinWindow(saturdayEarly), isTrue);

      // Saturday at 08:00 AM -> past end minute -> out of window
      final saturdayMorning = DateTime(2026, 11, 14, 8, 0);
      expect(nightRule.isTimeWithinWindow(saturdayMorning), isFalse);
    });

    test('3. PerAppRecurringEngine aggregates active rules and computes next transition', () {
      final engine = PerAppRecurringEngine();

      const rule1 = RecurringScheduleRule(
        id: 'r1',
        appId: 'youtube',
        packageName: 'com.google.android.youtube',
        label: 'Focus 1',
        daysOfWeek: [1, 2, 3, 4, 5],
        startMinuteOfDay: 600, // 10:00 AM
        endMinuteOfDay: 720, // 12:00 PM
      );
      engine.addRule(rule1);

      // Check at 10:30 AM on Monday (weekday 1)
      final mondayMid = DateTime(2026, 11, 9, 10, 30);
      expect(engine.isAppScheduledForLock('youtube', mondayMid), isTrue);

      final active = engine.evaluateActiveAppIds(mondayMid);
      expect(active, contains('youtube'));

      // Check next transition from 09:30 AM -> should be 10:00 AM start
      final mondayEarly = DateTime(2026, 11, 9, 9, 30);
      final nextTransition = engine.getNextTransitionTime(mondayEarly);
      expect(nextTransition, isNotNull);
      expect(nextTransition?.hour, equals(10));
      expect(nextTransition?.minute, equals(0));
    });
  });
}
