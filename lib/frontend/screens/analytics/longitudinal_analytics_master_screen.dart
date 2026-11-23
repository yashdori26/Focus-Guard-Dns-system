import 'package:flutter/material.dart';
import '../../../engine/analytics/longitudinal_time_period.dart';
import '../../../engine/analytics/session_lifecycle_metrics.dart';
import '../../../engine/analytics/streak_momentum_calculator.dart';
import '../../../engine/analytics/attention_heatmap_matrix.dart';
import '../../../engine/analytics/analytics_persistence_store.dart';
import '../../widgets/analytics/attention_heatmap_canvas.dart';
import '../../widgets/analytics/streak_momentum_visualizer.dart';
import '../../widgets/analytics/dopamine_recovery_curve_chart.dart';

/// Master studio displaying multi-horizon focus telemetry, 7x24 attention heatmaps,
/// dopamine receptor recovery curves, and streak momentum.
class LongitudinalAnalyticsMasterScreen extends StatefulWidget {
  final AnalyticsPersistenceStore store;

  const LongitudinalAnalyticsMasterScreen({
    super.key,
    required this.store,
  });

  @override
  State<LongitudinalAnalyticsMasterScreen> createState() => _LongitudinalAnalyticsMasterScreenState();
}

class _LongitudinalAnalyticsMasterScreenState extends State<LongitudinalAnalyticsMasterScreen> {
  LongitudinalTimePeriod _selectedPeriod = LongitudinalTimePeriod.week;

