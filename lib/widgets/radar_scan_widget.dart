/// FocusDNS Flutter Widget - Animated Radar Scan Visualizer
/// Custom painter rendering rotating radar sweep lines, concentric range circles,
/// and blips representing neutralized zero-day threats.

import 'dart:math' as math;
import 'package:flutter/material.dart';

class RadarScanWidget extends StatefulWidget {
  final double size;
  final int activeThreatBlips;
  final bool isScanning;

  const RadarScanWidget({
    Key? key,
    this.size = 200,
    this.activeThreatBlips = 3,
    this.isScanning = true,
  }) : super(key: key);

  @override
  State<RadarScanWidget> createState() => _RadarScanWidgetState();
}

class _RadarScanWidgetState extends State<RadarScanWidget>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 4),
    );
    if (widget.isScanning) {
      _controller.repeat();
    }
  }

  @override
  void didUpdateWidget(covariant RadarScanWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isScanning != oldWidget.isScanning) {
      if (widget.isScanning) {
        _controller.repeat();
      } else {
        _controller.stop();
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return CustomPaint(
          size: Size(widget.size, widget.size),
          painter: _RadarPainter(
            sweepAngle: _controller.value * 2 * math.pi,
            blipCount: widget.activeThreatBlips,
          ),
        );
      },
    );
  }
}

class _RadarPainter extends CustomPainter {
  final double sweepAngle;
  final int blipCount;

  _RadarPainter({required this.sweepAngle, required this.blipCount});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;

    // Background circle
    final bgPaint = Paint()
      ..color = const Color(0xFF0F172A)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(center, radius, bgPaint);

    // Concentric grid circles
    final gridPaint = Paint()
      ..color = const Color(0xFF10B981).withOpacity(0.2)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;

    canvas.drawCircle(center, radius * 0.25, gridPaint);
    canvas.drawCircle(center, radius * 0.50, gridPaint);
    canvas.drawCircle(center, radius * 0.75, gridPaint);
    canvas.drawCircle(center, radius * 0.98, gridPaint);

    // Crosshairs
    final crossPaint = Paint()
      ..color = const Color(0xFF10B981).withOpacity(0.15)
      ..strokeWidth = 1.0;
    canvas.drawLine(Offset(center.dx, 0), Offset(center.dx, size.height), crossPaint);
    canvas.drawLine(Offset(0, center.dy), Offset(size.width, center.dy), crossPaint);

    // Radar sweep gradient beam
    final sweepRect = Rect.fromCircle(center: center, radius: radius);
    final sweepGradient = SweepGradient(
      center: Alignment.center,
      startAngle: 0.0,
      endAngle: math.pi / 2,
      colors: [
        Colors.transparent,
        const Color(0xFF10B981).withOpacity(0.35),
      ],
      stops: const [0.0, 1.0],
      transform: GradientRotation(sweepAngle - math.pi / 2),
    );

    final sweepPaint = Paint()
      ..shader = sweepGradient.createShader(sweepRect)
      ..style = PaintingStyle.fill;

    canvas.drawCircle(center, radius * 0.98, sweepPaint);

    // Sweep leading edge line
    final sweepLinePaint = Paint()
      ..color = const Color(0xFF34D399)
      ..strokeWidth = 2.0;
    final edgePoint = Offset(
      center.dx + radius * 0.98 * math.cos(sweepAngle),
      center.dy + radius * 0.98 * math.sin(sweepAngle),
    );
    canvas.drawLine(center, edgePoint, sweepLinePaint);

    // Threat blips
    final blipPaint = Paint()
      ..color = const Color(0xFFEF4444)
      ..style = PaintingStyle.fill;

    final glowPaint = Paint()
      ..color = const Color(0xFFEF4444).withOpacity(0.3)
      ..style = PaintingStyle.fill;

    final blipOffsets = [
      Offset(center.dx + radius * 0.45 * math.cos(0.8), center.dy + radius * 0.45 * math.sin(0.8)),
      Offset(center.dx + radius * 0.65 * math.cos(2.4), center.dy + radius * 0.65 * math.sin(2.4)),
      Offset(center.dx + radius * 0.35 * math.cos(4.2), center.dy + radius * 0.35 * math.sin(4.2)),
    ];

    for (int i = 0; i < math.min(blipCount, blipOffsets.length); ++i) {
      canvas.drawCircle(blipOffsets[i], 8.0, glowPaint);
      canvas.drawCircle(blipOffsets[i], 3.5, blipPaint);
    }

    // Center focal dot
    final centerPaint = Paint()..color = const Color(0xFF34D399);
    canvas.drawCircle(center, 3.0, centerPaint);
  }

  @override
  bool shouldRepaint(covariant _RadarPainter oldDelegate) {
    return oldDelegate.sweepAngle != sweepAngle || oldDelegate.blipCount != blipCount;
  }
}
