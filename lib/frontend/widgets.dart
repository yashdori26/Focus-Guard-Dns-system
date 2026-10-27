import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
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
              borderRadius: BorderRadius.circular(10),
              color: palette.canvas,
              border: Border.all(color: palette.border, width: 1),
            ),
            child: Center(
              child: Text(
                iconText,
                style: GoogleFonts.plusJakartaSans(
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
                        style: GoogleFonts.plusJakartaSans(
                          color: palette.mutedInk,
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      TextSpan(
                        text: domain,
                        style: GoogleFonts.plusJakartaSans(
                          color: palette.ink,
                          fontWeight: FontWeight.w700,
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
                      style: GoogleFonts.plusJakartaSans(
                        color: palette.mutedInk,
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    if (isBlocked) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                        decoration: BoxDecoration(
                          color: palette.strictAccent.withOpacity(0.12),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          'BLOCKED',
                          style: GoogleFonts.plusJakartaSans(
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

  const AnimatedChart({
    super.key,
    required this.filter,
    required this.totalColor,
    required this.blockedColor,
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
    if (oldWidget.filter != widget.filter) {
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

  ChartPainter({
    required this.filter,
    this.progress = 1.0,
    this.totalColor,
    this.blockedColor,
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

    if (filter == '24h') {
      pathTotal.moveTo(0, morphY(size.height * 0.8));
      pathTotal.lineTo(size.width * 0.75, morphY(size.height * 0.8));
      pathTotal.lineTo(size.width, morphY(size.height * 0.15));

      pathBlocked.moveTo(0, morphY(size.height * 0.9));
      pathBlocked.lineTo(size.width, morphY(size.height * 0.9));
    } else if (filter == '7d') {
      pathTotal.moveTo(0, morphY(size.height * 0.3));
      pathTotal.quadraticBezierTo(
        size.width * 0.2, morphY(size.height * 0.85),
        size.width * 0.4, morphY(size.height * 0.45),
      );
      pathTotal.quadraticBezierTo(
        size.width * 0.6, morphY(size.height * 0.1),
        size.width * 0.8, morphY(size.height * 0.75),
      );
      pathTotal.lineTo(size.width, morphY(size.height * 0.85));

      pathBlocked.moveTo(0, morphY(size.height * 0.85));
      pathBlocked.quadraticBezierTo(
        size.width * 0.5, morphY(size.height * 0.92),
        size.width, morphY(size.height * 0.85),
      );
    } else {
      pathTotal.moveTo(0, morphY(size.height * 0.85));
      pathTotal.quadraticBezierTo(
        size.width * 0.2, morphY(size.height * 0.15),
        size.width * 0.4, morphY(size.height * 0.85),
      );
      pathTotal.quadraticBezierTo(
        size.width * 0.6, morphY(size.height * 0.1),
        size.width * 0.8, morphY(size.height * 0.85),
      );
      pathTotal.lineTo(size.width, morphY(size.height * 0.85));

      pathBlocked.moveTo(0, morphY(size.height * 0.9));
      pathBlocked.quadraticBezierTo(
        size.width * 0.3, morphY(size.height * 0.82),
        size.width * 0.6, morphY(size.height * 0.86),
      );
      pathBlocked.lineTo(size.width, morphY(size.height * 0.9));
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
