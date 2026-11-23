import 'dart:math' as math;
import 'package:flutter/foundation.dart';

/// Single cell in the 7-day x 24-hour cognitive attention matrix.
@immutable
class HeatmapCell {
  final int dayOfWeek; // 1 (Mon) to 7 (Sun)
  final int hourOfDay; // 0 to 23
  final int interceptionCount;
  final int focusMinutes;

  const HeatmapCell({
    required this.dayOfWeek,
    required this.hourOfDay,
    this.interceptionCount = 0,
    this.focusMinutes = 0,
  });

  /// Normalized distraction risk score (0.0 to 1.0).
  /// High interceptions relative to focus minutes indicates temptation traps.
  double get normalizedRiskScore {
    if (interceptionCount == 0 && focusMinutes == 0) return 0.0;
    if (focusMinutes > 0 && interceptionCount == 0) return 0.1; // Clean deep work
    final rawRisk = interceptionCount / (interceptionCount + (focusMinutes / 10.0));
    return rawRisk.clamp(0.0, 1.0);
  }

  HeatmapCell copyWith({
    int? interceptionCount,
    int? focusMinutes,
  }) {
    return HeatmapCell(
      dayOfWeek: dayOfWeek,
      hourOfDay: hourOfDay,
      interceptionCount: interceptionCount ?? this.interceptionCount,
      focusMinutes: focusMinutes ?? this.focusMinutes,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'dayOfWeek': dayOfWeek,
      'hourOfDay': hourOfDay,
      'interceptionCount': interceptionCount,
      'focusMinutes': focusMinutes,
    };
  }

  factory HeatmapCell.fromJson(Map<String, dynamic> json) {
    return HeatmapCell(
      dayOfWeek: json['dayOfWeek'] as int,
      hourOfDay: json['hourOfDay'] as int,
      interceptionCount: json['interceptionCount'] as int? ?? 0,
      focusMinutes: json['focusMinutes'] as int? ?? 0,
    );
  }
}

/// Diurnal time-of-day attention distribution metrics.
class DiurnalAttentionSplit {
  final double morningRatio; // 06:00 - 12:00
  final double afternoonRatio; // 12:00 - 18:00
  final double eveningRatio; // 18:00 - 22:00
  final double nightRatio; // 22:00 - 06:00

  const DiurnalAttentionSplit({
    required this.morningRatio,
    required this.afternoonRatio,
    required this.eveningRatio,
    required this.nightRatio,
  });
}

/// 7-day x 24-hour cognitive attention matrix quantifying distraction vulnerability peaks.
class AttentionHeatmapMatrix {
  // 7 rows (days 1..7) x 24 cols (hours 0..23)
  final List<List<HeatmapCell>> _grid;

  AttentionHeatmapMatrix._(this._grid);

  /// Creates a blank 7x24 matrix initialized to zero.
  factory AttentionHeatmapMatrix.empty() {
    final grid = List.generate(7, (d) {
      final dayOfWeek = d + 1; // 1 to 7
      return List.generate(24, (h) => HeatmapCell(dayOfWeek: dayOfWeek, hourOfDay: h));
    });
    return AttentionHeatmapMatrix._(grid);
  }

  /// Gets the cell for a specific day (1..7) and hour (0..23).
  HeatmapCell getCell(int dayOfWeek, int hourOfDay) {
    final d = (dayOfWeek - 1).clamp(0, 6);
    final h = hourOfDay.clamp(0, 23);
    return _grid[d][h];
  }

  /// Records an interception event at a specific timestamp.
  void recordInterception(DateTime timestamp, [int count = 1]) {
    final d = (timestamp.weekday - 1).clamp(0, 6);
    final h = timestamp.hour.clamp(0, 23);
    final current = _grid[d][h];
    _grid[d][h] = current.copyWith(interceptionCount: current.interceptionCount + count);
  }

  /// Records focus session minutes at a specific timestamp.
  void recordFocus(DateTime timestamp, int minutes) {
    final d = (timestamp.weekday - 1).clamp(0, 6);
    final h = timestamp.hour.clamp(0, 23);
    final current = _grid[d][h];
    _grid[d][h] = current.copyWith(focusMinutes: current.focusMinutes + minutes);
  }

  /// Returns the top [limit] most vulnerable distraction hours of the week.
  List<HeatmapCell> findPeakVulnerabilityHours([int limit = 3]) {
    final allCells = <HeatmapCell>[];
    for (int d = 0; d < 7; d++) {
      for (int h = 0; h < 24; h++) {
        allCells.add(_grid[d][h]);
      }
    }

    allCells.sort((a, b) => b.interceptionCount.compareTo(a.interceptionCount));
    return allCells.where((c) => c.interceptionCount > 0).take(limit).toList();
  }

  /// Calculates diurnal attention split across the four quarters of the day.
  DiurnalAttentionSplit calculateDiurnalSplit() {
    int morningFocus = 0;
    int afternoonFocus = 0;
    int eveningFocus = 0;
    int nightFocus = 0;

    for (int d = 0; d < 7; d++) {
      for (int h = 0; h < 24; h++) {
        final mins = _grid[d][h].focusMinutes;
        if (h >= 6 && h < 12) {
          morningFocus += mins;
        } else if (h >= 12 && h < 18) {
          afternoonFocus += mins;
        } else if (h >= 18 && h < 22) {
          eveningFocus += mins;
        } else {
          nightFocus += mins;
        }
      }
    }

    final total = morningFocus + afternoonFocus + eveningFocus + nightFocus;
    if (total == 0) {
      return const DiurnalAttentionSplit(
        morningRatio: 0.25,
        afternoonRatio: 0.25,
        eveningRatio: 0.25,
        nightRatio: 0.25,
      );
    }

    return DiurnalAttentionSplit(
      morningRatio: morningFocus / total,
      afternoonRatio: afternoonFocus / total,
      eveningRatio: eveningFocus / total,
      nightRatio: nightFocus / total,
    );
  }

  /// Returns total weekly interceptions.
  int get totalWeeklyInterceptions {
    int sum = 0;
    for (int d = 0; d < 7; d++) {
      for (int h = 0; h < 24; h++) {
        sum += _grid[d][h].interceptionCount;
      }
    }
    return sum;
  }

  /// Returns total weekly focus minutes.
  int get totalWeeklyFocusMinutes {
    int sum = 0;
    for (int d = 0; d < 7; d++) {
      for (int h = 0; h < 24; h++) {
        sum += _grid[d][h].focusMinutes;
      }
    }
    return sum;
  }

  /// Serializes matrix to 2D list of JSON maps.
  List<List<Map<String, dynamic>>> toJson() {
    return _grid.map((row) => row.map((cell) => cell.toJson()).toList()).toList();
  }

  /// Deserializes matrix from JSON.
  factory AttentionHeatmapMatrix.fromJson(List<dynamic> json) {
    final grid = json.map((rowRaw) {
      final row = rowRaw as List<dynamic>;
      return row.map((cellRaw) => HeatmapCell.fromJson(cellRaw as Map<String, dynamic>)).toList();
    }).toList();
    return AttentionHeatmapMatrix._(grid);
  }

  /// Helper to get day name from 1..7
  static String getDayName(int dayOfWeek) {
    switch (dayOfWeek) {
      case 1: return 'Mon';
      case 2: return 'Tue';
      case 3: return 'Wed';
      case 4: return 'Thu';
      case 5: return 'Fri';
      case 6: return 'Sat';
      case 7: return 'Sun';
      default: return 'Day';
    }
  }
}
