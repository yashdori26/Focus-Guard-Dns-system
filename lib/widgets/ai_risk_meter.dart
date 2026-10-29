/// FocusDNS Flutter Widget - AI Threat Risk Meter
/// Visualizes composite risk scores with color transitions, animated progress,
/// and risk level badge (Low, Moderate, High, Critical).

import 'package:flutter/material.dart';

class AiRiskMeter extends StatelessWidget {
  final double score; // 0.0 to 100.0
  final double height;
  final bool showBadge;

  const AiRiskMeter({
    Key? key,
    required this.score,
    this.height = 10,
    this.showBadge = true,
  }) : super(key: key);

  Color _getRiskColor(double val) {
    if (val >= 75) return const Color(0xFFEF4444); // Red
    if (val >= 50) return const Color(0xFFF59E0B); // Amber
    if (val >= 25) return const Color(0xFF3B82F6); // Blue
    return const Color(0xFF10B981); // Green
  }

  String _getRiskLabel(double val) {
    if (val >= 75) return 'CRITICAL';
    if (val >= 50) return 'ELEVATED';
    if (val >= 25) return 'MODERATE';
    return 'BENIGN';
  }

  @override
  Widget build(BuildContext context) {
    final clamped = score.clamp(0.0, 100.0);
    final color = _getRiskColor(clamped);
    final label = _getRiskLabel(clamped);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (showBadge) ...[
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Risk Score: ${clamped.toStringAsFixed(1)}%',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  color: color,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: color.withOpacity(0.4)),
                ),
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: color,
                    letterSpacing: 0.8,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
        ],
        ClipRRect(
          borderRadius: BorderRadius.circular(height / 2),
          child: Container(
            height: height,
            color: Colors.white.withOpacity(0.08),
            child: Stack(
              children: [
                FractionallySizedBox(
                  widthFactor: (clamped / 100.0).clamp(0.01, 1.0),
                  child: Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          color.withOpacity(0.7),
                          color,
                        ],
                      ),
                      borderRadius: BorderRadius.circular(height / 2),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
