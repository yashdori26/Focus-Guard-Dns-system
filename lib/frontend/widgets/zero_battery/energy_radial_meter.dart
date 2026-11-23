import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Interactive custom radial gauge displaying real-time power consumption and daily drain projection.
class EnergyRadialMeter extends StatelessWidget {
  final double dailyDrainPercentage;
  final double currentDrawMicroamps;
  final double maxBudgetPercentage;

  const EnergyRadialMeter({
    super.key,
    required this.dailyDrainPercentage,
    required this.currentDrawMicroamps,
    this.maxBudgetPercentage = 1.0,
  });

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final bool isOptimal = dailyDrainPercentage <= maxBudgetPercentage;
    final Color accentColor = isOptimal
        ? const Color(0xFF2ECC71)
        : const Color(0xFFE74C3C);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: 220,
          height: 130,
          child: CustomPaint(
            painter: _RadialArcPainter(
              dailyDrainPercentage: dailyDrainPercentage,
              maxBudgetPercentage: maxBudgetPercentage,
              isDark: isDark,
              accentColor: accentColor,
            ),
            child: Align(
              alignment: Alignment.bottomCenter,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '${dailyDrainPercentage.toStringAsFixed(2)}%',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 32,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -1,
                      color: isDark ? Colors.white : Colors.black87,
                    ),
                  ),
                  Text(
                    'ESTIMATED / 24H',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.2,
                      color: isDark ? Colors.white54 : Colors.black45,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          decoration: BoxDecoration(
            color: accentColor.withOpacity(0.12),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: accentColor.withOpacity(0.3)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.bolt_rounded, size: 14, color: accentColor),
              const SizedBox(width: 4),
              Text(
                '${currentDrawMicroamps.toStringAsFixed(0)} µA CURRENT DRAW',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: accentColor,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _RadialArcPainter extends CustomPainter {
  final double dailyDrainPercentage;
  final double maxBudgetPercentage;
  final bool isDark;
  final Color accentColor;

  _RadialArcPainter({
    required this.dailyDrainPercentage,
    required this.maxBudgetPercentage,
    required this.isDark,
    required this.accentColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height);
    final radius = size.width * 0.45;
    const startAngle = math.pi;
    const sweepAngle = math.pi;

    // Track Paint
    final trackPaint = Paint()
      ..color = isDark ? const Color(0xFF2C2C2E) : const Color(0xFFE5E5EA)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 14
      ..strokeCap = StrokeCap.round;

    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      startAngle,
      sweepAngle,
      false,
      trackPaint,
    );

    // Progress Arc
    final double normalizedProgress = (dailyDrainPercentage / (maxBudgetPercentage * 2.0)).clamp(0.0, 1.0);
    final progressPaint = Paint()
      ..color = accentColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 14
      ..strokeCap = StrokeCap.round;

    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      startAngle,
      sweepAngle * normalizedProgress,
      false,
      progressPaint,
    );
  }

  @override
  bool shouldRepaint(covariant _RadialArcPainter oldDelegate) {
    return oldDelegate.dailyDrainPercentage != dailyDrainPercentage ||
        oldDelegate.isDark != isDark;
  }
}
