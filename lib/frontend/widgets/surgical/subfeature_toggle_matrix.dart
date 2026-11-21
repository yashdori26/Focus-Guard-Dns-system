import 'package:flutter/material.dart';
import '../../../engine/surgical/catalog/surgical_subfeature_types.dart';

/// Interactive matrix of toggles for all 8 surgical sub-feature vectors,
/// displaying dopamine addiction ratings, descriptions, and strict mode status.
class SubfeatureToggleMatrix extends StatelessWidget {
  final Map<SurgicalSubfeature, bool> toggles;
  final Function(SurgicalSubfeature subfeature, bool blocked) onToggleChanged;
  final bool isStrictModeActive;
  final VoidCallback? onSeverAllAddictions;
  final VoidCallback? onRestoreDefaults;

  const SubfeatureToggleMatrix({
    super.key,
    required this.toggles,
    required this.onToggleChanged,
    this.isStrictModeActive = false,
    this.onSeverAllAddictions,
    this.onRestoreDefaults,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardColor = isDark ? const Color(0xFF1E222B) : Colors.white;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Action toolbar
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'SUB-FEATURE DISSECTION',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.0,
                color: Colors.grey,
              ),
            ),
            Row(
              children: [
                if (onSeverAllAddictions != null)
                  TextButton.icon(
                    onPressed: isStrictModeActive ? null : onSeverAllAddictions,
                    icon: const Icon(Icons.flash_on_rounded, size: 14, color: Color(0xFFEF4444)),
                    label: const Text(
                      'Sever Traps',
                      style: TextStyle(fontSize: 11, color: Color(0xFFEF4444)),
                    ),
                  ),
                if (onRestoreDefaults != null)
                  TextButton(
                    onPressed: isStrictModeActive ? null : onRestoreDefaults,
                    child: const Text('Reset', style: TextStyle(fontSize: 11)),
                  ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 8),

        // List of all 8 subfeatures
        ListView.separated(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: SurgicalSubfeature.values.length,
          separatorBuilder: (context, index) => const SizedBox(height: 8),
          itemBuilder: (context, index) {
            final feature = SurgicalSubfeature.values[index];
            final meta = SurgicalSubfeatureRegistry.getMetadata(feature);
            final isBlocked = toggles[feature] ?? meta.isDefaultBlocked;

            return Material(
              color: cardColor,
              borderRadius: BorderRadius.circular(16),
              elevation: 0,
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: isBlocked
                        ? const Color(0xFFEF4444).withAlpha(100)
                        : (isDark ? const Color(0xFF2C3240) : const Color(0xFFE2E7F0)),
                    width: isBlocked ? 1.5 : 1.0,
                  ),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                child: Row(
                  children: [
                    // Subfeature Icon
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: _getFeatureColor(meta).withAlpha(25),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(
                        meta.icon,
                        color: _getFeatureColor(meta),
                        size: 22,
                      ),
                    ),
                    const SizedBox(width: 14),

                    // Title & Description
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Flexible(
                                child: Text(
                                  meta.displayName,
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 14,
                                    color: isDark ? Colors.white : Colors.black87,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              const SizedBox(width: 6),
                              _buildAddictionBadge(meta.dopamineAddictionScore, isDark),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            meta.description,
                            style: TextStyle(
                              fontSize: 11,
                              color: isDark ? Colors.white60 : Colors.black54,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),

                    // Switch
                    Switch(
                      value: isBlocked,
                      activeColor: const Color(0xFFEF4444),
                      inactiveTrackColor: meta.isCommunicationChannel
                          ? const Color(0xFF10B981).withAlpha(80)
                          : null,
                      onChanged: isStrictModeActive
                          ? null
                          : (val) {
                              onToggleChanged(feature, val);
                            },
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ],
    );
  }

  Widget _buildAddictionBadge(int score, bool isDark) {
    Color badgeColor;
    String label;
    if (score >= 85) {
      badgeColor = const Color(0xFFEF4444);
      label = 'CRITICAL $score';
    } else if (score >= 65) {
      badgeColor = const Color(0xFFF59E0B);
      label = 'HIGH $score';
    } else if (score >= 40) {
      badgeColor = const Color(0xFF3B82F6);
      label = 'MODERATE $score';
    } else {
      badgeColor = const Color(0xFF10B981);
      label = 'UTILITY $score';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: badgeColor.withAlpha(isDark ? 40 : 25),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: badgeColor.withAlpha(120), width: 0.8),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: badgeColor,
          fontSize: 9,
          fontWeight: FontWeight.bold,
          letterSpacing: 0.5,
        ),
      ),
    );
  }

  Color _getFeatureColor(SubfeatureMetadata meta) {
    if (meta.isCommunicationChannel) return const Color(0xFF10B981);
    if (meta.dopamineAddictionScore >= 85) return const Color(0xFFEF4444);
    if (meta.dopamineAddictionScore >= 65) return const Color(0xFFF59E0B);
    return const Color(0xFF6366F1);
  }
}
