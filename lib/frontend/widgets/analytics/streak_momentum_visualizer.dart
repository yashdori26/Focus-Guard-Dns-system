import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../../engine/analytics/streak_momentum_calculator.dart';

/// Visualizer widget rendering streak flame, momentum arc meter, and 52-week focus matrix.
class StreakMomentumVisualizer extends StatelessWidget {
  final StreakRecord streakRecord;
  final double momentumScore;

  const StreakMomentumVisualizer({
    super.key,
    required this.streakRecord,
    required this.momentumScore,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 1. Hero Streak & Circular Arc Row
        Row(
          children: [
            // Circular Arc Gauge
            SizedBox(
              width: 100,
              height: 100,
              child: CustomPaint(
                painter: _MomentumArcPainter(score: momentumScore),
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '${momentumScore.toInt()}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 24,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.5,
                        ),
                      ),
                      Text(
                        'MOMENTUM',
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.5),
                          fontSize: 8,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(width: 20),
            // Streak Flame and Meta
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Text('🔥', style: TextStyle(fontSize: 28)),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '${streakRecord.currentStreakDays} Days',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 22,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.5,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Best: ${streakRecord.longestStreakDays} Days • ${streakRecord.freezeTokensRemaining} Freeze Tokens Left',
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.6),
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),

        // 2. 52-Week Focus Habit Grid
        Text(
          'ANNUAL FOCUS HABIT MATRIX',
          style: TextStyle(
            color: Colors.white.withOpacity(0.5),
            fontSize: 10,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.8,
          ),
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: 100,
          child: CustomPaint(
            size: const Size(double.infinity, 100),
            painter: _CommitMatrixPainter(record: streakRecord),
          ),
        ),
      ],
    );
  }
}

class _MomentumArcPainter extends CustomPainter {
  final double score;

  _MomentumArcPainter({required this.score});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (size.width / 2) - 8.0;

    final bgPaint = Paint()
      ..color = Colors.white.withOpacity(0.08)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 7.0;

    canvas.drawCircle(center, radius, bgPaint);

    final sweepAngle = (score / 100.0) * 2 * math.pi;
    final arcPaint = Paint()
      ..shader = const LinearGradient(
        colors: [Color(0xFFFF9F1C), Color(0xFF00E699)],
      ).createShader(Rect.fromCircle(center: center, radius: radius))
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 7.0;

    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -math.pi / 2,
      sweepAngle,
      false,
      arcPaint,
    );
  }

  @override
  bool shouldRepaint(covariant _MomentumArcPainter oldDelegate) {
    return oldDelegate.score != score;
  }
}

class _CommitMatrixPainter extends CustomPainter {
  final StreakRecord record;

  _CommitMatrixPainter({required this.record});

  @override
  void paint(Canvas canvas, Size size) {
    const numCols = 36; // Show last 36 weeks for responsive mobile width
    const numRows = 7;
    final cellWidth = (size.width - ((numCols - 1) * 2.5)) / numCols;
    const cellHeight = 9.0;
    const spacing = 2.5;

    final basePaint = Paint()..style = PaintingStyle.fill;

    for (int col = 0; col < numCols; col++) {
      for (int row = 0; row < numRows; row++) {
        final x = col * (cellWidth + spacing);
        final y = row * (cellHeight + spacing);

        final rect = RRect.fromRectAndRadius(
          Rect.fromLTWH(x, y, cellWidth, cellHeight),
          const Radius.circular(2.0),
        );

        // Simulation of daily density
        final hash = (col * 7 + row + record.currentStreakDays) % 10;
        Color color;
        if (hash >= 7) {
          color = const Color(0xFF00E699); // Full focus
        } else if (hash >= 5) {
          color = const Color(0xFF00E699).withOpacity(0.65);
        } else if (hash >= 3) {
          color = const Color(0xFF00E699).withOpacity(0.35);
        } else {
          color = Colors.white.withOpacity(0.04);
        }

        basePaint.color = color;
        canvas.drawRRect(rect, basePaint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _CommitMatrixPainter oldDelegate) {
    return oldDelegate.record != record;
  }
}
