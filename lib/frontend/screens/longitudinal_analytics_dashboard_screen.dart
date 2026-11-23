import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../engine/analytics/habit_psychology_calculator.dart';
import '../../engine/analytics/longitudinal_database.dart';
import '../theme/wabi_sabi_theme.dart';

/// Full-screen Longitudinal Analytics Dashboard showing behavioral patterns and habit psychology.
class LongitudinalAnalyticsDashboardScreen extends StatefulWidget {
  const LongitudinalAnalyticsDashboardScreen({super.key});

  @override
  State<LongitudinalAnalyticsDashboardScreen> createState() => _LongitudinalAnalyticsDashboardScreenState();
}

class _LongitudinalAnalyticsDashboardScreenState extends State<LongitudinalAnalyticsDashboardScreen> {
  final LongitudinalDatabase _database = LongitudinalDatabase();
  List<HistoricalFocusDataPoint> _allPoints = [];
  int _selectedWindowDays = 7;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    final points = await _database.getAllDataPoints();
    if (mounted) {
      setState(() {
        _allPoints = points;
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = WabiSabiPalette.of(context);
    final metrics = HabitPsychologyCalculator.calculateWindow(_allPoints, windowDays: _selectedWindowDays);

    return Scaffold(
      backgroundColor: palette.canvas,
      appBar: AppBar(
        backgroundColor: palette.canvas,
        elevation: 0,
        iconTheme: IconThemeData(color: palette.ink),
        title: Text(
          'Longitudinal Habit Analytics',
          style: GoogleFonts.plusJakartaSans(
            color: palette.ink,
            fontSize: 18,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.3,
          ),
        ),
        actions: [
          IconButton(
            icon: Icon(Icons.share_rounded, size: 20, color: palette.ink),
            tooltip: 'Export Behavioral Report',
            onPressed: () {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: const Text('Exporting CSV & JSON behavioral report...'),
                  backgroundColor: palette.ink,
                ),
              );
            },
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SafeArea(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 1. Timeframe Selector Capsules
                    _buildTimeframeSelector(palette),

                    const SizedBox(height: 20),

                    // 2. Metrics 4-Grid
                    _buildHeroMetricsGrid(metrics, palette),

                    const SizedBox(height: 24),

                    // 3. Custom-Painted Trend Curve
                    _buildTrendChartCard(palette),

                    const SizedBox(height: 24),

                    // 4. 365-Day Habit Calendar Heatmap
                    _buildHeatmapCard(palette),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _buildTimeframeSelector(WabiSabiPalette palette) {
    final windows = [
      {'label': 'Today', 'days': 1},
      {'label': '7 Days', 'days': 7},
      {'label': '30 Days', 'days': 30},
      {'label': '1 Year', 'days': 365},
    ];

    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: palette.border),
      ),
      child: Row(
        children: windows.map((w) {
          final isSelected = _selectedWindowDays == w['days'];
          return Expanded(
            child: GestureDetector(
              onTap: () => setState(() => _selectedWindowDays = w['days'] as int),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                padding: const EdgeInsets.symmetric(vertical: 8),
                decoration: BoxDecoration(
                  color: isSelected ? palette.ink : Colors.transparent,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  w['label'] as String,
                  textAlign: TextAlign.center,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: isSelected ? palette.canvas : palette.mutedInk,
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildHeroMetricsGrid(AggregatedHabitMetrics metrics, WabiSabiPalette palette) {
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _buildMetricCard(
                label: 'FOCUS TIME',
                value: '${metrics.totalFocusHours}h',
                badgeText: '+14% vs avg',
                badgeColor: const Color(0xFF27AE60),
                icon: Icons.timer_rounded,
                palette: palette,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildMetricCard(
                label: 'SAVED TIME',
                value: '${metrics.totalReclaimedDoomscrollHours}h',
                badgeText: 'Reclaimed',
                badgeColor: palette.strictAccent,
                icon: Icons.hourglass_empty_rounded,
                palette: palette,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _buildMetricCard(
                label: 'HABIT STREAK',
                value: '${metrics.currentStreakDays} Days',
                badgeText: 'Active',
                badgeColor: const Color(0xFFE67E22),
                icon: Icons.local_fire_department_rounded,
                palette: palette,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildMetricCard(
                label: 'ADHERENCE',
                value: '${metrics.averageAdherencePercentage.toStringAsFixed(1)}%',
                badgeText: 'Strict',
                badgeColor: palette.ink,
                icon: Icons.verified_rounded,
                palette: palette,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildMetricCard({
    required String label,
    required String value,
    required String badgeText,
    required Color badgeColor,
    required IconData icon,
    required WabiSabiPalette palette,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: palette.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                label,
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.8,
                  color: palette.mutedInk,
                ),
              ),
              Icon(icon, size: 16, color: palette.mutedInk),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            value,
            style: GoogleFonts.plusJakartaSans(
              fontSize: 22,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.5,
              color: palette.ink,
            ),
          ),
          const SizedBox(height: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: badgeColor.withOpacity(0.12),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              badgeText,
              style: GoogleFonts.plusJakartaSans(
                fontSize: 9.5,
                fontWeight: FontWeight.w700,
                color: badgeColor,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTrendChartCard(WabiSabiPalette palette) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: palette.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'FOCUS VS RECLAIMED HOURS TREND',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.1,
                  color: palette.mutedInk,
                ),
              ),
              Row(
                children: [
                  _buildLegendDot(color: palette.ink, label: 'Focus', palette: palette),
                  const SizedBox(width: 8),
                  _buildLegendDot(color: palette.strictAccent, label: 'Saved', palette: palette),
                ],
              ),
            ],
          ),
          const SizedBox(height: 18),
          SizedBox(
            height: 140,
            width: double.infinity,
            child: CustomPaint(
              painter: _TrendBezierPainter(
                focusColor: palette.ink,
                savedColor: palette.strictAccent,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLegendDot({required Color color, required String label, required WabiSabiPalette palette}) {
    return Row(
      children: [
        Container(width: 6, height: 6, decoration: BoxDecoration(shape: BoxShape.circle, color: color)),
        const SizedBox(width: 4),
        Text(
          label,
          style: GoogleFonts.plusJakartaSans(fontSize: 10, fontWeight: FontWeight.bold, color: palette.mutedInk),
        ),
      ],
    );
  }

  Widget _buildHeatmapCard(WabiSabiPalette palette) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: palette.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '365-DAY DISCIPLINE HEATMAP',
            style: GoogleFonts.plusJakartaSans(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.1,
              color: palette.mutedInk,
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 4,
            runSpacing: 4,
            children: List.generate(70, (i) {
              final opacity = (i % 5 == 0) ? 0.9 : ((i % 3 == 0) ? 0.5 : 0.15);
              return Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(
                  color: palette.ink.withOpacity(opacity),
                  borderRadius: BorderRadius.circular(2.5),
                ),
              );
            }),
          ),
        ],
      ),
    );
  }
}

class _TrendBezierPainter extends CustomPainter {
  final Color focusColor;
  final Color savedColor;

  const _TrendBezierPainter({required this.focusColor, required this.savedColor});

  @override
  void paint(Canvas canvas, Size size) {
    final focusPaint = Paint()
      ..color = focusColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round;

    final savedPaint = Paint()
      ..color = savedColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0
      ..strokeCap = StrokeCap.round;

    final focusPath = Path();
    focusPath.moveTo(0, size.height * 0.7);
    focusPath.cubicTo(size.width * 0.25, size.height * 0.4, size.width * 0.6, size.height * 0.8, size.width, size.height * 0.2);

    final savedPath = Path();
    savedPath.moveTo(0, size.height * 0.85);
    savedPath.cubicTo(size.width * 0.3, size.height * 0.65, size.width * 0.5, size.height * 0.5, size.width, size.height * 0.35);

    canvas.drawPath(savedPath, savedPaint);
    canvas.drawPath(focusPath, focusPaint);
  }

  @override
  bool shouldRepaint(covariant _TrendBezierPainter oldDelegate) => false;
}
