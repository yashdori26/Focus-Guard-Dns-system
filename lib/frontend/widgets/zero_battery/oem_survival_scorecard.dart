import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../engine/daemon/telemetry/oem_resilience_auditor.dart';

/// Visual scorecard breaking down device survivability against OEM task killers.
class OemSurvivalScorecard extends StatelessWidget {
  final OemAuditScorecard scorecard;
  final VoidCallback onFixVulnerabilities;

  const OemSurvivalScorecard({
    super.key,
    required this.scorecard,
    required this.onFixVulnerabilities,
  });

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final Color scoreColor = _getScoreColor(scorecard.totalScore);

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1C1C1E) : Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isDark ? const Color(0xFF2C2C2E) : const Color(0xFFE5E5EA),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: scoreColor.withOpacity(0.12),
                  shape: BoxShape.circle,
                ),
                child: Center(
                  child: Text(
                    '${scorecard.totalScore}',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      color: scoreColor,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${scorecard.tier.name.toUpperCase()} SHIELD',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        color: scoreColor,
                        letterSpacing: 0.5,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${scorecard.verifiedShields.length} protections active • ${scorecard.outstandingVulnerabilities.length} actions needed',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 11,
                        color: isDark ? Colors.white60 : Colors.black54,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),

          // Sub-vector Progress Bars
          _buildVectorRow('Autostart & Startup Exemption', scorecard.autostartScore, 35, isDark),
          const SizedBox(height: 10),
          _buildVectorRow('Doze & Battery Optimization', scorecard.dozeScore, 30, isDark),
          const SizedBox(height: 10),
          _buildVectorRow('Recent Apps Tray Pinning', scorecard.recentsLockScore, 20, isDark),
          const SizedBox(height: 10),
          _buildVectorRow('Foreground Service & Overlay', scorecard.permissionsScore, 15, isDark),

          if (scorecard.outstandingVulnerabilities.isNotEmpty) ...[
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: onFixVulnerabilities,
                icon: const Icon(Icons.shield_outlined, size: 16),
                label: const Text('HARDEN DEVICE PROTECTION'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: scoreColor,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  textStyle: GoogleFonts.plusJakartaSans(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildVectorRow(String title, int score, int maxScore, bool isDark) {
    final double pct = (score / maxScore).clamp(0.0, 1.0);
    final Color barColor = pct == 1.0 ? const Color(0xFF2ECC71) : const Color(0xFFF39C12);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              title,
              style: GoogleFonts.plusJakartaSans(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: isDark ? Colors.white70 : Colors.black87,
              ),
            ),
            Text(
              '$score / $maxScore pts',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: barColor,
              ),
            ),
          ],
        ),
        const SizedBox(height: 5),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: pct,
            backgroundColor: isDark ? const Color(0xFF2C2C2E) : const Color(0xFFE5E5EA),
            valueColor: AlwaysStoppedAnimation<Color>(barColor),
            minHeight: 5,
          ),
        ),
      ],
    );
  }

  Color _getScoreColor(int score) {
    if (score >= 95) return const Color(0xFF2ECC71);
    if (score >= 80) return const Color(0xFF3498DB);
    if (score >= 50) return const Color(0xFFF39C12);
    return const Color(0xFFE74C3C);
  }
}
