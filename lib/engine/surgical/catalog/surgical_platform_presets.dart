import 'package:flutter/material.dart';
import '../models/surgical_rule_model.dart';
import 'surgical_platform_catalog.dart';
import 'surgical_subfeature_types.dart';

/// Pre-configured operational profiles for one-tap surgical decoupling.
enum SurgicalPresetType {
  /// Ultra Strict: Blackholes all non-communication subfeatures across all 12 platforms.
  ultraStrictDecoupled,

  /// Student & Scholar: Tailored for YouTube lectures, technical subreddits, and academic queries.
  studentScholar,

  /// Balanced Professional: Decouples social media feeds while keeping LinkedIn InMail, Discord, and Slack channels.
  balancedProfessional,

  /// Communication Only (Pure Messenger): Every platform stripped of all feeds, stories, explore, and search—retaining only direct messages.
  pureCommunicationOnly,

  /// Mindful Friction: Allows subfeatures but enforces a 20-second pause and typing oath before every access.
  mindfulFrictionHeavy,
}

/// Metadata and policy definitions for a surgical decoupling preset.
@immutable
class SurgicalPresetProfile {
  final SurgicalPresetType type;
  final String title;
  final String subtitle;
  final String description;
  final IconData icon;
  final Color accentColor;
  final int dopamineProtectionRating; // 1 - 100
  final bool enableMindfulPause;
  final int defaultPauseSeconds;
  final Map<SurgicalSubfeature, bool> subfeatureOverrides;

  const SurgicalPresetProfile({
    required this.type,
    required this.title,
    required this.subtitle,
    required this.description,
    required this.icon,
    required this.accentColor,
    required this.dopamineProtectionRating,
    this.enableMindfulPause = true,
    this.defaultPauseSeconds = 10,
    required this.subfeatureOverrides,
  });

  /// Applies this preset to a target platform rule, returning an updated model.
  SurgicalRuleModel applyToRule(SurgicalRuleModel rule) {
    final updatedToggles = Map<SurgicalSubfeature, bool>.from(rule.subfeatureToggles);
    for (final entry in subfeatureOverrides.entries) {
      // Direct messages are never blocked unless explicitly forced
      if (entry.key == SurgicalSubfeature.directMessages && !entry.value) {
        updatedToggles[entry.key] = false;
      } else {
        updatedToggles[entry.key] = entry.value;
      }
    }

    return rule.copyWith(
      subfeatureToggles: updatedToggles,
      enableMindfulInterstitial: enableMindfulPause,
      mindfulPauseSeconds: defaultPauseSeconds,
    );
  }
}

/// Central catalog of high-impact surgical decoupling presets.
class SurgicalPlatformPresets {
  SurgicalPlatformPresets._();

  static const SurgicalPresetProfile ultraStrict = SurgicalPresetProfile(
    type: SurgicalPresetType.ultraStrictDecoupled,
    title: 'Ultra Strict Decoupled',
    subtitle: 'Zero dopamine traps. Communication gateways only.',
    description: 'Blackholes Reels, Shorts, Algorithmic Feeds, Explore Grids, and Public Comments across all 12 platforms. Direct messages flow unhindered.',
    icon: Icons.shield_sharp,
    accentColor: Color(0xFFEF4444),
    dopamineProtectionRating: 99,
    enableMindfulPause: false, // Instant network blackhole, no interstitial delay
    defaultPauseSeconds: 0,
    subfeatureOverrides: {
      SurgicalSubfeature.reelsOrShorts: true,
      SurgicalSubfeature.feed: true,
      SurgicalSubfeature.explore: true,
      SurgicalSubfeature.stories: true,
      SurgicalSubfeature.comments: true,
      SurgicalSubfeature.search: false,
      SurgicalSubfeature.directMessages: false,
      SurgicalSubfeature.creatorStudio: false,
    },
  );

  static const SurgicalPresetProfile studentScholar = SurgicalPresetProfile(
    type: SurgicalPresetType.studentScholar,
    title: 'Student & Scholar',
    subtitle: 'YouTube lectures & technical search allowed.',
    description: 'Severely throttles Reels, TikTok FYP, and Instagram Explore, while preserving intentional keyword searches, YouTube lectures, and educational threads.',
    icon: Icons.school_rounded,
    accentColor: Color(0xFF3B82F6),
    dopamineProtectionRating: 85,
    enableMindfulPause: true,
    defaultPauseSeconds: 10,
    subfeatureOverrides: {
      SurgicalSubfeature.reelsOrShorts: true,
      SurgicalSubfeature.feed: true,
      SurgicalSubfeature.explore: true,
      SurgicalSubfeature.stories: true,
      SurgicalSubfeature.comments: false,
      SurgicalSubfeature.search: false,
      SurgicalSubfeature.directMessages: false,
      SurgicalSubfeature.creatorStudio: false,
    },
  );

