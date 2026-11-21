import 'package:flutter/material.dart';
import '../../../engine/surgical/catalog/surgical_subfeature_types.dart';
import '../../../engine/surgical/models/surgical_rule_model.dart';

/// Card component representing a monitored platform in the Surgical Studio dashboard.
class PlatformSurgicalCard extends StatelessWidget {
  final SurgicalRuleModel rule;
  final VoidCallback onTap;
  final Function(bool isEnabled)? onMasterToggle;
  final int blockedCount;

  const PlatformSurgicalCard({
    super.key,
    required this.rule,
    required this.onTap,
    this.onMasterToggle,
    this.blockedCount = 0,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardColor = isDark ? const Color(0xFF1E222B) : Colors.white;

    final reelsBlocked = rule.isSubfeatureBlocked(SurgicalSubfeature.reelsOrShorts);
    final feedBlocked = rule.isSubfeatureBlocked(SurgicalSubfeature.feed);
    final exploreBlocked = rule.isSubfeatureBlocked(SurgicalSubfeature.explore);
    final dmsAllowed = !rule.isSubfeatureBlocked(SurgicalSubfeature.directMessages);

    final bool isDecoupled = (reelsBlocked || feedBlocked) && dmsAllowed;

    return Material(
      color: cardColor,
      borderRadius: BorderRadius.circular(20),
      elevation: 0,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: isDecoupled
                  ? const Color(0xFF10B981).withAlpha(120)
                  : (isDark ? const Color(0xFF2C3240) : const Color(0xFFE2E7F0)),
              width: isDecoupled ? 1.5 : 1.0,
            ),
          ),
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header Row: Glyph + Title + Status Pill + Chevron
              Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0xFF282E3B) : const Color(0xFFEEF2F6),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      rule.iconGlyph,
                      style: const TextStyle(fontSize: 22),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          rule.displayName,
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: isDark ? Colors.white : Colors.black87,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          rule.packageNames.isNotEmpty ? rule.packageNames.first : 'Web platform',
                          style: TextStyle(
                            fontSize: 11,
                            color: isDark ? Colors.white54 : Colors.black54,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  _buildStatusPill(isDecoupled, isDark),
                  const SizedBox(width: 8),
                  Icon(
                    Icons.chevron_right_rounded,
                    color: isDark ? Colors.white38 : Colors.black38,
                  ),
                ],
              ),
              const SizedBox(height: 14),

              // Subfeature Status Chips
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  if (reelsBlocked)
                    _buildChip('Reels Severed', const Color(0xFFEF4444), isDark),
                  if (feedBlocked)
                    _buildChip('Feed Blackholed', const Color(0xFFF59E0B), isDark),
                  if (exploreBlocked)
                    _buildChip('Explore Blocked', const Color(0xFF8B5CF6), isDark),
                  if (dmsAllowed)
                    _buildChip('DMs Intact', const Color(0xFF10B981), isDark),
                ],
              ),

              if (blockedCount > 0) ...[
                const SizedBox(height: 10),
                Text(
                  '$blockedCount addiction loops severed today',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                    color: const Color(0xFF10B981),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatusPill(bool isDecoupled, bool isDark) {
    final color = isDecoupled ? const Color(0xFF10B981) : Colors.grey;
    final text = isDecoupled ? 'DECOUPLED' : 'PASS-THROUGH';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withAlpha(isDark ? 40 : 25),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withAlpha(120), width: 0.8),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: color,
          fontSize: 9,
          fontWeight: FontWeight.bold,
          letterSpacing: 0.5,
        ),
      ),
    );
  }

  Widget _buildChip(String label, Color color, bool isDark) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withAlpha(isDark ? 30 : 20),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withAlpha(90), width: 0.8),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }
}
