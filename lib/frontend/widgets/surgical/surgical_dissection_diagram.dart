import 'dart:math' as math;
import 'package:flutter/material.dart';

/// Interactive custom canvas visualization displaying the surgical separation
/// between protected intentional communication (DMs) and severed algorithmic addiction traps (Reels).
class SurgicalDissectionDiagram extends StatefulWidget {
  final int blockedReelsCount;
  final int allowedChatsCount;
  final double height;
  final bool isAnimated;

  const SurgicalDissectionDiagram({
    super.key,
    this.blockedReelsCount = 42,
    this.allowedChatsCount = 128,
    this.height = 200,
    this.isAnimated = true,
  });

  @override
  State<SurgicalDissectionDiagram> createState() => _SurgicalDissectionDiagramState();
}

class _SurgicalDissectionDiagramState extends State<SurgicalDissectionDiagram>
    with SingleTickerProviderStateMixin {
  late AnimationController _animController;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3000),
    );
    if (widget.isAnimated) {
      _animController.repeat();
    }
  }

  @override
  void didUpdateWidget(SurgicalDissectionDiagram oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isAnimated && !_animController.isAnimating) {
      _animController.repeat();
    } else if (!widget.isAnimated && _animController.isAnimating) {
      _animController.stop();
    }
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardColor = isDark ? const Color(0xFF1E222B) : const Color(0xFFF3F5F9);

    return Container(
      height: widget.height,
      width: double.infinity,
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isDark ? const Color(0xFF2C3240) : const Color(0xFFE2E7F0),
          width: 1.5,
        ),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: AnimatedBuilder(
          animation: _animController,
          builder: (context, _) {
            return CustomPaint(
              painter: _SurgicalDissectionPainter(
                progress: _animController.value,
                isDark: isDark,
                blockedCount: widget.blockedReelsCount,
                allowedCount: widget.allowedChatsCount,
              ),
            );
          },
        ),
      ),
    );
  }
}

class _SurgicalDissectionPainter extends CustomPainter {
  final double progress;
  final bool isDark;
  final int blockedCount;
  final int allowedCount;

