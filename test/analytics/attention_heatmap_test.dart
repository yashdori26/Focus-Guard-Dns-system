import 'package:flutter_test/flutter_test.dart';
import 'package:focus_dns/engine/analytics/attention_heatmap_matrix.dart';

void main() {
  group('Attention Heatmap Matrix Tests', () {
    test('1. Empty matrix initializes all 168 cells with 0 counts', () {
      final matrix = AttentionHeatmapMatrix.empty();
      for (int d = 1; d <= 7; d++) {
        for (int h = 0; h < 24; h++) {
          final cell = matrix.getCell(d, h);
          expect(cell.dayOfWeek, equals(d));
          expect(cell.hourOfDay, equals(h));
          expect(cell.interceptionCount, equals(0));
          expect(cell.focusMinutes, equals(0));
          expect(cell.normalizedRiskScore, equals(0.0));
        }
      }
    });

    test('2. Recording interception updates specific day and hour', () {
      final matrix = AttentionHeatmapMatrix.empty();
      // Friday (5) at 22:15
      final timestamp = DateTime(2026, 11, 6, 22, 15);
      matrix.recordInterception(timestamp, 3);

      final cell = matrix.getCell(DateTime.friday, 22);
      expect(cell.interceptionCount, equals(3));
      expect(cell.focusMinutes, equals(0));
      expect(cell.normalizedRiskScore, greaterThan(0.5));
    });

    test('3. Recording focus minutes updates specific cell', () {
      final matrix = AttentionHeatmapMatrix.empty();
      // Wednesday (3) at 10:00
      final timestamp = DateTime(2026, 11, 4, 10, 0);
      matrix.recordFocus(timestamp, 50);

      final cell = matrix.getCell(DateTime.wednesday, 10);
      expect(cell.focusMinutes, equals(50));
      expect(cell.interceptionCount, equals(0));
      expect(cell.normalizedRiskScore, equals(0.1)); // Deep work baseline
    });

    test('4. Peak vulnerability detection accurately identifies top distracted hours', () {
      final matrix = AttentionHeatmapMatrix.empty();
      // Friday 22:00 -> 10 interceptions
      matrix.recordInterception(DateTime(2026, 11, 6, 22, 0), 10);
      // Saturday 23:00 -> 8 interceptions
      matrix.recordInterception(DateTime(2026, 11, 7, 23, 0), 8);
      // Tuesday 14:00 -> 2 interceptions
      matrix.recordInterception(DateTime(2026, 11, 3, 14, 0), 2);

      final peaks = matrix.findPeakVulnerabilityHours(2);
      expect(peaks.length, equals(2));
      expect(peaks.first.dayOfWeek, equals(DateTime.friday));
      expect(peaks.first.hourOfDay, equals(22));
      expect(peaks.first.interceptionCount, equals(10));

      expect(peaks[1].dayOfWeek, equals(DateTime.saturday));
      expect(peaks[1].hourOfDay, equals(23));
      expect(peaks[1].interceptionCount, equals(8));
    });

    test('5. Diurnal attention split categorizes four quarters of the day', () {
      final matrix = AttentionHeatmapMatrix.empty();
      // Morning (8:00): 60 mins
      matrix.recordFocus(DateTime(2026, 11, 2, 8, 0), 60);
      // Afternoon (14:00): 60 mins
      matrix.recordFocus(DateTime(2026, 11, 2, 14, 0), 60);

      final split = matrix.calculateDiurnalSplit();
      expect(split.morningRatio, closeTo(0.5, 0.01));
      expect(split.afternoonRatio, closeTo(0.5, 0.01));
      expect(split.eveningRatio, equals(0.0));
      expect(split.nightRatio, equals(0.0));
    });

    test('6. Weekly totals aggregation sums all 168 cells', () {
      final matrix = AttentionHeatmapMatrix.empty();
      matrix.recordFocus(DateTime(2026, 11, 2, 9, 0), 45);
      matrix.recordFocus(DateTime(2026, 11, 3, 10, 0), 45);
      matrix.recordInterception(DateTime(2026, 11, 2, 21, 0), 5);
      matrix.recordInterception(DateTime(2026, 11, 3, 21, 0), 7);

      expect(matrix.totalWeeklyFocusMinutes, equals(90));
      expect(matrix.totalWeeklyInterceptions, equals(12));
    });

    test('7. JSON serialization roundtrip preserves 168 cells', () {
      final original = AttentionHeatmapMatrix.empty();
      original.recordInterception(DateTime(2026, 11, 5, 23, 0), 9);
      original.recordFocus(DateTime(2026, 11, 5, 11, 0), 75);

      final json = original.toJson();
      final revived = AttentionHeatmapMatrix.fromJson(json);

      expect(revived.getCell(DateTime.thursday, 23).interceptionCount, equals(9));
      expect(revived.getCell(DateTime.thursday, 11).focusMinutes, equals(75));
    });
  });
}