  static const SurgicalPresetProfile balancedProfessional = SurgicalPresetProfile(
    type: SurgicalPresetType.balancedProfessional,
    title: 'Balanced Professional',
    subtitle: 'LinkedIn, InMail, and Discord workspaces protected.',
    description: 'Severely cuts entertainment addiction traps (Reels, Shorts, TikTok) while keeping LinkedIn InMail, Job Search, and Discord communication fully accessible.',
    icon: Icons.work_outline_rounded,
    accentColor: Color(0xFF10B981),
    dopamineProtectionRating: 80,
    enableMindfulPause: true,
    defaultPauseSeconds: 10,
    subfeatureOverrides: {
      SurgicalSubfeature.reelsOrShorts: true,
      SurgicalSubfeature.feed: true,
      SurgicalSubfeature.explore: true,
      SurgicalSubfeature.stories: false,
      SurgicalSubfeature.comments: false,
      SurgicalSubfeature.search: false,
      SurgicalSubfeature.directMessages: false,
      SurgicalSubfeature.creatorStudio: false,
    },
  );

  static const SurgicalPresetProfile pureCommunicationOnly = SurgicalPresetProfile(
    type: SurgicalPresetType.pureCommunicationOnly,
    title: 'Pure Communication Only',
    subtitle: 'Converts every social app into a dedicated messenger.',
    description: 'Severely blackholes Home Feeds, Reels, Stories, Explore, Search, and Comments. Instagram becomes IG DMs; Twitter becomes X Chat; Reddit becomes Reddit Chat.',
    icon: Icons.mark_chat_read_rounded,
    accentColor: Color(0xFF8B5CF6),
    dopamineProtectionRating: 95,
    enableMindfulPause: false,
    defaultPauseSeconds: 0,
    subfeatureOverrides: {
      SurgicalSubfeature.reelsOrShorts: true,
      SurgicalSubfeature.feed: true,
      SurgicalSubfeature.explore: true,
      SurgicalSubfeature.stories: true,
      SurgicalSubfeature.comments: true,
      SurgicalSubfeature.search: true,
      SurgicalSubfeature.creatorStudio: true,
      SurgicalSubfeature.directMessages: false, // ONLY DMs remain active!
    },
  );

  static const SurgicalPresetProfile mindfulFrictionHeavy = SurgicalPresetProfile(
    type: SurgicalPresetType.mindfulFrictionHeavy,
    title: 'Mindful Friction Heavy',
    subtitle: '25-second reflection delay on all algorithmic traps.',
    description: 'Leaves subfeatures accessible but introduces deep neuro-cognitive friction: a 25-second countdown timer and mandatory pledge typing before access.',
    icon: Icons.spa_rounded,
    accentColor: Color(0xFFF59E0B),
    dopamineProtectionRating: 75,
    enableMindfulPause: true,
    defaultPauseSeconds: 25,
    subfeatureOverrides: {
      SurgicalSubfeature.reelsOrShorts: true,
      SurgicalSubfeature.feed: true,
      SurgicalSubfeature.explore: true,
      SurgicalSubfeature.stories: true,
      SurgicalSubfeature.comments: false,
      SurgicalSubfeature.search: false,
      SurgicalSubfeature.directMessages: false,
      SurgicalSubfeature.creatorStudio: false,
    },
  );

  /// All 5 predefined presets.
  static const List<SurgicalPresetProfile> allPresets = [
    ultraStrict,
    pureCommunicationOnly,
    studentScholar,
    balancedProfessional,
    mindfulFrictionHeavy,
  ];

  /// Resolves preset by type.
  static SurgicalPresetProfile getPreset(SurgicalPresetType type) {
    return allPresets.firstWhere(
      (p) => p.type == type,
      orElse: () => ultraStrict,
    );
  }

  /// Applies a preset profile to an entire collection of platform rules.
  static List<SurgicalRuleModel> applyPresetToAll(
    SurgicalPresetProfile preset,
    List<SurgicalRuleModel> existingRules,
  ) {
    return existingRules.map((r) => preset.applyToRule(r)).toList();
  }
}
