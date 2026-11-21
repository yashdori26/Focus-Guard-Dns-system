import 'dart:math' as math;
import 'package:flutter/foundation.dart';

/// Milestone achievements unlocked via continuous focus streaks.
enum StreakMilestone {
  firstStep, // 3 Days
  unbreakableWeek, // 7 Days
  fortressOfSolitude, // 14 Days
  habitForged, // 30 Days
  centuryFocus, // 100 Days
  dopamineMaster, // 180 Days
  yearOfSovereignty, // 365 Days
  legendaryTitan, // 500 Days
}

/// Relapse vulnerability risk level.
enum RelapseRiskLevel {
  low,
  moderate,
  high,
  critical,
}

/// Metadata describing a streak milestone.
class StreakMilestoneInfo {
  final StreakMilestone milestone;
  final String title;
  final String description;
  final int requiredDays;
  final String icon;

  const StreakMilestoneInfo({
    required this.milestone,
    required this.title,
    required this.description,
    required this.requiredDays,
    required this.icon,
  });
}

/// Data entity capturing active streak records, historical daily adherence,
/// and available freeze tokens.
@immutable
class StreakRecord {
  final int currentStreakDays;
  final int longestStreakDays;
  final int freezeTokensRemaining;
  final DateTime? lastActiveDate;
  final Map<String, double> dailyAdherenceScores; // 'YYYY-MM-DD' -> score (0.0 - 100.0)

  const StreakRecord({
    required this.currentStreakDays,
    required this.longestStreakDays,
    required this.freezeTokensRemaining,
    this.lastActiveDate,
    required this.dailyAdherenceScores,
  });

  factory StreakRecord.initial() {
    return const StreakRecord(
      currentStreakDays: 0,
      longestStreakDays: 0,
      freezeTokensRemaining: 2,
      lastActiveDate: null,
      dailyAdherenceScores: {},
    );
  }

  StreakRecord copyWith({
    int? currentStreakDays,
    int? longestStreakDays,
    int? freezeTokensRemaining,
    DateTime? lastActiveDate,
    Map<String, double>? dailyAdherenceScores,
  }) {
    return StreakRecord(
      currentStreakDays: currentStreakDays ?? this.currentStreakDays,
      longestStreakDays: longestStreakDays ?? this.longestStreakDays,
      freezeTokensRemaining: freezeTokensRemaining ?? this.freezeTokensRemaining,
      lastActiveDate: lastActiveDate ?? this.lastActiveDate,
      dailyAdherenceScores: dailyAdherenceScores ?? this.dailyAdherenceScores,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'currentStreakDays': currentStreakDays,
      'longestStreakDays': longestStreakDays,
      'freezeTokensRemaining': freezeTokensRemaining,
      'lastActiveDate': lastActiveDate?.toIso8601String(),
      'dailyAdherenceScores': dailyAdherenceScores,
    };
  }

  factory StreakRecord.fromJson(Map<String, dynamic> json) {
    return StreakRecord(
      currentStreakDays: json['currentStreakDays'] as int? ?? 0,
      longestStreakDays: json['longestStreakDays'] as int? ?? 0,
      freezeTokensRemaining: json['freezeTokensRemaining'] as int? ?? 2,
      lastActiveDate: json['lastActiveDate'] != null
          ? DateTime.tryParse(json['lastActiveDate'] as String)
          : null,
      dailyAdherenceScores: (json['dailyAdherenceScores'] as Map<String, dynamic>?)
              ?.map((k, v) => MapEntry(k, (v as num).toDouble())) ??
          {},
    );
  }
}

/// Mathematical engine calculating weighted streak momentum, relapse indicators,
/// milestone unlocks, and freeze token application.
class StreakMomentumCalculator {
  static const double decayFactor = 0.95; // Exponential discount factor gamma

  static const List<StreakMilestoneInfo> allMilestones = [
    StreakMilestoneInfo(
      milestone: StreakMilestone.firstStep,
      title: 'First Step',
      description: '3 consecutive days of intentional focus.',
      requiredDays: 3,
      icon: '🌱',
    ),
    StreakMilestoneInfo(
      milestone: StreakMilestone.unbreakableWeek,
      title: 'Unbreakable Week',
      description: '7 days of uninterrupted dopamine shield.',
      requiredDays: 7,
      icon: '🛡️',
    ),
    StreakMilestoneInfo(
      milestone: StreakMilestone.fortressOfSolitude,
      title: 'Fortress of Solitude',
      description: '14 days of deep intentionality.',
      requiredDays: 14,
      icon: '🏰',
    ),
    StreakMilestoneInfo(
      milestone: StreakMilestone.habitForged,
      title: 'Habit Forged',
      description: '30 days — neural pathways permanently rewired.',
      requiredDays: 30,
      icon: '🔥',
    ),
    StreakMilestoneInfo(
      milestone: StreakMilestone.centuryFocus,
      title: 'Century Focus',
      description: '100 days of relentless sovereignty.',
      requiredDays: 100,
      icon: '⚡',
    ),
    StreakMilestoneInfo(
      milestone: StreakMilestone.dopamineMaster,
      title: 'Dopamine Master',
      description: '180 days — complete neurochemical restoration.',
      requiredDays: 180,
      icon: '🧠',
    ),
    StreakMilestoneInfo(
      milestone: StreakMilestone.yearOfSovereignty,
      title: 'Year of Sovereignty',
      description: '365 days of uncompromising deep work.',
      requiredDays: 365,
      icon: '👑',
    ),
    StreakMilestoneInfo(
      milestone: StreakMilestone.legendaryTitan,
      title: 'Legendary Titan',
      description: '500 days of legendary mental fortress.',
      requiredDays: 500,
      icon: '🌌',
    ),
  ];

