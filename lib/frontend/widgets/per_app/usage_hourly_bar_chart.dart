import 'package:flutter/material.dart';

/// Custom canvas painter rendering 24-hour hourly screen time histogram.
class UsageHourlyBarChart extends StatelessWidget {
  final List<int> hourlyUsageSeconds; // 24 entries
  final double height;
  final Color barColor;

  const UsageHourlyBarChart({
    super.key,
    required this.hourlyUsageSeconds,
    this.height = 90,
    this.barColor = const Color(0xFF3B82F6),
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: height,
          width: double.infinity,
          child: CustomPaint(
            painter: _HourlyBarPainter(
              data: hourlyUsageSeconds,
              barColor: barColor,
            ),
          ),
        ),
        const SizedBox(height: 4),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: const [
            Text('12 AM', style: TextStyle(color: Colors.white38, fontSize: 10)),
            Text('6 AM', style: TextStyle(color: Colors.white38, fontSize: 10)),
            Text('12 PM', style: TextStyle(color: Colors.white38, fontSize: 10)),
            Text('6 PM', style: TextStyle(color: Colors.white38, fontSize: 10)),
            Text('11 PM', style: TextStyle(color: Colors.white38, fontSize: 10)),
          ],
        ),
      ],
    );
  }
}

class _HourlyBarPainter extends CustomPainter {
  final List<int> data;
  final Color barColor;

  _HourlyBarPainter({required this.data, required this.barColor});

  @override
  void paint(Canvas canvas, Size size) {
    if (data.isEmpty) return;

    final maxVal = data.fold<int>(0, (prev, elem) => elem > prev ? elem : prev);
    final effectiveMax = maxVal == 0 ? 3600 : maxVal; // default to 1h scale if 0

    final barWidth = (size.width / 24) * 0.7;
    final spacing = (size.width / 24) * 0.3;

    final bgPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.05)
      ..style = PaintingStyle.fill;

    final barPaint = Paint()
      ..color = barColor
      ..style = PaintingStyle.fill;

    for (int i = 0; i < 24; i++) {
      final x = i * (barWidth + spacing) + spacing / 2;
      final val = i < data.length ? data[i] : 0;
      final ratio = (val / effectiveMax).clamp(0.0, 1.0);
      final barHeight = ratio * (size.height - 4);

      // Draw background track
      final trackRect = RRect.fromRectAndRadius(
        Rect.fromLTWH(x, 0, barWidth, size.height),
        const Radius.circular(2),
      );
      canvas.drawRRect(trackRect, bgPaint);

      // Draw filled bar from bottom
      if (barHeight > 0) {
        final fillRect = RRect.fromRectAndRadius(
          Rect.fromLTWH(x, size.height - barHeight, barWidth, barHeight),
          const Radius.circular(2),
        );
        canvas.drawRRect(fillRect, barPaint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _HourlyBarPainter oldDelegate) {
    return oldDelegate.data != data || oldDelegate.barColor != barColor;
  }
}
