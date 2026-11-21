import 'package:flutter_test/flutter_test.dart';
import 'package:focus_dns/engine/analytics/longitudinal_time_period.dart';

void main() {
  group('Longitudinal Time Period Tests', () {
    final fixedDate = DateTime(2026, 11, 8, 14, 30, 0);

    test('1. Day period bounds span midnight to midnight', () {
      final range = LongitudinalPeriodHelper.calculateRange(LongitudinalTimePeriod.day, fixedDate);
      expect(range.start.year, equals(2026));
      expect(range.start.month, equals(11));
      expect(range.start.day, equals(8));
      expect(range.start.hour, equals(0));
      expect(range.start.minute, equals(0));
      expect(range.end.hour, equals(23));
      expect(range.end.minute, equals(59));
      expect(range.contains(fixedDate), isTrue);
    });

    test('2. Week period bounds span Monday 00:00 to Sunday 23:59', () {
      final range = LongitudinalPeriodHelper.calculateRange(LongitudinalTimePeriod.week, fixedDate);
      // 2026-11-08 is a Sunday. Monday was 2026-11-02.
      expect(range.start.weekday, equals(DateTime.monday));
      expect(range.contains(fixedDate), isTrue);
      expect(range.contains(DateTime(2026, 11, 2)), isTrue);
      expect(range.contains(DateTime(2026, 11, 1)), isFalse);
    });

    test('3. Month period bounds span 1st of month to end of month', () {
      final range = LongitudinalPeriodHelper.calculateRange(LongitudinalTimePeriod.month, fixedDate);
      expect(range.start.day, equals(1));
      expect(range.start.month, equals(11));
      expect(range.contains(fixedDate), isTrue);
      expect(range.contains(DateTime(2026, 10, 31)), isFalse);
    });

    test('4. Quarter period resolves Q4 correctly for November', () {
      final range = LongitudinalPeriodHelper.calculateRange(LongitudinalTimePeriod.quarter, fixedDate);
      expect(range.start.month, equals(10)); // October
      expect(range.start.day, equals(1));
      expect(range.contains(fixedDate), isTrue);
    });

    test('5. Year period covers Jan 1 to Dec 31', () {
      final range = LongitudinalPeriodHelper.calculateRange(LongitudinalTimePeriod.year, fixedDate);
      expect(range.start.month, equals(1));
      expect(range.start.day, equals(1));
      expect(range.end.month, equals(12));
      expect(range.end.day, equals(31));
      expect(range.contains(fixedDate), isTrue);
    });

    test('6. Bucket counts and granularity match visualization requirements', () {
      expect(LongitudinalPeriodHelper.getBucketCount(LongitudinalTimePeriod.day), equals(24));
      expect(LongitudinalPeriodHelper.getBucketCount(LongitudinalTimePeriod.week), equals(7));
      expect(LongitudinalPeriodHelper.getBucketCount(LongitudinalTimePeriod.month), equals(31));
      expect(LongitudinalPeriodHelper.getBucketCount(LongitudinalTimePeriod.quarter), equals(12));
      expect(LongitudinalPeriodHelper.getBucketCount(LongitudinalTimePeriod.year), equals(52));
    });

    test('7. Period labels and titles render correctly', () {
      expect(LongitudinalPeriodHelper.getTitle(LongitudinalTimePeriod.day), equals('Today'));
      expect(LongitudinalPeriodHelper.getTitle(LongitudinalTimePeriod.week), equals('This Week'));
      expect(LongitudinalPeriodHelper.getTitle(LongitudinalTimePeriod.year), equals('Past 365 Days'));
      expect(LongitudinalPeriodHelper.getTabLabel(LongitudinalTimePeriod.allTime), equals('All-Time'));
    });

    test('8. DateRange equality and hashCode work as expected', () {
      final r1 = DateRange(start: DateTime(2026, 1, 1), end: DateTime(2026, 1, 2));
      final r2 = DateRange(start: DateTime(2026, 1, 1), end: DateTime(2026, 1, 2));
      final r3 = DateRange(start: DateTime(2026, 1, 1), end: DateTime(2026, 1, 3));

      expect(r1, equals(r2));
      expect(r1.hashCode, equals(r2.hashCode));
      expect(r1 == r3, isFalse);
    });
  });
}
