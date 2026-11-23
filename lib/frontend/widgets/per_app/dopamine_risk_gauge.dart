import 'dart:math';
import 'package:flutter/material.dart';

/// Custom canvas painter rendering an animated radial arc for dopamine addiction risk (0-100).
class DopamineRiskGauge extends StatelessWidget {
  final int score; // 0 to 100
  final double size;
  final bool showLabel;

  const DopamineRiskGauge({
    super.key,
    required this.score,
    this.size = 80,
    this.showLabel = true,
  });

  Color _getRiskColor() {
    if (score >= 95) return const Color(0xFFFF2A54);
    if (score >= 85) return const Color(0xFFF97316);
    if (score >= 70) return const Color(0xFFFBBF24);
    if (score >= 40) return const Color(0xFF3B82F6);
    return const Color(0xFF10B981);
  }

  String _getRiskCategory() {
    if (score >= 95) return 'EXTREME TRAP';
    if (score >= 85) return 'VERY HIGH';
    if (score >= 70) return 'HIGH RISK';
    if (score >= 40) return 'MODERATE';
    return 'MINIMAL';
  }

  @override
  Widget build(BuildContext context) {
    final color = _getRiskColor();

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: size,
          height: size,
          child: CustomPaint(
            painter: _GaugePainter(
              score: score.clamp(0, 100),
              activeColor: color,
              trackColor: Colors.white.withValues(alpha: 0.1),
            ),
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    '$score',
                    style: TextStyle(
                      color: color,
                      fontWeight: FontWeight.bold,
                      fontSize: size * 0.28,
                    ),
                  ),
                  Text(
                    'RISK',
                    style: TextStyle(
                      color: Colors.white54,
                      fontSize: size * 0.12,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.8,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        if (showLabel) ...[
          const SizedBox(height: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: color.withValues(alpha: 0.4), width: 0.8),
            ),
            child: Text(
              _getRiskCategory(),
              style: TextStyle(
                color: color,
                fontSize: 10,
                fontWeight: FontWeight.bold,
                letterSpacing: 0.5,
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _GaugePainter extends CustomPainter {
  final int score;
  final Color activeColor;
  final Color trackColor;

  _GaugePainter({
    required this.score,
    required this.activeColor,
    required this.trackColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (min(size.width, size.height) - 8) / 2;
    const startAngle = 135 * (pi / 180);
    const sweepAngle = 270 * (pi / 180);

    final trackPaint = Paint()
      ..color = trackColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 6.0
      ..strokeCap = StrokeCap.round;

    final activePaint = Paint()
      ..color = activeColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 6.0
      ..strokeCap = StrokeCap.round;

    // Draw background track arc
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      startAngle,
      sweepAngle,
      false,
      trackPaint,
    );

    // Draw active score arc
    final currentSweep = sweepAngle * (score / 100.0);
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      startAngle,
      currentSweep,
      false,
      activePaint,
    );
  }

  @override
  bool shouldRepaint(covariant _GaugePainter oldDelegate) {
    return oldDelegate.score != score || oldDelegate.activeColor != activeColor;
  }
}
