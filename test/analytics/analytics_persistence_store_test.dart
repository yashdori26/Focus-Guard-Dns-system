import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:focus_dns/engine/analytics/longitudinal_time_period.dart';
import 'package:focus_dns/engine/analytics/session_lifecycle_metrics.dart';
import 'package:focus_dns/engine/analytics/streak_momentum_calculator.dart';
import 'package:focus_dns/engine/analytics/attention_heatmap_matrix.dart';
import 'package:focus_dns/engine/analytics/analytics_persistence_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Analytics Persistence Store Tests', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('1. Record daily rollup stores and merges correctly', () async {
      final store = await AnalyticsPersistenceStore.create();
      final day = DateTime(2026, 11, 8);

      final m1 = SessionLifecycleMetrics(
        sessionsInitiated: 4,
        sessionsCompleted: 4,
        sessionsAborted: 0,
        strictLocksEnforced: 2,
        breakOvershootsPrevented: 1,
        frictionPledgesSubmitted: 0,
        emergencyRequestsInitiated: 0,
        emergencyRequestsApproved: 0,
        totalFocusMinutes: 100,
        totalBreakMinutes: 20,
        totalDistractionInterceptions: 25,
        bandwidthBytesSaved: 1024 * 1024 * 10,
        lastRecordedAt: day,
      );

      await store.recordDailyMetrics(day, m1);

      final all = store.getAllRollups();
      expect(all.containsKey('2026-11-08'), isTrue);
      expect(all['2026-11-08']?.totalFocusMinutes, equals(100));

      // Second session on same day merges
      final m2 = m1.copyWith(totalFocusMinutes: 50, sessionsCompleted: 2, sessionsInitiated: 2);
      await store.recordDailyMetrics(day, m2);

      final updated = store.getAllRollups()['2026-11-08']!;
      expect(updated.totalFocusMinutes, equals(150));
      expect(updated.sessionsCompleted, equals(6));
    });

    test('2. Aggregation for LongitudinalTimePeriod filters by date range', () async {
      final store = await AnalyticsPersistenceStore.create();

      // November 1 (Sunday)
      await store.recordDailyMetrics(
        DateTime(2026, 11, 1),
        SessionLifecycleMetrics.empty().copyWith(totalFocusMinutes: 60, sessionsCompleted: 2),
      );
      // November 8 (Sunday - 1 week later)
      await store.recordDailyMetrics(
        DateTime(2026, 11, 8),
        SessionLifecycleMetrics.empty().copyWith(totalFocusMinutes: 120, sessionsCompleted: 4),
      );

      // Query for Day (Nov 8)
      final dayMetrics = store.getMetricsForPeriod(LongitudinalTimePeriod.day, DateTime(2026, 11, 8));
      expect(dayMetrics.totalFocusMinutes, equals(120));

      // Query for Month (Nov 2026)
      final monthMetrics = store.getMetricsForPeriod(LongitudinalTimePeriod.month, DateTime(2026, 11, 8));
      expect(monthMetrics.totalFocusMinutes, equals(180));
    });

    test('3. Streak record and Heatmap matrix persistence', () async {
      final store = await AnalyticsPersistenceStore.create();

      final streak = StreakRecord(
        currentStreakDays: 12,
        longestStreakDays: 15,
        freezeTokensRemaining: 1,
        dailyAdherenceScores: {'2026-11-08': 100.0},
      );
      await store.saveStreakRecord(streak);
      expect(store.streakRecord.currentStreakDays, equals(12));

      final matrix = AttentionHeatmapMatrix.empty();
      matrix.recordInterception(DateTime(2026, 11, 8, 21, 0), 7);
      await store.saveHeatmapMatrix(matrix);
      expect(store.heatmapMatrix.getCell(DateTime.sunday, 21).interceptionCount, equals(7));
    });

    test('4. Export CSV produces formatted table', () async {
      final store = await AnalyticsPersistenceStore.create();
      await store.recordDailyMetrics(
        DateTime(2026, 11, 8),
        SessionLifecycleMetrics.empty().copyWith(
          sessionsInitiated: 5,
          sessionsCompleted: 5,
          totalFocusMinutes: 125,
          totalDistractionInterceptions: 30,
        ),
      );

      final csv = store.exportCsv();
      expect(csv.contains('Date,Initiated,Completed'), isTrue);
      expect(csv.contains('2026-11-08,5,5,0,125,0,30'), isTrue);
    });

    test('5. Export Markdown report generates complete executive summary', () async {
      final store = await AnalyticsPersistenceStore.create();
      await store.recordDailyMetrics(
        DateTime(2026, 11, 8),
        SessionLifecycleMetrics.empty().copyWith(
          sessionsInitiated: 8,
          sessionsCompleted: 7,
          totalFocusMinutes: 210,
          totalDistractionInterceptions: 44,
        ),
      );

      final md = store.exportMarkdownReport(LongitudinalTimePeriod.week);
      expect(md.contains('# FocusDNS Focus & Dopamine Audit Report'), isTrue);
      expect(md.contains('Total Reclaimed Hours'), isTrue);
      expect(md.contains('Books Read Equivalent'), isTrue);
      expect(md.contains('Tangible Real-World Equivalents'), isTrue);
    });
  });
}
