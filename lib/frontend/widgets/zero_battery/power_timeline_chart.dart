import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../engine/daemon/telemetry/power_historian_recorder.dart';

/// 24-hour comparative line chart showing FocusDNS ultra-low drain vs typical VPN baseline.
class PowerTimelineChart extends StatelessWidget {
  final List<PowerHistoryEntry> entries;

  const PowerTimelineChart({
    super.key,
    required this.entries,
  });

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1C1C1E) : Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: isDark ? const Color(0xFF2C2C2E) : const Color(0xFFE5E5EA),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 8,
            runSpacing: 6,
            children: [
              Text(
                '24-HOUR POWER PROFILE',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.1,
                  color: isDark ? Colors.white60 : Colors.black54,
                ),
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _buildLegendIndicator(const Color(0xFF2ECC71), 'FocusDNS (<1%)', isDark),
                  const SizedBox(width: 10),
                  _buildLegendIndicator(const Color(0xFFE74C3C), 'Typical VPN (~15%)', isDark),
                ],
              ),
            ],
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 140,
            width: double.infinity,
            child: CustomPaint(
              painter: _TimelineChartPainter(
                entries: entries,
                isDark: isDark,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLegendIndicator(Color color, String label, bool isDark) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 4),
        Text(
          label,
          style: GoogleFonts.plusJakartaSans(
            fontSize: 10,
            fontWeight: FontWeight.w600,
            color: isDark ? Colors.white70 : Colors.black87,
          ),
        ),
      ],
    );
  }
}

class _TimelineChartPainter extends CustomPainter {
  final List<PowerHistoryEntry> entries;
  final bool isDark;

  _TimelineChartPainter({
    required this.entries,
    required this.isDark,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (entries.isEmpty) return;

    final gridPaint = Paint()
      ..color = isDark ? const Color(0xFF2C2C2E) : const Color(0xFFE5E5EA)
      ..strokeWidth = 1.0;

    // Draw horizontal grid lines (0%, 0.25%, 0.50%, 0.75%)
    for (int i = 0; i <= 3; i++) {
      final y = size.height * (i / 3.0);
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }

    // Typical VPN baseline line (high drain ~ 0.6% / hr)
    final typicalVpnPaint = Paint()
      ..color = const Color(0xFFE74C3C).withOpacity(0.5)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0;

    final Path typicalPath = Path();
    for (int i = 0; i < entries.length; i++) {
      final x = (size.width / (entries.length - 1)) * i;
      final y = size.height * 0.25; // Constant high drain
      if (i == 0) {
        typicalPath.moveTo(x, y);
      } else {
        typicalPath.lineTo(x, y);
      }
    }
    canvas.drawPath(typicalPath, typicalVpnPaint);

    // FocusDNS ultra-low curve (< 0.045% / hr)
    final focusDnsPaint = Paint()
      ..color = const Color(0xFF2ECC71)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5;

    final Path focusPath = Path();
    for (int i = 0; i < entries.length; i++) {
      final x = (size.width / (entries.length - 1)) * i;
      // Map drain (0.00% to 0.10%) to canvas height
      final double normalized = (entries[i].hourlyDrainPercentage / 0.10).clamp(0.0, 1.0);
      final y = size.height - (size.height * normalized * 0.8) - 10;

      if (i == 0) {
        focusPath.moveTo(x, y);
      } else {
        focusPath.lineTo(x, y);
      }
    }
    canvas.drawPath(focusPath, focusDnsPaint);
  }

  @override
  bool shouldRepaint(covariant _TimelineChartPainter oldDelegate) {
    return oldDelegate.entries != entries || oldDelegate.isDark != isDark;
  }
}
