import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'longitudinal_time_period.dart';
import 'session_lifecycle_metrics.dart';
import 'streak_momentum_calculator.dart';
import 'attention_heatmap_matrix.dart';
import 'dopamine_rehabilitation_historian.dart';

/// Persistent time-series storage and aggregation engine for longitudinal metrics.
class AnalyticsPersistenceStore {
  static const String keyPrefixRollups = 'focusdns_daily_rollup_';
  static const String keyStreakRecord = 'focusdns_streak_record_v2';
  static const String keyHeatmapMatrix = 'focusdns_heatmap_matrix_v2';

  final SharedPreferences? _prefs;
  final Map<String, SessionLifecycleMetrics> _inMemoryRollups = {};
  StreakRecord _streakRecord = StreakRecord.initial();
  AttentionHeatmapMatrix _heatmapMatrix = AttentionHeatmapMatrix.empty();

  AnalyticsPersistenceStore([this._prefs]);

  /// Factory creating an initialized store from SharedPreferences.
  static Future<AnalyticsPersistenceStore> create() async {
    final prefs = await SharedPreferences.getInstance();
    final store = AnalyticsPersistenceStore(prefs);
    await store.loadAll();
    return store;
  }

  /// Loads all stored rollups, streak record, and heatmap matrix into memory.
  Future<void> loadAll() async {
    if (_prefs == null) return;

    // 1. Streak Record
    final streakJsonStr = _prefs!.getString(keyStreakRecord);
    if (streakJsonStr != null) {
      try {
        final map = jsonDecode(streakJsonStr) as Map<String, dynamic>;
        _streakRecord = StreakRecord.fromJson(map);
      } catch (_) {}
    }

    // 2. Heatmap Matrix
    final heatmapJsonStr = _prefs!.getString(keyHeatmapMatrix);
    if (heatmapJsonStr != null) {
      try {
        final list = jsonDecode(heatmapJsonStr) as List<dynamic>;
        _heatmapMatrix = AttentionHeatmapMatrix.fromJson(list);
      } catch (_) {}
    }

    // 3. Rollups
    final keys = _prefs!.getKeys().where((k) => k.startsWith(keyPrefixRollups));
    for (final k in keys) {
      final jsonStr = _prefs!.getString(k);
      if (jsonStr != null) {
        try {
          final map = jsonDecode(jsonStr) as Map<String, dynamic>;
          final dateKey = k.replaceFirst(keyPrefixRollups, '');
          _inMemoryRollups[dateKey] = SessionLifecycleMetrics.fromJson(map);
        } catch (_) {}
      }
    }
  }

  // =========================================================================
  // 1. DATA RECORDING
  // =========================================================================

  /// Persists or updates the daily rollup for a given [date].
  Future<void> recordDailyMetrics(DateTime date, SessionLifecycleMetrics metrics) async {
    final key = _formatDateKey(date);
    final existing = _inMemoryRollups[key];
    final merged = existing != null ? existing.merge(metrics) : metrics;
    _inMemoryRollups[key] = merged;

    if (_prefs != null) {
      await _prefs!.setString('$keyPrefixRollups$key', jsonEncode(merged.toJson()));
    }
  }

  /// Updates and persists the streak record.
  Future<void> saveStreakRecord(StreakRecord record) async {
    _streakRecord = record;
    if (_prefs != null) {
      await _prefs!.setString(keyStreakRecord, jsonEncode(record.toJson()));
    }
  }

  /// Updates and persists the attention heatmap matrix.
  Future<void> saveHeatmapMatrix(AttentionHeatmapMatrix matrix) async {
    _heatmapMatrix = matrix;
    if (_prefs != null) {
      await _prefs!.setString(keyHeatmapMatrix, jsonEncode(matrix.toJson()));
    }
  }

  StreakRecord get streakRecord => _streakRecord;
  AttentionHeatmapMatrix get heatmapMatrix => _heatmapMatrix;

  // =========================================================================
  // 2. AGGREGATION & PERIOD QUERIES
  // =========================================================================

  /// Aggregates all daily metrics within the specified [period] relative to [referenceDate].
  SessionLifecycleMetrics getMetricsForPeriod(LongitudinalTimePeriod period, [DateTime? referenceDate]) {
    final range = LongitudinalPeriodHelper.calculateRange(period, referenceDate);
    var aggregated = SessionLifecycleMetrics.empty();

    for (final entry in _inMemoryRollups.entries) {
      final date = DateTime.tryParse(entry.key);
      if (date != null && range.contains(date)) {
        aggregated = aggregated.merge(entry.value);
      }
    }

    return aggregated;
  }

