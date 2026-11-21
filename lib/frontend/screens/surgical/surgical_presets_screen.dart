import 'package:flutter/material.dart';
import '../../../engine/surgical/catalog/surgical_platform_presets.dart';
import '../../../engine/surgical/catalog/surgical_subfeature_types.dart';
import '../../../engine/surgical/core/surgical_policy_evaluator.dart';

/// Screen enabling users to browse, compare, and apply one-tap surgical decoupling presets.
class SurgicalPresetsScreen extends StatefulWidget {
  final SurgicalPolicyEvaluator evaluator;

  const SurgicalPresetsScreen({
    super.key,
    required this.evaluator,
  });

  @override
  State<SurgicalPresetsScreen> createState() => _SurgicalPresetsScreenState();
}

class _SurgicalPresetsScreenState extends State<SurgicalPresetsScreen> {
  SurgicalPresetType _selectedPreset = SurgicalPresetType.ultraStrictDecoupled;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final scaffoldBg = isDark ? const Color(0xFF13151B) : const Color(0xFFF8FAFC);
    final cardColor = isDark ? const Color(0xFF1E222B) : Colors.white;

    final activePreset = SurgicalPlatformPresets.getPreset(_selectedPreset);

    return Scaffold(
      backgroundColor: scaffoldBg,
      appBar: AppBar(
        title: const Text('Surgical Decoupling Presets'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header Info Card
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: cardColor,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: isDark ? const Color(0xFF2C3240) : const Color(0xFFE2E7F0),
                ),
              ),
              child: const Row(
                children: [
                  Icon(Icons.auto_awesome_rounded, color: Color(0xFF6366F1), size: 28),
                  SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'One-Tap Architectural Presets',
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                        ),
                        SizedBox(height: 4),
                        Text(
                          'Instantly align all 12 monitored platforms to your desired focus profile.',
                          style: TextStyle(fontSize: 11, color: Colors.grey),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            const Text(
              'SELECT A FOCUS PROFILE',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.0,
                color: Colors.grey,
              ),
            ),
            const SizedBox(height: 10),

            // Presets Cards List
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: SurgicalPlatformPresets.allPresets.length,
              separatorBuilder: (context, index) => const SizedBox(height: 10),
              itemBuilder: (context, index) {
                final preset = SurgicalPlatformPresets.allPresets[index];
                final isSelected = _selectedPreset == preset.type;

                return Material(
                  color: cardColor,
                  borderRadius: BorderRadius.circular(20),
                  child: InkWell(
                    onTap: () {
                      setState(() {
                        _selectedPreset = preset.type;
                      });
                    },
                    borderRadius: BorderRadius.circular(20),
                    child: Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: isSelected
                              ? preset.accentColor
                              : (isDark ? const Color(0xFF2C3240) : const Color(0xFFE2E7F0)),
                          width: isSelected ? 2.0 : 1.0,
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
                                  color: preset.accentColor.withAlpha(25),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Icon(preset.icon, color: preset.accentColor, size: 22),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      preset.title,
                                      style: TextStyle(
                                        fontSize: 15,
                                        fontWeight: FontWeight.bold,
                                        color: isDark ? Colors.white : Colors.black87,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      preset.subtitle,
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: isDark ? Colors.white60 : Colors.black54,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              _buildProtectionScorePill(preset.dopamineProtectionRating, isDark),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Text(
                            preset.description,
                            style: TextStyle(
                              fontSize: 12,
                              color: isDark ? Colors.white70 : Colors.black87,
                            ),
                          ),
                          if (isSelected) ...[
                            const SizedBox(height: 14),
                            _buildSubfeatureBreakdown(preset, isDark),
                          ],
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
            const SizedBox(height: 24),

            // Apply Button
            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton.icon(
                onPressed: () => _confirmAndApplyPreset(activePreset),
                style: ElevatedButton.styleFrom(
                  backgroundColor: activePreset.accentColor,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                ),
                icon: const Icon(Icons.check_circle_outline_rounded),
                label: Text(
                  'Apply "${activePreset.title}" to All Platforms',
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                ),
              ),
            ),
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  Widget _buildProtectionScorePill(int score, bool isDark) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xFF10B981).withAlpha(isDark ? 40 : 25),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFF10B981).withAlpha(120), width: 0.8),
      ),
      child: Text(
        '$score% SHIELD',
        style: const TextStyle(
          color: Color(0xFF10B981),
          fontSize: 9,
          fontWeight: FontWeight.bold,
          letterSpacing: 0.5,
        ),
      ),
    );
  }

  Widget _buildSubfeatureBreakdown(SurgicalPresetProfile preset, bool isDark) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF13151B) : const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Wrap(
        spacing: 6,
        runSpacing: 6,
        children: preset.subfeatureOverrides.entries.map((e) {
          final isBlocked = e.value;
          final color = isBlocked ? const Color(0xFFEF4444) : const Color(0xFF10B981);
          final action = isBlocked ? 'Blocked' : 'Allowed';
          return Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: color.withAlpha(isDark ? 30 : 20),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: color.withAlpha(80)),
            ),
            child: Text(
              '${e.key.name}: $action',
              style: TextStyle(fontSize: 10, color: color, fontWeight: FontWeight.bold),
            ),
          );
        }).toList(),
      ),
    );
  }

  void _confirmAndApplyPreset(SurgicalPresetProfile preset) {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text('Apply ${preset.title}?'),
          content: Text(
            'This will update surgical subfeature toggles across all 12 monitored platforms according to the ${preset.title} profile.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: preset.accentColor),
              onPressed: () {
                for (final rule in widget.evaluator.compiledRules.values) {
                  for (final entry in preset.subfeatureOverrides.entries) {
                    widget.evaluator.setSubfeatureToggle(
                      platformId: rule.platformId,
                      subfeature: entry.key,
                      blocked: entry.value,
                    );
                  }
                }
                Navigator.of(context).pop();
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Applied "${preset.title}" across all platforms.'),
                    backgroundColor: const Color(0xFF10B981),
                  ),
                );
              },
              child: const Text('Apply Preset', style: TextStyle(color: Colors.white)),
            ),
          ],
        );
      },
    );
  }
}
