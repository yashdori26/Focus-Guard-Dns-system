import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../../engine/analytics/dopamine_rehabilitation_historian.dart';

/// Interactive chart displaying predicted dopamine receptor sensitivity recovery over 30 days.
class DopamineRecoveryCurveChart extends StatelessWidget {
  final int currentDaysClean;

  const DopamineRecoveryCurveChart({
    super.key,
    required this.currentDaysClean,
  });

  @override
  Widget build(BuildContext context) {
    final currentStage = DopamineRehabilitationHistorian.getStageForDays(currentDaysClean);
    final currentSensitivity = DopamineRehabilitationHistorian.calculateReceptorSensitivity(currentDaysClean);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Stage Header & Metric
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    currentStage.title.toUpperCase(),
                    style: const TextStyle(
                      color: Color(0xFF00E699),
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.5,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${currentSensitivity.toStringAsFixed(1)}% Receptor Sensitivity',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: const Color(0xFF00E699).withOpacity(0.12),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFF00E699).withOpacity(0.3)),
              ),
              child: Text(
                'Day $currentDaysClean of 30',
                style: const TextStyle(
                  color: Color(0xFF00E699),
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),

        // Custom Canvas Chart
        SizedBox(
          height: 160,
          width: double.infinity,
          child: CustomPaint(
            painter: _RecoveryCurvePainter(currentDay: currentDaysClean),
          ),
        ),
        const SizedBox(height: 8),

        // Stage description
        Text(
          currentStage.description,
          style: TextStyle(
            color: Colors.white.withOpacity(0.65),
            fontSize: 11,
            height: 1.4,
          ),
        ),
      ],
    );
  }
}

class _RecoveryCurvePainter extends CustomPainter {
  final int currentDay;

  _RecoveryCurvePainter({required this.currentDay});

  @override
  void paint(Canvas canvas, Size size) {
    const leftMargin = 32.0;
    const rightMargin = 16.0;
    const topMargin = 20.0;
    const bottomMargin = 24.0;

    final plotWidth = size.width - leftMargin - rightMargin;
    final plotHeight = size.height - topMargin - bottomMargin;

    // 1. Draw horizontal grid lines (25%, 50%, 75%, 100%)
    final gridPaint = Paint()
      ..color = Colors.white.withOpacity(0.06)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;

    final textStyle = TextStyle(
      color: Colors.white.withOpacity(0.35),
      fontSize: 9.0,
      fontWeight: FontWeight.w500,
    );

    for (int p = 25; p <= 100; p += 25) {
      final y = topMargin + plotHeight * (1.0 - (p / 100.0));
      canvas.drawLine(Offset(leftMargin, y), Offset(size.width - rightMargin, y), gridPaint);

      final textSpan = TextSpan(text: '$p%', style: textStyle);
      final textPainter = TextPainter(
        text: textSpan,
        textDirection: TextDirection.ltr,
      )..layout();
      textPainter.paint(canvas, Offset(leftMargin - textPainter.width - 4.0, y - (textPainter.height / 2)));
    }

    // 2. Draw Day Markers along bottom
    for (int day = 0; day <= 30; day += 10) {
      final x = leftMargin + (day / 30.0) * plotWidth;
      final textSpan = TextSpan(text: 'D$day', style: textStyle);
      final textPainter = TextPainter(
        text: textSpan,
        textDirection: TextDirection.ltr,
      )..layout();
      textPainter.paint(canvas, Offset(x - (textPainter.width / 2), size.height - bottomMargin + 6.0));
    }

    // 3. Build Curve Path
    final curvePath = Path();
    final fillPath = Path();
    fillPath.moveTo(leftMargin, topMargin + plotHeight);

    Offset? currentDayPoint;

    for (double t = 0; t <= 30; t += 0.5) {
      final x = leftMargin + (t / 30.0) * plotWidth;
      final sensitivity = DopamineRehabilitationHistorian.calculateReceptorSensitivity(t.toInt());
      final y = topMargin + plotHeight * (1.0 - (sensitivity / 100.0));

      if (t == 0) {
        curvePath.moveTo(x, y);
      } else {
        curvePath.lineTo(x, y);
      }
      fillPath.lineTo(x, y);

      if ((t - currentDay).abs() < 0.3 && currentDayPoint == null) {
        currentDayPoint = Offset(x, y);
      }
    }

    fillPath.lineTo(leftMargin + plotWidth, topMargin + plotHeight);
    fillPath.close();

    // 4. Paint Gradient Fill
    final gradient = LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [
        const Color(0xFF00E699).withOpacity(0.35),
        const Color(0xFF00E699).withOpacity(0.0),
      ],
    );
    final fillPaint = Paint()
      ..shader = gradient.createShader(Rect.fromLTWH(leftMargin, topMargin, plotWidth, plotHeight))
      ..style = PaintingStyle.fill;
    canvas.drawPath(fillPath, fillPaint);

    // 5. Paint Curve Line
    final linePaint = Paint()
      ..color = const Color(0xFF00E699)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round;
    canvas.drawPath(curvePath, linePaint);

    // 6. Draw Current Day Pin Marker
    if (currentDayPoint != null) {
      final pinPaint = Paint()
        ..color = const Color(0xFFFF9F1C)
        ..style = PaintingStyle.fill;
      canvas.drawCircle(currentDayPoint, 5.0, pinPaint);

      final outerRingPaint = Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.0;
      canvas.drawCircle(currentDayPoint, 5.0, outerRingPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _RecoveryCurvePainter oldDelegate) {
    return oldDelegate.currentDay != currentDay;
  }
}