  _SurgicalDissectionPainter({
    required this.progress,
    required this.isDark,
    required this.blockedCount,
    required this.allowedCount,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    // Background subtle grid lines
    final gridPaint = Paint()
      ..color = (isDark ? Colors.white : Colors.black).withAlpha(12)
      ..strokeWidth = 1.0;

    for (double x = 20; x < w; x += 30) {
      canvas.drawLine(Offset(x, 0), Offset(x, h), gridPaint);
    }
    for (double y = 20; y < h; y += 30) {
      canvas.drawLine(Offset(0, y), Offset(w, y), gridPaint);
    }

    final topTrackY = h * 0.32;
    final bottomTrackY = h * 0.68;
    final midX = w * 0.50;

    // 1. TOP HIGHWAY: Protected Intentional Communication (Green)
    final greenBaseColor = const Color(0xFF10B981);
    final topTrackPaint = Paint()
      ..color = greenBaseColor.withAlpha(isDark ? 80 : 60)
      ..strokeWidth = 6.0
      ..strokeCap = StrokeCap.round;

    final topTrackPath = Path();
    topTrackPath.moveTo(24, topTrackY);
    topTrackPath.cubicTo(w * 0.3, topTrackY - 10, w * 0.7, topTrackY + 10, w - 24, topTrackY);
    canvas.drawPath(topTrackPath, topTrackPaint);

    // Glowing core line
    final topCorePaint = Paint()
      ..color = greenBaseColor
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round;
    canvas.drawPath(topTrackPath, topCorePaint);

    // Flowing data packets on Top Highway
    final packetPaint = Paint()..color = const Color(0xFF6EE7B7);
    for (int i = 0; i < 4; i++) {
      final pOffset = (progress + (i * 0.25)) % 1.0;
      final px = 24 + pOffset * (w - 48);
      final py = topTrackY + math.sin(pOffset * math.pi * 2) * 8;
      canvas.drawCircle(Offset(px, py), 4.0, packetPaint);

      // Packet glow
      final glowPaint = Paint()..color = greenBaseColor.withAlpha(60);
      canvas.drawCircle(Offset(px, py), 8.0, glowPaint);
    }

    // Top Label
    _drawText(
      canvas: canvas,
      text: 'CHAT & DMs (PROTECTED)',
      offset: Offset(28, topTrackY - 26),
      color: greenBaseColor,
      fontSize: 11,
      isBold: true,
    );
    _drawText(
      canvas: canvas,
      text: '$allowedCount Packets Flowing',
      offset: Offset(w - 150, topTrackY - 26),
      color: isDark ? Colors.white70 : Colors.black87,
      fontSize: 10,
    );

    // 2. BOTTOM HIGHWAY: Severed Algorithmic Addictions (Red)
    final redBaseColor = const Color(0xFFEF4444);
    final bottomTrackPaint = Paint()
      ..color = redBaseColor.withAlpha(isDark ? 80 : 60)
      ..strokeWidth = 6.0
      ..strokeCap = StrokeCap.round;

    // Incoming segment (left to midX)
    final incomingBottomPath = Path();
    incomingBottomPath.moveTo(24, bottomTrackY);
    incomingBottomPath.lineTo(midX - 12, bottomTrackY);
    canvas.drawPath(incomingBottomPath, bottomTrackPaint);

    final incomingCorePaint = Paint()
      ..color = redBaseColor
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round;
    canvas.drawPath(incomingBottomPath, incomingCorePaint);

    // Severed dead-end gap (midX - 12 to midX + 12)
    // Laser cutter beam at center
    final laserPaint = Paint()
      ..color = const Color(0xFFF43F5E)
      ..strokeWidth = 3.0
      ..strokeCap = StrokeCap.round;

    final laserGlow = Paint()
      ..color = const Color(0xFFF43F5E).withAlpha(120)
      ..strokeWidth = 10.0
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6);

    canvas.drawLine(Offset(midX, bottomTrackY - 22), Offset(midX, bottomTrackY + 22), laserGlow);
    canvas.drawLine(Offset(midX, bottomTrackY - 20), Offset(midX, bottomTrackY + 20), laserPaint);

    // Animated spark particles at severed junction
    final sparkPaint = Paint()..color = const Color(0xFFFDE047);
    for (int i = 0; i < 5; i++) {
      final sparkAngle = (progress * math.pi * 4 + (i * 1.25)) % (math.pi * 2);
      final sparkDist = 6 + (progress * 14);
      final sx = midX + math.cos(sparkAngle) * sparkDist;
      final sy = bottomTrackY + math.sin(sparkAngle) * sparkDist;
      canvas.drawCircle(Offset(sx, sy), 2.0, sparkPaint);
    }

    // Ghost dead segment on right (severed / blackholed)
    final deadTrackPaint = Paint()
      ..color = (isDark ? Colors.white : Colors.black).withAlpha(20)
      ..strokeWidth = 4.0
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    final deadPath = Path();
    deadPath.moveTo(midX + 16, bottomTrackY);
    deadPath.lineTo(w - 24, bottomTrackY);
    canvas.drawPath(deadPath, deadTrackPaint);

    // Cross icon on dead side
    final crossPaint = Paint()
      ..color = redBaseColor.withAlpha(180)
      ..strokeWidth = 2.0;
    canvas.drawLine(Offset(w - 40, bottomTrackY - 6), Offset(w - 28, bottomTrackY + 6), crossPaint);
    canvas.drawLine(Offset(w - 28, bottomTrackY - 6), Offset(w - 40, bottomTrackY + 6), crossPaint);

    // Bottom Label
    _drawText(
      canvas: canvas,
      text: 'REELS & FEEDS (BLACKHOLED)',
      offset: Offset(28, bottomTrackY + 14),
      color: redBaseColor,
      fontSize: 11,
      isBold: true,
    );
    _drawText(
      canvas: canvas,
      text: '$blockedCount Interceptions',
      offset: Offset(w - 150, bottomTrackY + 14),
      color: isDark ? Colors.white70 : Colors.black87,
      fontSize: 10,
    );
  }

  void _drawText({
    required Canvas canvas,
    required String text,
    required Offset offset,
    required Color color,
    required double fontSize,
    bool isBold = false,
  }) {
    final textSpan = TextSpan(
      text: text,
      style: TextStyle(
        color: color,
        fontSize: fontSize,
        fontWeight: isBold ? FontWeight.bold : FontWeight.w500,
        letterSpacing: 0.5,
      ),
    );
    final textPainter = TextPainter(
      text: textSpan,
      textDirection: TextDirection.ltr,
    );
    textPainter.layout();
    textPainter.paint(canvas, offset);
  }

  @override
  bool shouldRepaint(covariant _SurgicalDissectionPainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.blockedCount != blockedCount ||
        oldDelegate.allowedCount != allowedCount ||
        oldDelegate.isDark != isDark;
  }
}
