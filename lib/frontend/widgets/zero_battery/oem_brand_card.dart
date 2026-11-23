import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../engine/daemon/oem/oem_device_profiles.dart';

/// Interactive card presenting detected device brand characteristics and status.
class OemBrandCard extends StatelessWidget {
  final OemDeviceProfile profile;
  final String romVersion;
  final VoidCallback onLaunchWizard;

  const OemBrandCard({
    super.key,
    required this.profile,
    required this.romVersion,
    required this.onLaunchWizard,
  });

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1C1C1E) : Colors.white,
        borderRadius: BorderRadius.circular(18),
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
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF2C2C2E) : const Color(0xFFF2F2F7),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.phone_android_rounded, size: 24, color: Color(0xFF3498DB)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      profile.displayName,
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: isDark ? Colors.white : Colors.black87,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      romVersion,
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 12,
                        color: isDark ? Colors.white60 : Colors.black54,
                      ),
                    ),
                  ],
                ),
              ),
              _buildSeverityBadge(profile.severity),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            'Aggressive background task killers may silently terminate focus blockers on ${profile.displayName}. Follow our tailored guide to make FocusDNS 100% unbreakable.',
            style: GoogleFonts.plusJakartaSans(
              fontSize: 12,
              color: isDark ? Colors.white70 : Colors.black87,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: onLaunchWizard,
              icon: const Icon(Icons.tune_rounded, size: 16),
              label: const Text('OPEN STEP-BY-STEP SETUP WIZARD'),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                side: BorderSide(color: isDark ? const Color(0xFF3A3A3C) : const Color(0xFFD1D1D6)),
                textStyle: GoogleFonts.plusJakartaSans(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSeverityBadge(OemKillSeverity severity) {
    Color color;
    String label;

    switch (severity) {
      case OemKillSeverity.standard:
        color = const Color(0xFF2ECC71);
        label = 'Standard';
        break;
      case OemKillSeverity.moderate:
        color = const Color(0xFF3498DB);
        label = 'Moderate';
        break;
      case OemKillSeverity.aggressive:
        color = const Color(0xFFF39C12);
        label = 'Aggressive';
        break;
      case OemKillSeverity.severe:
        color = const Color(0xFFE67E22);
        label = 'Severe';
        break;
      case OemKillSeverity.extreme:
        color = const Color(0xFFE74C3C);
        label = 'Extreme Hostility';
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Text(
        label,
        style: GoogleFonts.plusJakartaSans(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
    );
  }
}
