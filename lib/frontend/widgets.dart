import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../state_management/live_telemetry_provider.dart';
import 'theme/wabi_sabi_theme.dart';

class QueryLogItem extends StatelessWidget {
  final String subdomain;
  final String domain;
  final String timeAgo;
  final String iconText;
  final bool isBlocked;

  const QueryLogItem({
    super.key,
    required this.subdomain,
    required this.domain,
    required this.timeAgo,
    required this.iconText,
    this.isBlocked = false,
  });

  @override
  Widget build(BuildContext context) {
    final palette = WabiSabiPalette.of(context);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6.0),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(4),
              color: palette.canvas,
              border: Border.all(color: palette.hairlineSoft, width: 1),
            ),
            child: Center(
              child: Text(
                iconText,
                style: GoogleFonts.inter(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                  color: palette.ink,
                  letterSpacing: -0.2,
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                RichText(
                  overflow: TextOverflow.ellipsis,
                  text: TextSpan(
                    children: [
                      TextSpan(
                        text: subdomain,
                        style: GoogleFonts.inter(
                          color: palette.mutedInk,
                          fontSize: 13,
                          fontWeight: FontWeight.w400,
                        ),
                      ),
                      TextSpan(
                        text: domain,
                        style: GoogleFonts.inter(
                          color: palette.ink,
                          fontWeight: FontWeight.w600,
                          fontSize: 13.5,
                          letterSpacing: -0.2,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 2),
                Row(
                  children: [
                    Text(
                      timeAgo,
                      style: GoogleFonts.inter(
                        color: palette.mutedInk,
                        fontSize: 11,
                        fontWeight: FontWeight.w400,
                      ),
                    ),
                    if (isBlocked) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                        decoration: BoxDecoration(
                          color: palette.strictAccent.withOpacity(0.12),
                          borderRadius: BorderRadius.circular(3),
                        ),
                        child: Text(
                          'BLOCKED',
                          style: GoogleFonts.inter(
                            color: palette.strictAccent,
                            fontSize: 9,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class AnimatedChart extends StatefulWidget {
  final String filter;
  final Color totalColor;
  final Color blockedColor;
  final List<LiveDnsQueryItem>? queries;

  const AnimatedChart({
    super.key,
    required this.filter,
    required this.totalColor,
    required this.blockedColor,
    this.queries,
  });

  @override
  State<AnimatedChart> createState() => _AnimatedChartState();
}

class _AnimatedChartState extends State<AnimatedChart> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
      value: 1.0,
    );
    _animation = CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic);
  }

  @override
  void didUpdateWidget(covariant AnimatedChart oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.filter != widget.filter || oldWidget.queries?.length != widget.queries?.length) {
      _controller.forward(from: 0.15);
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
      animation: _animation,
      builder: (context, _) {
        return CustomPaint(
          painter: ChartPainter(
            filter: widget.filter,
            progress: _animation.value,
            totalColor: widget.totalColor,
            blockedColor: widget.blockedColor,
            queries: widget.queries,
          ),
        );
      },
    );
  }
}

class ChartPainter extends CustomPainter {
  final String filter;
  final double progress;
  final Color? totalColor;
  final Color? blockedColor;
  final List<LiveDnsQueryItem>? queries;

  ChartPainter({
    required this.filter,
    this.progress = 1.0,
    this.totalColor,
    this.blockedColor,
    this.queries,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final effectiveProgress = progress.clamp(0.05, 1.0);
    final baseline = size.height * 0.88;
    double morphY(double targetY) => baseline - (baseline - targetY) * effectiveProgress;

    final paintTotal = Paint()
      ..color = (totalColor ?? Colors.white).withOpacity(effectiveProgress.clamp(0.4, 1.0))
      ..strokeWidth = 2.4
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final paintBlocked = Paint()
      ..color = (blockedColor ?? const Color(0xFFE11D48)).withOpacity(effectiveProgress.clamp(0.4, 1.0))
      ..strokeWidth = 2.0
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final pathTotal = Path();
    final pathBlocked = Path();

    if (queries != null && queries!.isNotEmpty) {
      final queryList = queries!;
      const int segments = 8;
      final totalCounts = List<int>.filled(segments, 0);
      final blockedCounts = List<int>.filled(segments, 0);

      // Distribute queries chronologically into segments
      for (int i = 0; i < queryList.length; i++) {
        final bucket = ((queryList.length - 1 - i) * segments / queryList.length).floor().clamp(0, segments - 1);
        totalCounts[bucket]++;
        if (queryList[i].isBlocked) {
          blockedCounts[bucket]++;
        }
      }

      int maxVal = totalCounts.reduce(math.max);
      if (maxVal < 1) maxVal = 1;

      final totalPoints = <Offset>[];
      final blockedPoints = <Offset>[];

      for (int i = 0; i < segments; i++) {
        final x = (i / (segments - 1)) * size.width;
        final tRatio = totalCounts[i] / maxVal;
        final bRatio = blockedCounts[i] / maxVal;

        final targetYTotal = baseline - (tRatio * (baseline - size.height * 0.15));
        final targetYBlocked = baseline - (bRatio * (baseline - size.height * 0.15));

        totalPoints.add(Offset(x, morphY(targetYTotal)));
        blockedPoints.add(Offset(x, morphY(targetYBlocked)));
      }

      pathTotal.moveTo(totalPoints[0].dx, totalPoints[0].dy);
      pathBlocked.moveTo(blockedPoints[0].dx, blockedPoints[0].dy);

      for (int i = 0; i < segments - 1; i++) {
        final p0 = totalPoints[i];
        final p1 = totalPoints[i + 1];
        final midX = (p0.dx + p1.dx) / 2;
        pathTotal.cubicTo(midX, p0.dy, midX, p1.dy, p1.dx, p1.dy);

        final b0 = blockedPoints[i];
        final b1 = blockedPoints[i + 1];
        final bMidX = (b0.dx + b1.dx) / 2;
        pathBlocked.cubicTo(bMidX, b0.dy, bMidX, b1.dy, b1.dx, b1.dy);
      }
    } else {
      pathTotal.moveTo(0, morphY(baseline));
      pathTotal.lineTo(size.width, morphY(baseline));

      pathBlocked.moveTo(0, morphY(baseline));
      pathBlocked.lineTo(size.width, morphY(baseline));
    }

    // Gradient fill under total path
    final fillPath = Path.from(pathTotal);
    fillPath.lineTo(size.width, baseline);
    fillPath.lineTo(0, baseline);
    fillPath.close();

    final fillPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          (totalColor ?? Colors.white).withOpacity(0.08 * effectiveProgress),
          Colors.transparent,
        ],
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height))
      ..style = PaintingStyle.fill;

    canvas.drawPath(fillPath, fillPaint);
    canvas.drawPath(pathTotal, paintTotal);
    canvas.drawPath(pathBlocked, paintBlocked);
  }

  @override
  bool shouldRepaint(covariant ChartPainter oldDelegate) =>
      oldDelegate.filter != filter ||
      oldDelegate.progress != progress ||
      oldDelegate.totalColor != totalColor ||
      oldDelegate.blockedColor != blockedColor;
}
