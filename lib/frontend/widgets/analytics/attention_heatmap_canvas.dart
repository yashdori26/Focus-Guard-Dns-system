import 'package:flutter/material.dart';
import '../../../engine/analytics/attention_heatmap_matrix.dart';

/// Interactive custom canvas painter rendering the 7-day x 24-hour cognitive attention matrix.
class AttentionHeatmapCanvas extends StatelessWidget {
  final AttentionHeatmapMatrix matrix;
  final void Function(HeatmapCell cell)? onCellTapped;

  const AttentionHeatmapCanvas({
    super.key,
    required this.matrix,
    this.onCellTapped,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        const height = 240.0;

        return SizedBox(
          width: width,
          height: height,
          child: CustomPaint(
            painter: _HeatmapPainter(matrix: matrix),
          ),
        );
      },
    );
  }
}

class _HeatmapPainter extends CustomPainter {
  final AttentionHeatmapMatrix matrix;

  _HeatmapPainter({required this.matrix});

  @override
  void paint(Canvas canvas, Size size) {
    const leftMargin = 38.0;
    const topMargin = 26.0;
    const bottomMargin = 16.0;

    final cellWidth = (size.width - leftMargin - 8.0) / 24.0;
    final cellHeight = (size.height - topMargin - bottomMargin) / 7.0;

    final hourLabelStyle = TextStyle(
      color: Colors.white.withOpacity(0.45),
      fontSize: 9.0,
      fontWeight: FontWeight.w500,
    );

    final dayLabelStyle = TextStyle(
      color: Colors.white.withOpacity(0.55),
      fontSize: 10.0,
      fontWeight: FontWeight.w600,
    );

    // 1. Draw Hour Labels (00, 04, 08, 12, 16, 20)
    for (int h = 0; h < 24; h += 4) {
      final x = leftMargin + (h * cellWidth) + (cellWidth / 2);
      final textSpan = TextSpan(text: '${h.toString().padLeft(2, '0')}:00', style: hourLabelStyle);
      final textPainter = TextPainter(
        text: textSpan,
        textDirection: TextDirection.ltr,
      )..layout();
      textPainter.paint(canvas, Offset(x - (textPainter.width / 2), 6.0));
    }

    // 2. Draw Day Labels (Mon, Tue, Wed, Thu, Fri, Sat, Sun)
    for (int d = 0; d < 7; d++) {
      final y = topMargin + (d * cellHeight) + (cellHeight / 2);
      final dayName = AttentionHeatmapMatrix.getDayName(d + 1);
      final textSpan = TextSpan(text: dayName, style: dayLabelStyle);
      final textPainter = TextPainter(
        text: textSpan,
        textDirection: TextDirection.ltr,
      )..layout();
      textPainter.paint(canvas, Offset(leftMargin - textPainter.width - 6.0, y - (textPainter.height / 2)));
    }

    // 3. Draw 7x24 Heatmap Grid Cells
    final cellPaint = Paint()..style = PaintingStyle.fill;
    final borderPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.5
      ..color = Colors.white.withOpacity(0.06);

    for (int d = 0; d < 7; d++) {
      for (int h = 0; h < 24; h++) {
        final cell = matrix.getCell(d + 1, h);
        final x = leftMargin + (h * cellWidth);
        final y = topMargin + (d * cellHeight);

        final rect = RRect.fromRectAndRadius(
          Rect.fromLTWH(x + 1.0, y + 1.0, cellWidth - 2.0, cellHeight - 2.0),
          const Radius.circular(3.0),
        );

        // Color coding:
        // High interceptions = Neon Vermilion Red
        // Moderate = Amber
        // Focus only = Neon Emerald Green
        // Blank = Dark gray
        Color cellColor;
        if (cell.interceptionCount > 0) {
          final intensity = (cell.interceptionCount / 10.0).clamp(0.25, 1.0);
          if (cell.interceptionCount >= 5) {
            cellColor = const Color(0xFFFF3B5C).withOpacity(intensity); // Severe distraction trap
          } else {
            cellColor = const Color(0xFFFF9F1C).withOpacity(intensity); // Moderate distraction
          }
        } else if (cell.focusMinutes > 0) {
          final intensity = (cell.focusMinutes / 60.0).clamp(0.2, 0.9);
          cellColor = const Color(0xFF00E699).withOpacity(intensity); // Pure deep work
        } else {
          cellColor = Colors.white.withOpacity(0.03); // Inactive
        }

        cellPaint.color = cellColor;
        canvas.drawRRect(rect, cellPaint);
        canvas.drawRRect(rect, borderPaint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _HeatmapPainter oldDelegate) {
    return oldDelegate.matrix != matrix;
  }
}
