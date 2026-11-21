import 'package:flutter_test/flutter_test.dart';
import 'package:focus_dns/engine/analytics/streak_momentum_calculator.dart';

void main() {
  group('Streak Momentum Calculator Tests', () {
    test('1. Initial streak record starts at zero with 2 freeze tokens', () {
      final record = StreakRecord.initial();
      expect(record.currentStreakDays, equals(0));
      expect(record.longestStreakDays, equals(0));
      expect(record.freezeTokensRemaining, equals(2));
      expect(record.lastActiveDate, isNull);
    });

    test('2. First activity establishes streak of 1 day', () {
      final initial = StreakRecord.initial();
      final day1 = DateTime(2026, 11, 1);
      final updated = StreakMomentumCalculator.recordActivity(initial, day1, dailyScore: 100.0);

      expect(updated.currentStreakDays, equals(1));
      expect(updated.longestStreakDays, equals(1));
      expect(updated.lastActiveDate, equals(DateTime(2026, 11, 1)));
      expect(updated.dailyAdherenceScores['2026-11-01'], equals(100.0));
    });

    test('3. Same day activity does not double-increment streak', () {
      final initial = StreakRecord.initial();
      final day1 = DateTime(2026, 11, 1, 10, 0);
      final r1 = StreakMomentumCalculator.recordActivity(initial, day1);

      final day1Later = DateTime(2026, 11, 1, 18, 30);
      final r2 = StreakMomentumCalculator.recordActivity(r1, day1Later);

      expect(r2.currentStreakDays, equals(1));
      expect(r2.longestStreakDays, equals(1));
    });

    test('4. Consecutive day increments streak to 2 and 3', () {
      var record = StreakRecord.initial();
      record = StreakMomentumCalculator.recordActivity(record, DateTime(2026, 11, 1));
      record = StreakMomentumCalculator.recordActivity(record, DateTime(2026, 11, 2));
      record = StreakMomentumCalculator.recordActivity(record, DateTime(2026, 11, 3));

      expect(record.currentStreakDays, equals(3));
      expect(record.longestStreakDays, equals(3));
    });

    test('5. Single missed day is protected by freeze token', () {
      var record = StreakRecord.initial();
      record = StreakMomentumCalculator.recordActivity(record, DateTime(2026, 11, 1));
      record = StreakMomentumCalculator.recordActivity(record, DateTime(2026, 11, 2));
      expect(record.currentStreakDays, equals(2));
      expect(record.freezeTokensRemaining, equals(2));

      // Skip Nov 3, resume on Nov 4 (2 days difference)
      record = StreakMomentumCalculator.recordActivity(record, DateTime(2026, 11, 4));

      expect(record.currentStreakDays, equals(3)); // Preserved!
      expect(record.freezeTokensRemaining, equals(1)); // One token spent
    });

    test('6. Two consecutive missed days resets streak to 1', () {
      var record = StreakRecord.initial();
      record = StreakMomentumCalculator.recordActivity(record, DateTime(2026, 11, 1));
      record = StreakMomentumCalculator.recordActivity(record, DateTime(2026, 11, 2));
      expect(record.currentStreakDays, equals(2));

      // Skip Nov 3 & Nov 4, resume Nov 5 (3 days difference)
      record = StreakMomentumCalculator.recordActivity(record, DateTime(2026, 11, 5));

      expect(record.currentStreakDays, equals(1)); // Reset
      expect(record.longestStreakDays, equals(2)); // Retains best
    });

    test('7. Momentum score calculation applies exponential decay', () {
      var record = StreakRecord.initial();
      final ref = DateTime(2026, 11, 10);

      // 5 perfect days leading up to ref
      for (int i = 0; i < 5; i++) {
        record = StreakMomentumCalculator.recordActivity(
          record,
          ref.subtract(Duration(days: i)),
          dailyScore: 100.0,
        );
      }

      final score = StreakMomentumCalculator.calculateMomentumScore(record, ref);
      // Recent days weighted heavily
      expect(score, greaterThan(20.0));
      expect(score, lessThanOrEqualTo(100.0));
    });

    test('8. Relapse risk evaluation identifies active vs inactive patterns', () {
      var record = StreakRecord.initial();
      final today = DateTime(2026, 11, 10);

      // Active user
      record = StreakMomentumCalculator.recordActivity(record, today);
      final riskActive = StreakMomentumCalculator.evaluateRelapseRisk(record, today);
      expect(riskActive, isNot(equals(RelapseRiskLevel.critical)));

      // Inactive for 5 days
      final futureDate = today.add(const Duration(days: 5));
      final riskStale = StreakMomentumCalculator.evaluateRelapseRisk(record, futureDate);
      expect(riskStale, equals(RelapseRiskLevel.critical));
    });

    test('9. Milestone unlocks match required day counts', () {
      final m3 = StreakMomentumCalculator.getUnlockedMilestones(3);
      expect(m3.length, equals(1));
      expect(m3.first.milestone, equals(StreakMilestone.firstStep));

      final m7 = StreakMomentumCalculator.getUnlockedMilestones(7);
      expect(m7.length, equals(2));

      final m30 = StreakMomentumCalculator.getUnlockedMilestones(30);
      expect(m30.any((m) => m.milestone == StreakMilestone.habitForged), isTrue);

      final next = StreakMomentumCalculator.getNextMilestone(5);
      expect(next?.milestone, equals(StreakMilestone.unbreakableWeek));
      expect(StreakMomentumCalculator.daysUntilNextMilestone(5), equals(2));
    });

    test('10. JSON serialization preserves full streak state', () {
      final original = StreakRecord(
        currentStreakDays: 14,
        longestStreakDays: 21,
        freezeTokensRemaining: 1,
        lastActiveDate: DateTime(2026, 11, 8),
        dailyAdherenceScores: {
          '2026-11-07': 95.0,
          '2026-11-08': 100.0,
        },
      );

      final json = original.toJson();
      final revived = StreakRecord.fromJson(json);

      expect(revived.currentStreakDays, equals(14));
      expect(revived.longestStreakDays, equals(21));
      expect(revived.freezeTokensRemaining, equals(1));
      expect(revived.dailyAdherenceScores['2026-11-08'], equals(100.0));
    });
  });
}
