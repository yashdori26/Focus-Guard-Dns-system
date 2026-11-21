import 'package:flutter_test/flutter_test.dart';
import 'package:focus_dns/engine/analytics/session_lifecycle_metrics.dart';

void main() {
  group('Session Lifecycle Metrics Tests', () {
    test('1. Baseline empty metrics initializes to zero', () {
      final m = SessionLifecycleMetrics.empty();
      expect(m.sessionsInitiated, equals(0));
      expect(m.sessionsCompleted, equals(0));
      expect(m.totalFocusMinutes, equals(0));
      expect(m.adherenceRate, equals(100.0));
      expect(m.averageFocusSessionMinutes, equals(0.0));
    });

    test('2. Adherence rate calculation with completions and aborts', () {
      final m = SessionLifecycleMetrics(
        sessionsInitiated: 10,
        sessionsCompleted: 8,
        sessionsAborted: 2,
        strictLocksEnforced: 5,
        breakOvershootsPrevented: 3,
        frictionPledgesSubmitted: 1,
        emergencyRequestsInitiated: 0,
        emergencyRequestsApproved: 0,
        totalFocusMinutes: 200,
        totalBreakMinutes: 40,
        totalDistractionInterceptions: 45,
        bandwidthBytesSaved: 1024 * 1024 * 50,
        lastRecordedAt: DateTime.now(),
      );

      expect(m.adherenceRate, equals(80.0));
      expect(m.averageFocusSessionMinutes, equals(25.0));
      expect(m.focusToBreakRatio, equals(5.0));
      expect(m.totalHoursReclaimed, closeTo(3.33, 0.01));
      expect(m.megabytesSaved, equals(50.0));
    });

    test('3. Discipline rating resolves appropriate status', () {
      final sovereign = SessionLifecycleMetrics(
        sessionsInitiated: 20,
        sessionsCompleted: 20,
        sessionsAborted: 0,
        strictLocksEnforced: 12,
        breakOvershootsPrevented: 10,
        frictionPledgesSubmitted: 0,
        emergencyRequestsInitiated: 0,
        emergencyRequestsApproved: 0,
        totalFocusMinutes: 600,
        totalBreakMinutes: 60,
        totalDistractionInterceptions: 150,
        bandwidthBytesSaved: 0,
        lastRecordedAt: DateTime.now(),
      );
      expect(sovereign.disciplineRating, equals('Dopamine Sovereign'));

      final guardian = sovereign.copyWith(sessionsCompleted: 18); // 90%
      expect(guardian.disciplineRating, equals('Deep Work Guardian'));

      final focused = sovereign.copyWith(sessionsCompleted: 15); // 75%
      expect(focused.disciplineRating, equals('Focused Practitioner'));
    });

    test('4. Merging two metrics objects produces correct cumulative sum', () {
      final m1 = SessionLifecycleMetrics(
        sessionsInitiated: 5,
        sessionsCompleted: 4,
        sessionsAborted: 1,
        strictLocksEnforced: 2,
        breakOvershootsPrevented: 2,
        frictionPledgesSubmitted: 0,
        emergencyRequestsInitiated: 0,
        emergencyRequestsApproved: 0,
        totalFocusMinutes: 100,
        totalBreakMinutes: 20,
        totalDistractionInterceptions: 30,
        bandwidthBytesSaved: 1000,
        lastRecordedAt: DateTime(2026, 11, 1),
      );

      final m2 = SessionLifecycleMetrics(
        sessionsInitiated: 3,
        sessionsCompleted: 3,
        sessionsAborted: 0,
        strictLocksEnforced: 3,
        breakOvershootsPrevented: 1,
        frictionPledgesSubmitted: 1,
        emergencyRequestsInitiated: 1,
        emergencyRequestsApproved: 1,
        totalFocusMinutes: 75,
        totalBreakMinutes: 15,
        totalDistractionInterceptions: 20,
        bandwidthBytesSaved: 2000,
        lastRecordedAt: DateTime(2026, 11, 2),
      );

      final merged = m1.merge(m2);
      expect(merged.sessionsInitiated, equals(8));
      expect(merged.sessionsCompleted, equals(7));
      expect(merged.totalFocusMinutes, equals(175));
      expect(merged.totalDistractionInterceptions, equals(50));
      expect(merged.bandwidthBytesSaved, equals(3000));
      expect(merged.emergencyRequestsApproved, equals(1));
      expect(merged.lastRecordedAt, equals(DateTime(2026, 11, 2)));
    });

    test('5. JSON round-trip serialization maintains full fidelity', () {
      final original = SessionLifecycleMetrics(
        sessionsInitiated: 12,
        sessionsCompleted: 11,
        sessionsAborted: 1,
        strictLocksEnforced: 6,
        breakOvershootsPrevented: 4,
        frictionPledgesSubmitted: 2,
        emergencyRequestsInitiated: 1,
        emergencyRequestsApproved: 0,
        totalFocusMinutes: 330,
        totalBreakMinutes: 55,
        totalDistractionInterceptions: 88,
        bandwidthBytesSaved: 1024 * 1024 * 120,
        lastRecordedAt: DateTime(2026, 11, 8, 12, 0, 0),
      );

      final json = original.toJson();
      final revived = SessionLifecycleMetrics.fromJson(json);

      expect(revived.sessionsInitiated, equals(original.sessionsInitiated));
      expect(revived.sessionsCompleted, equals(original.sessionsCompleted));
      expect(revived.totalFocusMinutes, equals(original.totalFocusMinutes));
      expect(revived.bandwidthBytesSaved, equals(original.bandwidthBytesSaved));
      expect(revived.lastRecordedAt, equals(original.lastRecordedAt));
    });
  });
}
