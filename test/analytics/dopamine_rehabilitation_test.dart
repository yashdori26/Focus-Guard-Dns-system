import 'package:flutter_test/flutter_test.dart';
import 'package:focus_dns/engine/analytics/dopamine_rehabilitation_historian.dart';

void main() {
  group('Dopamine Rehabilitation Historian Tests', () {
    test('1. Day 0 sensitivity equals baseline pre-detox (25%)', () {
      final s0 = DopamineRehabilitationHistorian.calculateReceptorSensitivity(0);
      expect(s0, equals(25.0));
    });

    test('2. Sensitivity strictly increases monotonically with days clean', () {
      double previous = 0.0;
      for (int day = 0; day <= 30; day++) {
        final current = DopamineRehabilitationHistorian.calculateReceptorSensitivity(day);
        expect(current, greaterThanOrEqualTo(previous));
        previous = current;
      }
      expect(previous, greaterThan(85.0)); // Day 30 achieves > 85%
    });

    test('3. Stage registry categorizes 4 clinical phases accurately', () {
      expect(
        DopamineRehabilitationHistorian.getStageForDays(2).stage,
        equals(DopamineRehabilitationStage.acuteWithdrawal),
      );
      expect(
        DopamineRehabilitationHistorian.getStageForDays(7).stage,
        equals(DopamineRehabilitationStage.neurochemicalReset),
      );
      expect(
        DopamineRehabilitationHistorian.getStageForDays(14).stage,
        equals(DopamineRehabilitationStage.synapticPruning),
      );
      expect(
        DopamineRehabilitationHistorian.getStageForDays(25).stage,
        equals(DopamineRehabilitationStage.dopaminergicEquilibrium),
      );
    });

    test('4. Tangible focus equivalents computes books read and deep work blocks', () {
      // 560 minutes = 2 books (280m per book) = 6.2 deep blocks (90m each)
      final tangible = DopamineRehabilitationHistorian.calculateTangibleEquivalents(
        560,
        lateNightTrapsSevered: 4,
      );

      expect(tangible.booksReadEquivalent, equals(2.0));
      expect(tangible.deepWorkBlocks, closeTo(6.22, 0.01));
      expect(tangible.lateNightSleepQualityBoost, equals(14.0)); // 4 * 3.5%
      expect(tangible.attentionSpanReclaimedSeconds, equals(45)); // (9 hrs * 5s)
    });

    test('5. 30-day projected curve data points contain 31 elements', () {
      final curve = DopamineRehabilitationHistorian.generateRecoveryCurveData(14);
      expect(curve.length, equals(31)); // Day 0 to 30
      expect(curve[14]['isCurrentDay'], equals(1.0));
      expect(curve[0]['isCurrentDay'], equals(0.0));
    });
  });
}