  /// Records a completed focus session for a given day and updates streak state.
  static StreakRecord recordActivity(
    StreakRecord current,
    DateTime sessionDate, {
    double dailyScore = 100.0,
  }) {
    final dayKey = _formatDateKey(sessionDate);
    final updatedScores = Map<String, double>.from(current.dailyAdherenceScores);
    updatedScores[dayKey] = math.max(updatedScores[dayKey] ?? 0.0, dailyScore);

    final today = _normalizeDate(sessionDate);
    final lastActive = current.lastActiveDate != null ? _normalizeDate(current.lastActiveDate!) : null;

    if (lastActive == null) {
      // First ever activity
      return current.copyWith(
        currentStreakDays: 1,
        longestStreakDays: math.max(1, current.longestStreakDays),
        lastActiveDate: today,
        dailyAdherenceScores: updatedScores,
      );
    }

    final differenceDays = today.difference(lastActive).inDays;

    if (differenceDays == 0) {
      // Activity on the same day, streak unchanged
      return current.copyWith(
        lastActiveDate: today,
        dailyAdherenceScores: updatedScores,
      );
    } else if (differenceDays == 1) {
      // Consecutive day! Increment streak
      final newStreak = current.currentStreakDays + 1;
      return current.copyWith(
        currentStreakDays: newStreak,
        longestStreakDays: math.max(newStreak, current.longestStreakDays),
        lastActiveDate: today,
        dailyAdherenceScores: updatedScores,
      );
    } else if (differenceDays == 2 && current.freezeTokensRemaining > 0) {
      // Missed 1 day, but freeze token preserves streak!
      final newStreak = current.currentStreakDays + 1;
      return current.copyWith(
        currentStreakDays: newStreak,
        longestStreakDays: math.max(newStreak, current.longestStreakDays),
        freezeTokensRemaining: current.freezeTokensRemaining - 1,
        lastActiveDate: today,
        dailyAdherenceScores: updatedScores,
      );
    } else {
      // Streak broken, reset to 1
      return current.copyWith(
        currentStreakDays: 1,
        lastActiveDate: today,
        dailyAdherenceScores: updatedScores,
      );
    }
  }

  /// Calculates mathematically weighted momentum score (0.0 to 100.0).
  /// Formula: M = (Sum(gamma^i * S_i) / Sum(gamma^i))
  static double calculateMomentumScore(StreakRecord record, [DateTime? referenceDate]) {
    final ref = _normalizeDate(referenceDate ?? DateTime.now());
    double weightedSum = 0.0;
    double weightTotal = 0.0;

    for (int i = 0; i < 30; i++) {
      final targetDay = ref.subtract(Duration(days: i));
      final dayKey = _formatDateKey(targetDay);
      final score = record.dailyAdherenceScores[dayKey] ?? 0.0;
      final weight = math.pow(decayFactor, i).toDouble();

      weightedSum += score * weight;
      weightTotal += weight * 100.0;
    }

    if (weightTotal == 0.0) return 0.0;
    final momentum = (weightedSum / weightTotal) * 100.0;
    return momentum.clamp(0.0, 100.0);
  }

  /// Evaluates relapse risk level by comparing short-term momentum to baseline.
  static RelapseRiskLevel evaluateRelapseRisk(StreakRecord record, [DateTime? referenceDate]) {
    final ref = _normalizeDate(referenceDate ?? DateTime.now());

    if (record.lastActiveDate == null) return RelapseRiskLevel.critical;

    final daysSince = ref.difference(_normalizeDate(record.lastActiveDate!)).inDays;
    if (daysSince >= 4) return RelapseRiskLevel.critical;
    if (daysSince >= 2) return RelapseRiskLevel.high;
    if (daysSince == 1) return RelapseRiskLevel.moderate;

    final momentum = calculateMomentumScore(record, ref);
    if (momentum >= 50.0 || record.currentStreakDays >= 3) return RelapseRiskLevel.low;
    return RelapseRiskLevel.moderate;
  }

  /// Returns all milestone achievements unlocked by the current streak.
  static List<StreakMilestoneInfo> getUnlockedMilestones(int streakDays) {
    return allMilestones.where((m) => streakDays >= m.requiredDays).toList();
  }

  /// Returns next upcoming milestone.
  static StreakMilestoneInfo? getNextMilestone(int streakDays) {
    for (final m in allMilestones) {
      if (streakDays < m.requiredDays) return m;
    }
    return null;
  }

  /// Days remaining until next milestone.
  static int daysUntilNextMilestone(int streakDays) {
    final next = getNextMilestone(streakDays);
    if (next == null) return 0;
    return next.requiredDays - streakDays;
  }

  static String _formatDateKey(DateTime dt) {
    final y = dt.year.toString().padLeft(4, '0');
    final m = dt.month.toString().padLeft(2, '0');
    final d = dt.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }

  static DateTime _normalizeDate(DateTime dt) {
    return DateTime(dt.year, dt.month, dt.day);
  }
}
