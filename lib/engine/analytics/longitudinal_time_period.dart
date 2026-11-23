import 'package:flutter/foundation.dart';

/// Supported longitudinal time horizons for historical analysis and trend projection.
enum LongitudinalTimePeriod {
  day,
  week,
  month,
  quarter,
  year,
  allTime,
}

/// Date range boundaries for a specific time period.
@immutable
class DateRange {
  final DateTime start;
  final DateTime end;

  const DateRange({required this.start, required this.end});

  Duration get duration => end.difference(start);

  bool contains(DateTime date) {
    return date.isAfter(start) && date.isBefore(end) ||
        date.isAtSameMomentAs(start) ||
        date.isAtSameMomentAs(end);
  }

  @override
  String toString() => 'DateRange(${start.toIso8601String()} - ${end.toIso8601String()})';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DateRange &&
          runtimeType == other.runtimeType &&
          start == other.start &&
          end == other.end;

  @override
  int get hashCode => start.hashCode ^ end.hashCode;
}

/// Helper utilities and interval calculators for longitudinal periods.
class LongitudinalPeriodHelper {
  const LongitudinalPeriodHelper._();

  /// Human-readable label for the period.
  static String getTitle(LongitudinalTimePeriod period) {
    switch (period) {
      case LongitudinalTimePeriod.day:
        return 'Today';
      case LongitudinalTimePeriod.week:
        return 'This Week';
      case LongitudinalTimePeriod.month:
        return 'This Month';
      case LongitudinalTimePeriod.quarter:
        return 'This Quarter';
      case LongitudinalTimePeriod.year:
        return 'Past 365 Days';
      case LongitudinalTimePeriod.allTime:
        return 'Lifetime All-Time';
    }
  }

  /// Shorter tab label.
  static String getTabLabel(LongitudinalTimePeriod period) {
    switch (period) {
      case LongitudinalTimePeriod.day:
        return 'Day';
      case LongitudinalTimePeriod.week:
        return 'Week';
      case LongitudinalTimePeriod.month:
        return 'Month';
      case LongitudinalTimePeriod.quarter:
        return 'Quarter';
      case LongitudinalTimePeriod.year:
        return 'Year';
      case LongitudinalTimePeriod.allTime:
        return 'All-Time';
    }
  }

  /// Calculates the exact start and end [DateRange] for a given [period] relative to [referenceDate].
  static DateRange calculateRange(LongitudinalTimePeriod period, [DateTime? referenceDate]) {
    final ref = referenceDate ?? DateTime.now();

    switch (period) {
      case LongitudinalTimePeriod.day:
        final start = DateTime(ref.year, ref.month, ref.day, 0, 0, 0);
        final end = DateTime(ref.year, ref.month, ref.day, 23, 59, 59, 999);
        return DateRange(start: start, end: end);

      case LongitudinalTimePeriod.week:
        // Start from Monday
        final weekdayOffset = ref.weekday - DateTime.monday;
        final start = DateTime(ref.year, ref.month, ref.day - weekdayOffset, 0, 0, 0);
        final end = start.add(const Duration(days: 6, hours: 23, minutes: 59, seconds: 59));
        return DateRange(start: start, end: end);

      case LongitudinalTimePeriod.month:
        final start = DateTime(ref.year, ref.month, 1, 0, 0, 0);
        final nextMonth = ref.month == 12 ? DateTime(ref.year + 1, 1, 1) : DateTime(ref.year, ref.month + 1, 1);
        final end = nextMonth.subtract(const Duration(milliseconds: 1));
        return DateRange(start: start, end: end);

      case LongitudinalTimePeriod.quarter:
        final quarter = ((ref.month - 1) ~/ 3) + 1;
        final startMonth = (quarter - 1) * 3 + 1;
        final start = DateTime(ref.year, startMonth, 1, 0, 0, 0);
        final endMonth = startMonth + 3;
        final nextQuarter = endMonth > 12 ? DateTime(ref.year + 1, endMonth - 12, 1) : DateTime(ref.year, endMonth, 1);
        final end = nextQuarter.subtract(const Duration(milliseconds: 1));
        return DateRange(start: start, end: end);

      case LongitudinalTimePeriod.year:
        final start = DateTime(ref.year, 1, 1, 0, 0, 0);
        final end = DateTime(ref.year, 12, 31, 23, 59, 59, 999);
        return DateRange(start: start, end: end);

      case LongitudinalTimePeriod.allTime:
        final start = DateTime(2024, 1, 1, 0, 0, 0);
        final end = DateTime(ref.year + 5, 12, 31, 23, 59, 59);
        return DateRange(start: start, end: end);
    }
  }

  /// Returns the granularity bucket duration for charts.
  static Duration getBucketDuration(LongitudinalTimePeriod period) {
    switch (period) {
      case LongitudinalTimePeriod.day:
        return const Duration(hours: 1);
      case LongitudinalTimePeriod.week:
      case LongitudinalTimePeriod.month:
        return const Duration(days: 1);
      case LongitudinalTimePeriod.quarter:
      case LongitudinalTimePeriod.year:
        return const Duration(days: 7);
      case LongitudinalTimePeriod.allTime:
        return const Duration(days: 30);
    }
  }

  /// Returns the number of discrete buckets for visualization in this period.
  static int getBucketCount(LongitudinalTimePeriod period) {
    switch (period) {
      case LongitudinalTimePeriod.day:
        return 24; // 24 hours
      case LongitudinalTimePeriod.week:
        return 7; // 7 days
      case LongitudinalTimePeriod.month:
        return 31; // max 31 days
      case LongitudinalTimePeriod.quarter:
        return 12; // 12 weeks
      case LongitudinalTimePeriod.year:
        return 52; // 52 weeks
      case LongitudinalTimePeriod.allTime:
        return 36; // 36 months
    }
  }

  /// Multiplier scaling daily baseline metrics to this period.
  static double getScaleMultiplier(LongitudinalTimePeriod period) {
    switch (period) {
      case LongitudinalTimePeriod.day:
        return 1.0;
      case LongitudinalTimePeriod.week:
        return 7.0;
      case LongitudinalTimePeriod.month:
        return 30.0;
      case LongitudinalTimePeriod.quarter:
        return 90.0;
      case LongitudinalTimePeriod.year:
        return 365.0;
      case LongitudinalTimePeriod.allTime:
        return 730.0;
    }
  }
}
