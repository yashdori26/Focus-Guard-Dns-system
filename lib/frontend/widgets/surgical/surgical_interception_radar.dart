import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../../engine/surgical/catalog/surgical_subfeature_types.dart';

/// Interactive 8-axis radar polygon chart illustrating the distribution
/// of surgical interceptions across all sub-feature vectors.
class SurgicalInterceptionRadar extends StatelessWidget {
  final Map<SurgicalSubfeature, int> subfeatureCounts;
  final double size;

  const SurgicalInterceptionRadar({
    super.key,
    required this.subfeatureCounts,
    this.size = 280,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Center(
      child: SizedBox(
        width: size,
        height: size,
        child: CustomPaint(
          size: Size(size, size),
          painter: _SurgicalRadarPainter(
            counts: subfeatureCounts,
            isDark: isDark,
          ),
        ),
      ),
    );
  }
}

class _SurgicalRadarPainter extends CustomPainter {
  final Map<SurgicalSubfeature, int> counts;
  final bool isDark;

  _SurgicalRadarPainter({
    required this.counts,
    required this.isDark,
  });

  static const List<SurgicalSubfeature> axes = [
    SurgicalSubfeature.reelsOrShorts,
    SurgicalSubfeature.feed,
    SurgicalSubfeature.explore,
    SurgicalSubfeature.stories,
    SurgicalSubfeature.comments,
    SurgicalSubfeature.directMessages,
    SurgicalSubfeature.search,
    SurgicalSubfeature.creatorStudio,
  ];

  static const List<String> axisLabels = [
    'Reels',
    'Feed',
    'Explore',
    'Stories',
    'Comments',
    'DMs',
    'Search',
    'Studio',
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (size.width / 2) - 36; // leave room for labels
    final n = axes.length;
    final angleStep = (2 * math.pi) / n;

    // 1. Draw concentric polygon grid webs (4 rings: 25%, 50%, 75%, 100%)
    final gridPaint = Paint()
      ..color = (isDark ? Colors.white : Colors.black).withAlpha(24)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;

    for (int ring = 1; ring <= 4; ring++) {
      final ringRadius = (radius / 4) * ring;
      final webPath = Path();
      for (int i = 0; i < n; i++) {
        final angle = (i * angleStep) - (math.pi / 2);
        final x = center.dx + math.cos(angle) * ringRadius;
        final y = center.dy + math.sin(angle) * ringRadius;
        if (i == 0) {
          webPath.moveTo(x, y);
        } else {
          webPath.lineTo(x, y);
        }
      }
      webPath.close();
      canvas.drawPath(webPath, gridPaint);
    }

    // 2. Draw radial spoke axes
    final spokePaint = Paint()
      ..color = (isDark ? Colors.white : Colors.black).withAlpha(35)
      ..strokeWidth = 1.0;

    for (int i = 0; i < n; i++) {
      final angle = (i * angleStep) - (math.pi / 2);
      final spokeEnd = Offset(
        center.dx + math.cos(angle) * radius,
        center.dy + math.sin(angle) * radius,
      );
      canvas.drawLine(center, spokeEnd, spokePaint);

      // Draw axis labels
      final labelOffset = Offset(
        center.dx + math.cos(angle) * (radius + 20),
        center.dy + math.sin(angle) * (radius + 20),
      );
      _drawAxisLabel(canvas, axisLabels[i], labelOffset);
    }

    // 3. Find max count for normalization
    int maxCount = 1;
    for (final count in counts.values) {
      if (count > maxCount) maxCount = count;
    }

    // 4. Build data polygon path
    final dataPath = Path();
    final List<Offset> points = [];

    for (int i = 0; i < n; i++) {
      final feature = axes[i];
      final count = counts[feature] ?? 0;
      final normalized = (count / maxCount).clamp(0.10, 1.0);
      final pointRadius = radius * normalized;

      final angle = (i * angleStep) - (math.pi / 2);
      final pt = Offset(
        center.dx + math.cos(angle) * pointRadius,
        center.dy + math.sin(angle) * pointRadius,
      );
      points.add(pt);

      if (i == 0) {
        dataPath.moveTo(pt.dx, pt.dy);
      } else {
        dataPath.lineTo(pt.dx, pt.dy);
      }
    }
    dataPath.close();

    // 5. Fill data polygon with gradient
    final fillGradient = RadialGradient(
      colors: [
        const Color(0xFF6366F1).withAlpha(140),
        const Color(0xFF8B5CF6).withAlpha(80),
      ],
    );

    final fillPaint = Paint()
      ..shader = fillGradient.createShader(Rect.fromCircle(center: center, radius: radius))
      ..style = PaintingStyle.fill;
    canvas.drawPath(dataPath, fillPaint);

    // 6. Draw glowing perimeter stroke
    final strokePaint = Paint()
      ..color = const Color(0xFF818CF8)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5
      ..strokeJoin = StrokeJoin.round;
    canvas.drawPath(dataPath, strokePaint);

    // 7. Draw vertex nodes
    final nodePaint = Paint()..color = const Color(0xFFC7D2FE);
    final nodeGlow = Paint()
      ..color = const Color(0xFF6366F1).withAlpha(150)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4);

    for (final pt in points) {
      canvas.drawCircle(pt, 5.0, nodeGlow);
      canvas.drawCircle(pt, 3.5, nodePaint);
    }
  }

  void _drawAxisLabel(Canvas canvas, String text, Offset center) {
    final textSpan = TextSpan(
      text: text,
      style: TextStyle(
        color: isDark ? Colors.white70 : Colors.black87,
        fontSize: 10,
        fontWeight: FontWeight.w600,
      ),
    );
    final textPainter = TextPainter(
      text: textSpan,
      textAlign: TextAlign.center,
      textDirection: TextDirection.ltr,
    );
    textPainter.layout();
    final pos = Offset(center.dx - (textPainter.width / 2), center.dy - (textPainter.height / 2));
    textPainter.paint(canvas, pos);
  }

  @override
  bool shouldRepaint(covariant _SRadarPainter oldDelegate) {
    return oldDelegate.counts != counts || oldDelegate.isDark != isDark;
  }
}

typedef _SRadarPainter = _SurgicalRadarPainter;
