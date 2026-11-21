import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../engine/daemon/oem/oem_registry.dart';
import '../../../engine/daemon/oem/oem_troubleshooting_guides.dart';

/// Interactive step-by-step diagnostic and hardening wizard for the host OEM.
class OemExemptionWizardScreen extends StatefulWidget {
  const OemExemptionWizardScreen({super.key});

  @override
  State<OemExemptionWizardScreen> createState() => _OemExemptionWizardScreenState();
}

class _OemExemptionWizardScreenState extends State<OemExemptionWizardScreen> {
  final OemRegistry _registry = OemRegistry();
  final Set<int> _completedSteps = {};

  @override
  void initState() {
    super.initState();
    _registry.detectDevice();
  }

  void _toggleStep(int stepNumber) {
    setState(() {
      if (_completedSteps.contains(stepNumber)) {
        _completedSteps.remove(stepNumber);
      } else {
        _completedSteps.add(stepNumber);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? const Color(0xFF141416) : const Color(0xFFF8F9FA);
    final cardColor = isDark ? const Color(0xFF1C1C1E) : Colors.white;
    final borderColor = isDark ? const Color(0xFF2C2C2E) : const Color(0xFFE5E5EA);

    final guide = _registry.currentGuide;
    final profile = _registry.currentProfile;

    final int calculatedScore = _registry.calculateSurvivabilityScore() +
        (_completedSteps.length * 15).clamp(0, 40);

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        backgroundColor: bgColor,
        elevation: 0,
        title: Text(
          'OEM Hardening Wizard',
          style: GoogleFonts.plusJakartaSans(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: isDark ? Colors.white : Colors.black87,
          ),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header Card
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: cardColor,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: borderColor),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          profile.displayName.toUpperCase(),
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 1.0,
                            color: const Color(0xFF3498DB),
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: const Color(0xFF2ECC71).withOpacity(0.12),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            'SCORE: $calculatedScore / 100',
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                              color: const Color(0xFF2ECC71),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Text(
                      guide.headline,
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: isDark ? Colors.white : Colors.black87,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      guide.introWarning,
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 12,
                        color: isDark ? Colors.white70 : Colors.black87,
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 24),

              Text(
                'ACTIONABLE HARDENING STEPS',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.1,
                  color: isDark ? Colors.white54 : Colors.black45,
                ),
              ),
              const SizedBox(height: 12),

              ...guide.steps.map((step) => _buildStepCard(
                    step: step,
                    isCompleted: _completedSteps.contains(step.stepNumber),
                    isDark: isDark,
                    cardColor: cardColor,
                    borderColor: borderColor,
                  )),

              const SizedBox(height: 20),

              // Recent Apps Tray Pinning Card
              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: cardColor,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: borderColor),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.lock_outline_rounded, size: 20, color: Color(0xFFF39C12)),
                        const SizedBox(width: 8),
                        Text(
                          'LOCK IN RECENT APPS TRAY',
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.8,
                            color: isDark ? Colors.white : Colors.black87,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Text(
                      guide.recentsLockInstructions,
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 12,
                        color: isDark ? Colors.white70 : Colors.black87,
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 20),

              // Developer Options Tip
              if (guide.developerOptionsTip.isNotEmpty)
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFF3498DB).withOpacity(0.08),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: const Color(0xFF3498DB).withOpacity(0.2)),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.info_outline_rounded, size: 18, color: Color(0xFF3498DB)),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          guide.developerOptionsTip,
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 12,
                            color: isDark ? Colors.white70 : Colors.black87,
                            height: 1.35,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

              const SizedBox(height: 30),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStepCard({
    required OemSetupStep step,
    required bool isCompleted,
    required bool isDark,
    required Color cardColor,
    required Color borderColor,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: isCompleted ? const Color(0xFF2ECC71) : borderColor,
          width: isCompleted ? 1.5 : 1.0,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: isCompleted
                      ? const Color(0xFF2ECC71).withOpacity(0.15)
                      : (isDark ? const Color(0xFF2C2C2E) : const Color(0xFFF2F2F7)),
                  shape: BoxShape.circle,
                ),
                child: Center(
                  child: Icon(
                    isCompleted ? Icons.check_rounded : step.icon,
                    size: 16,
                    color: isCompleted ? const Color(0xFF2ECC71) : (isDark ? Colors.white70 : Colors.black87),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Step ${step.stepNumber}: ${step.title}',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: isDark ? Colors.white : Colors.black87,
                  ),
                ),
              ),
              Checkbox(
                value: isCompleted,
                activeColor: const Color(0xFF2ECC71),
                onChanged: (_) => _toggleStep(step.stepNumber),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            step.instructions,
            style: GoogleFonts.plusJakartaSans(
              fontSize: 12,
              color: isDark ? Colors.white70 : Colors.black87,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF141416) : const Color(0xFFF2F2F7),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              step.settingPath,
              style: GoogleFonts.jetBrainsMono(
                fontSize: 10.5,
                color: const Color(0xFF3498DB),
              ),
            ),
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () async {
                if (step.stepNumber == 1) {
                  await _registry.launchPrimaryAutostart();
                } else {
                  await _registry.launchPrimaryBatteryOptimization();
                }
              },
              icon: const Icon(Icons.open_in_new_rounded, size: 15),
              label: Text(step.actionButtonLabel),
              style: ElevatedButton.styleFrom(
                backgroundColor: isDark ? const Color(0xFF2C2C2E) : const Color(0xFFE5E5EA),
                foregroundColor: isDark ? Colors.white : Colors.black87,
                elevation: 0,
                padding: const EdgeInsets.symmetric(vertical: 11),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
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
}