  /// Returns raw daily rollup metrics mapped by 'YYYY-MM-DD'.
  Map<String, SessionLifecycleMetrics> getAllRollups() {
    return Map.unmodifiable(_inMemoryRollups);
  }

  // =========================================================================
  // 3. EXPORT ENGINE (JSON, CSV, MARKDOWN)
  // =========================================================================

  /// Exports complete analytics snapshot as JSON string.
  String exportJson() {
    final data = {
      'exportedAt': DateTime.now().toIso8601String(),
      'streakRecord': _streakRecord.toJson(),
      'heatmapMatrix': _heatmapMatrix.toJson(),
      'rollups': _inMemoryRollups.map((k, v) => MapEntry(k, v.toJson())),
    };
    return const JsonEncoder.withIndent('  ').convert(data);
  }

  /// Exports daily metrics table as CSV string.
  String exportCsv() {
    final buffer = StringBuffer();
    buffer.writeln('Date,Initiated,Completed,Aborted,FocusMinutes,BreakMinutes,TrapsSevered,BytesSaved,AdherenceRate');

    final sortedKeys = _inMemoryRollups.keys.toList()..sort();
    for (final k in sortedKeys) {
      final m = _inMemoryRollups[k]!;
      buffer.writeln(
        '$k,${m.sessionsInitiated},${m.sessionsCompleted},${m.sessionsAborted},'
        '${m.totalFocusMinutes},${m.totalBreakMinutes},${m.totalDistractionInterceptions},'
        '${m.bandwidthBytesSaved},${m.adherenceRate.toStringAsFixed(1)}%',
      );
    }

    return buffer.toString();
  }

  /// Exports human-readable executive Markdown report.
  String exportMarkdownReport(LongitudinalTimePeriod period) {
    final metrics = getMetricsForPeriod(period);
    final range = LongitudinalPeriodHelper.calculateRange(period);
    final stage = DopamineRehabilitationHistorian.getStageForDays(_streakRecord.currentStreakDays);
    final tangible = DopamineRehabilitationHistorian.calculateTangibleEquivalents(metrics.totalFocusMinutes);

    final buffer = StringBuffer();
    buffer.writeln('# FocusDNS Focus & Dopamine Audit Report');
    buffer.writeln('**Horizon**: ${LongitudinalPeriodHelper.getTitle(period)} (${range.start.toLocal().toString().split(' ')[0]} to ${range.end.toLocal().toString().split(' ')[0]})');
    buffer.writeln('**Generated**: ${DateTime.now().toIso8601String()}\n');

    buffer.writeln('## Executive Summary');
    buffer.writeln('- **Total Reclaimed Hours**: ${metrics.totalHoursReclaimed.toStringAsFixed(1)} hrs');
    buffer.writeln('- **Session Adherence Rate**: ${metrics.adherenceRate.toStringAsFixed(1)}% (${metrics.sessionsCompleted}/${metrics.sessionsInitiated} completed)');
    buffer.writeln('- **Distraction Traps Severed**: ${metrics.totalDistractionInterceptions}');
    buffer.writeln('- **Current Habit Streak**: ${_streakRecord.currentStreakDays} Days (Best: ${_streakRecord.longestStreakDays} Days)');
    buffer.writeln('- **Dopamine Rehabilitation Stage**: ${stage.title} (${stage.neurochemicalState})\n');

    buffer.writeln('## Tangible Real-World Equivalents');
    buffer.writeln('- 📚 **Books Read Equivalent**: ${tangible.booksReadEquivalent.toStringAsFixed(1)} books');
    buffer.writeln('- 🎯 **Deep Work 90m Cycles**: ${tangible.deepWorkBlocks.toStringAsFixed(1)} blocks');
    buffer.writeln('- 🎓 **Full Courses Completed**: ${tangible.coursesCompleted.toStringAsFixed(1)} courses');
    buffer.writeln('- 🌙 **Sleep Quality Boost**: +${tangible.lateNightSleepQualityBoost.toStringAsFixed(1)}%\n');

    buffer.writeln('## Next Milestone Target');
    final nextMilestone = StreakMomentumCalculator.getNextMilestone(_streakRecord.currentStreakDays);
    if (nextMilestone != null) {
      final daysRemaining = StreakMomentumCalculator.daysUntilNextMilestone(_streakRecord.currentStreakDays);
      buffer.writeln('Targeting **${nextMilestone.title}** (${nextMilestone.icon}) in $daysRemaining days.');
    } else {
      buffer.writeln('All streak milestones achieved! Dopamine Sovereignty attained.');
    }

    return buffer.toString();
  }

  static String _formatDateKey(DateTime dt) {
    final y = dt.year.toString().padLeft(4, '0');
    final m = dt.month.toString().padLeft(2, '0');
    final d = dt.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }
}
