import 'package:flutter/foundation.dart';
import 'longitudinal_database.dart';

/// Aggregated habit wellness metrics for a given timeframe.
@immutable
class AggregatedHabitMetrics {
  final int totalFocusHours;
  final int totalReclaimedDoomscrollHours;
  final int totalBreakMinutes;
  final int totalInterventions;
  final double averageAdherencePercentage;
  final int currentStreakDays;
  final int habitConsistencyScore; // 0 to 100
  final double urgeResistanceRate; // 0.0 to 1.0

  const AggregatedHabitMetrics({
    required this.totalFocusHours,
    required this.totalReclaimedDoomscrollHours,
    required this.totalBreakMinutes,
    required this.totalInterventions,
    required this.averageAdherencePercentage,
    required this.currentStreakDays,
    required this.habitConsistencyScore,
    required this.urgeResistanceRate,
  });
}

/// Mathematical behavioral science engine computing cognitive wellness and habit formation indices.
class HabitPsychologyCalculator {
  /// Aggregates historical data points over a specific rolling window of days.
  static AggregatedHabitMetrics calculateWindow(
    List<HistoricalFocusDataPoint> points, {
    required int windowDays,
  }) {
    if (points.isEmpty) {
      return const AggregatedHabitMetrics(
        totalFocusHours: 0,
        totalReclaimedDoomscrollHours: 0,
        totalBreakMinutes: 0,
        totalInterventions: 0,
        averageAdherencePercentage: 100.0,
        currentStreakDays: 0,
        habitConsistencyScore: 100,
        urgeResistanceRate: 1.0,
      );
    }

    final cutoff = DateTime.now().subtract(Duration(days: windowDays));
    final relevant = points.where((p) => p.timestamp.isAfter(cutoff)).toList();

    if (relevant.isEmpty) {
      return const AggregatedHabitMetrics(
        totalFocusHours: 0,
        totalReclaimedDoomscrollHours: 0,
        totalBreakMinutes: 0,
        totalInterventions: 0,
        averageAdherencePercentage: 100.0,
        currentStreakDays: 0,
        habitConsistencyScore: 100,
        urgeResistanceRate: 1.0,
      );
    }

    int sumFocusMinutes = 0;
    int sumBreakMinutes = 0;
    int sumInterventions = 0;
    int sumReclaimedMinutes = 0;
    double sumAdherence = 0.0;

    for (final p in relevant) {
      sumFocusMinutes += p.focusMinutes;
      sumBreakMinutes += p.breakMinutes;
      sumInterventions += p.blockedAttempts;
      sumReclaimedMinutes += p.estimatedReclaimedMinutes;
      sumAdherence += p.adherenceScore;
    }

    final avgAdherence = (sumAdherence / relevant.length) * 100.0;

    // Consistency score (0 - 100) based on regularity of focus minutes
    final consistencyScore = (avgAdherence * 0.7 + (relevant.length / windowDays) * 30).clamp(0.0, 100.0).toInt();

    // Urge Resistance Rate: ratio of blocked attempts that were safely deflected
    final totalUrges = sumInterventions + (sumFocusMinutes ~/ 45);
    final ubb = totalUrges > 0 ? (sumInterventions / totalUrges).clamp(0.0, 1.0) : 1.0;

    final streak = calculateCurrentStreak(points);

    return AggregatedHabitMetrics(
      totalFocusHours: sumFocusMinutes ~/ 60,
      totalReclaimedDoomscrollHours: sumReclaimedMinutes ~/ 60,
      totalBreakMinutes: sumBreakMinutes,
      totalInterventions: sumInterventions,
      averageAdherencePercentage: avgAdherence.clamp(0.0, 100.0),
      currentStreakDays: streak,
      habitConsistencyScore: consistencyScore,
      urgeResistanceRate: ubb,
    );
  }

  /// Calculates consecutive daily streak where focus goal (>= 120 minutes) was met.
  static int calculateCurrentStreak(List<HistoricalFocusDataPoint> points) {
    if (points.isEmpty) return 0;

    final sorted = List<HistoricalFocusDataPoint>.from(points)
      ..sort((a, b) => b.timestamp.compareTo(a.timestamp));

    int streak = 0;
    DateTime lastDate = DateTime.now();

    for (final p in sorted) {
      final daysDiff = lastDate.difference(p.timestamp).inDays;
      if (daysDiff <= 1 && p.focusMinutes >= 120) {
        streak++;
        lastDate = p.timestamp;
      } else if (daysDiff > 1) {
        break;
      }
    }

    return streak;
  }
}
