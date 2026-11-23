// FocusDNS Threat Matrix Radial Gauge & Distribution Widget

import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../models/enterprise_models.dart';

class ThreatMatrixGauge extends StatelessWidget {
  final ThreatMatrixModel matrix;

  const ThreatMatrixGauge({super.key, required this.matrix});

  static const _threatColors = <String, Color>{
    'DGA_MALWARE': Color(0xFFEF5350),
    'PHISHING_ZERO_HOUR': Color(0xFFFF7043),
    'HOMOGRAPH_TYPOSQUAT': Color(0xFFAB47BC),
    'DNS_TUNNELING': Color(0xFF26C6DA),
    'DOMAIN_FRONTING': Color(0xFFFFCA28),
  };

  static const _threatLabels = <String, String>{
    'DGA_MALWARE': 'DGA C2 Malware',
    'PHISHING_ZERO_HOUR': 'Zero-Hour Phishing',
    'HOMOGRAPH_TYPOSQUAT': 'IDN Homograph',
    'DNS_TUNNELING': 'Covert DNS Tunneling',
    'DOMAIN_FRONTING': 'TLS Domain Fronting',
  };

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E20),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF2C2C2E)),
      ),
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Zero-Day Threat Matrix Distribution',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                  letterSpacing: -0.2,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: const Color(0xFFEF5350).withOpacity(0.15),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  '${matrix.totalThreats} Caught',
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFFEF5350),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              SizedBox(
                width: 110,
                height: 110,
                child: CustomPaint(
                  painter: _RadialDonutPainter(
                    breakdown: matrix.breakdown,
                    total: matrix.totalThreats,
                    colorMap: _threatColors,
                  ),
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          '${matrix.totalThreats}',
                          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
                        ),
                        const Text('Threats', style: TextStyle(fontSize: 10, color: Colors.white54)),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 20),
              Expanded(
                child: Column(
                  children: matrix.breakdown.entries.map((entry) {
                    final color = _threatColors[entry.key] ?? const Color(0xFF78909C);
                    final label = _threatLabels[entry.key] ?? entry.key;
                    final pct = matrix.totalThreats > 0
                        ? (entry.value / matrix.totalThreats * 100).toStringAsFixed(1)
                        : '0.0';

                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 3),
                      child: Row(
                        children: [
                          Container(width: 8, height: 8, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              label,
                              style: const TextStyle(fontSize: 12, color: Colors.white70),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          Text(
                            '${entry.value} ($pct%)',
                            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: color),
                          ),
                        ],
                      ),
                    );
                  }).toList(),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _RadialDonutPainter extends CustomPainter {
  final Map<String, int> breakdown;
  final int total;
  final Map<String, Color> colorMap;

  _RadialDonutPainter({
    required this.breakdown,
    required this.total,
    required this.colorMap,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (size.width / 2) - 8;
    const strokeW = 12.0;

    final bgPaint = Paint()
      ..color = const Color(0xFF2C2C2E)
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeW;
    canvas.drawCircle(center, radius, bgPaint);

    if (total == 0 || breakdown.isEmpty) return;

    double startAngle = -math.pi / 2;
    for (final entry in breakdown.entries) {
      final sweepAngle = (entry.value / total) * (2 * math.pi);
      final paint = Paint()
        ..color = colorMap[entry.key] ?? const Color(0xFF78909C)
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeW
        ..strokeCap = StrokeCap.round;

      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        startAngle,
        sweepAngle - 0.05, // tiny gap
        false,
        paint,
      );
      startAngle += sweepAngle;
    }
  }

  @override
  bool shouldRepaint(covariant _RadialDonutPainter oldDelegate) {
    return oldDelegate.total != total || oldDelegate.breakdown != breakdown;
  }
}