  @override
  Widget build(BuildContext context) {
    final metrics = widget.store.getMetricsForPeriod(_selectedPeriod);
    final streakRecord = widget.store.streakRecord;
    final heatmapMatrix = widget.store.heatmapMatrix;
    final momentum = StreakMomentumCalculator.calculateMomentumScore(streakRecord);
    final topPeaks = heatmapMatrix.findPeakVulnerabilityHours(3);

    return Scaffold(
      backgroundColor: const Color(0xFF0E0E12),
      appBar: AppBar(
        backgroundColor: const Color(0xFF14141A),
        elevation: 0,
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Longitudinal Analytics',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: Colors.white),
            ),
            Text(
              'Neurobiological Focus & Dopamine Restoration',
              style: TextStyle(fontSize: 11, color: Colors.white54),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.share, size: 20, color: Color(0xFF00E699)),
            tooltip: 'Export Audit Report',
            onPressed: () => _showExportOptionsModal(context),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // 1. Time Horizon Filter Tabs
          _buildHorizonFilterBar(),
          const SizedBox(height: 16),

          // 2. Hero KPI Cards
          _buildHeroKpiGrid(metrics),
          const SizedBox(height: 20),

          // 3. 7x24 Cognitive Attention Heatmap
          _buildHeatmapSection(heatmapMatrix, topPeaks),
          const SizedBox(height: 20),

          // 4. Dopamine Receptor Recovery Curve
          _buildDopamineCurveSection(streakRecord.currentStreakDays),
          const SizedBox(height: 20),

          // 5. Streak Momentum & 52-Week Commit Matrix
          _buildStreakMomentumSection(streakRecord, momentum),
          const SizedBox(height: 24),

          // 6. Export Report Action Card
          _buildExportCard(context),
        ],
      ),
    );
  }

  Widget _buildHorizonFilterBar() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: LongitudinalTimePeriod.values.map((period) {
          final isSelected = _selectedPeriod == period;
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: ChoiceChip(
              label: Text(LongitudinalPeriodHelper.getTabLabel(period)),
              selected: isSelected,
              selectedColor: const Color(0xFF00E699),
              backgroundColor: const Color(0xFF1A1A22),
              labelStyle: TextStyle(
                color: isSelected ? Colors.black : Colors.white,
                fontWeight: FontWeight.w700,
                fontSize: 12,
              ),
              onSelected: (selected) {
                if (selected) setState(() => _selectedPeriod = period);
              },
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildHeroKpiGrid(SessionLifecycleMetrics metrics) {
    return Row(
      children: [
        Expanded(
          child: _buildMetricTile(
            'HOURS RECLAIMED',
            '${metrics.totalHoursReclaimed.toStringAsFixed(1)}h',
            const Color(0xFF00E699),
            '${metrics.sessionsCompleted} sessions finished',
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _buildMetricTile(
            'ADHERENCE RATE',
            '${metrics.adherenceRate.toStringAsFixed(1)}%',
            const Color(0xFF0095F6),
            '${metrics.breakOvershootsPrevented} breaks guarded',
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _buildMetricTile(
            'TRAPS SEVERED',
            '${metrics.totalDistractionInterceptions}',
            const Color(0xFFFF9F1C),
            '${metrics.megabytesSaved.toStringAsFixed(0)}MB video saved',
          ),
        ),
      ],
    );
  }

  Widget _buildMetricTile(String title, String value, Color accentColor, String subtitle) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF16161E),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withOpacity(0.06)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              color: Colors.white.withOpacity(0.45),
              fontSize: 9,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: TextStyle(
              color: accentColor,
              fontSize: 20,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            style: TextStyle(
              color: Colors.white.withOpacity(0.55),
              fontSize: 10,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeatmapSection(AttentionHeatmapMatrix matrix, List<HeatmapCell> topPeaks) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFF16161E),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withOpacity(0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Expanded(
                child: Text(
                  '7x24 COGNITIVE VULNERABILITY HEATMAP',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.8,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: const Color(0xFFFF3B5C).withOpacity(0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Text(
                  'Distraction Peaks',
                  style: TextStyle(color: Color(0xFFFF3B5C), fontSize: 10, fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),

          // Canvas Heatmap
          AttentionHeatmapCanvas(matrix: matrix),
          const SizedBox(height: 14),

          // Peak Callout Tags
          if (topPeaks.isNotEmpty) ...[
            Text(
              'Identified High-Risk Temptation Windows:',
              style: TextStyle(color: Colors.white.withOpacity(0.6), fontSize: 11, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: topPeaks.map((peak) {
                final dayName = AttentionHeatmapMatrix.getDayName(peak.dayOfWeek);
                final hourStr = '${peak.hourOfDay.toString().padLeft(2, '0')}:00';
                return Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFF3B5C).withOpacity(0.12),
                    border: Border.all(color: const Color(0xFFFF3B5C).withOpacity(0.3)),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '⚠️ $dayName at $hourStr (${peak.interceptionCount} traps severed)',
                    style: const TextStyle(color: Color(0xFFFF3B5C), fontSize: 11, fontWeight: FontWeight.w600),
                  ),
                );
              }).toList(),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildDopamineCurveSection(int daysClean) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFF16161E),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withOpacity(0.08)),
      ),
      child: DopamineRecoveryCurveChart(currentDaysClean: daysClean),
    );
  }

  Widget _buildStreakMomentumSection(StreakRecord record, double momentum) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFF16161E),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withOpacity(0.08)),
      ),
      child: StreakMomentumVisualizer(
        streakRecord: record,
        momentumScore: momentum,
      ),
    );
  }

  Widget _buildExportCard(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            const Color(0xFF181822),
            const Color(0xFF14141B),
          ],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(0.08)),
      ),
      child: Row(
        children: [
          const Text('📄', style: TextStyle(fontSize: 28)),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Export Clinical Focus Audit',
                  style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 2),
                Text(
                  'Download verified CSV session log or Markdown report for your accountability partner.',
                  style: TextStyle(color: Colors.white.withOpacity(0.55), fontSize: 11),
                ),
              ],
            ),
          ),
          ElevatedButton(
            onPressed: () => _showExportOptionsModal(context),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF00E699),
              foregroundColor: Colors.black,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            ),
            child: const Text('Export', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }

  void _showExportOptionsModal(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1A1A22),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Export Audit Report',
                style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 8),
              Text(
                'Select output format for longitudinal metrics:',
                style: TextStyle(color: Colors.white.withOpacity(0.6), fontSize: 13),
              ),
              const SizedBox(height: 18),
              ListTile(
                leading: const Text('📊', style: TextStyle(fontSize: 22)),
                title: const Text('CSV Matrix', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                subtitle: const Text('Tabular daily session logs with adherence ratios', style: TextStyle(color: Colors.white54, fontSize: 12)),
                onTap: () {
                  Navigator.of(ctx).pop();
                  final csv = widget.store.exportCsv();
                  _showReportViewer(context, 'CSV Audit Log', csv);
                },
              ),
              ListTile(
                leading: const Text('📝', style: TextStyle(fontSize: 22)),
                title: const Text('Markdown Focus Audit', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                subtitle: const Text('Formatted executive summary with tangible equivalents', style: TextStyle(color: Colors.white54, fontSize: 12)),
                onTap: () {
                  Navigator.of(ctx).pop();
                  final md = widget.store.exportMarkdownReport(_selectedPeriod);
                  _showReportViewer(context, 'Executive Markdown Audit', md);
                },
              ),
              ListTile(
                leading: const Text('📦', style: TextStyle(fontSize: 22)),
                title: const Text('Full JSON Snapshot', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                subtitle: const Text('Raw machine-readable state backup', style: TextStyle(color: Colors.white54, fontSize: 12)),
                onTap: () {
                  Navigator.of(ctx).pop();
                  final jsonStr = widget.store.exportJson();
                  _showReportViewer(context, 'JSON Snapshot', jsonStr);
                },
              ),
            ],
          ),
        );
      },
    );
  }

  void _showReportViewer(BuildContext context, String title, String content) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF16161E),
        title: Text(title, style: const TextStyle(color: Colors.white, fontSize: 16)),
        content: SizedBox(
          width: double.maxFinite,
          height: 350,
          child: SingleChildScrollView(
            child: SelectableText(
              content,
              style: const TextStyle(color: Colors.white70, fontSize: 12, fontFamily: 'monospace'),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Close', style: TextStyle(color: Color(0xFF00E699))),
          ),
        ],
      ),
    );
  }
}
