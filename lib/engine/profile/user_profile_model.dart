import 'package:flutter/foundation.dart';

/// Primary focus archetypes guiding decoupling intensity and notifications.
enum FocusArchetype {
  studentScholar, // High block on Shorts/Reels; keeps educational YouTube & Wikipedia
  deepWorkEngineer, // Zero tolerance for social feeds; keeps GitHub, StackOverflow, Docs
  executiveSovereign, // Clean communication only; keeps Email, InMail, Slack, Calendar
  zenMonk, // Total media severing; pure intentionality
}

/// Metadata and badge for a focus archetype.
class FocusArchetypeInfo {
  final FocusArchetype archetype;
  final String title;
  final String subtitle;
  final String icon;
  final int recommendedDailyFocusHours;

  const FocusArchetypeInfo({
    required this.archetype,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.recommendedDailyFocusHours,
  });
}

/// User profile model encapsulating identity, focus archetype, lifetime achievements,
/// security policies, and dopamine sovereignty rank.
@immutable
class UserProfileModel {
  final String userId;
  final String displayName;
  final String? email;
  final String? avatarUrl;
  final FocusArchetype archetype;
  final DateTime createdAt;
  final int totalLifetimeHoursReclaimed;
  final int totalLifetimeTrapsSevered;
  final int bestLifetimeStreakDays;
  final int dopamineProtectionRating; // 0 to 100
  final bool biometricUnlockRequired;
  final bool strictAntiUninstallEnabled;
  final bool emergencyPartnerRequired;
  final String? pairedPartnerEmail;

  const UserProfileModel({
    required this.userId,
    required this.displayName,
    this.email,
    this.avatarUrl,
    required this.archetype,
    required this.createdAt,
    required this.totalLifetimeHoursReclaimed,
    required this.totalLifetimeTrapsSevered,
    required this.bestLifetimeStreakDays,
    required this.dopamineProtectionRating,
    required this.biometricUnlockRequired,
    required this.strictAntiUninstallEnabled,
    required this.emergencyPartnerRequired,
    this.pairedPartnerEmail,
  });

  /// Factory producing a new default user profile.
  factory UserProfileModel.initial({
    String userId = 'usr_sovereign_default',
    String displayName = 'Focus Sovereign',
  }) {
    return UserProfileModel(
      userId: userId,
      displayName: displayName,
      email: null,
      avatarUrl: null,
      archetype: FocusArchetype.deepWorkEngineer,
      createdAt: DateTime.now(),
      totalLifetimeHoursReclaimed: 0,
      totalLifetimeTrapsSevered: 0,
      bestLifetimeStreakDays: 0,
      dopamineProtectionRating: 85,
      biometricUnlockRequired: false,
      strictAntiUninstallEnabled: true,
      emergencyPartnerRequired: false,
      pairedPartnerEmail: null,
    );
  }

  /// Archetype info descriptor.
  FocusArchetypeInfo get archetypeInfo {
    switch (archetype) {
      case FocusArchetype.studentScholar:
        return const FocusArchetypeInfo(
          archetype: FocusArchetype.studentScholar,
          title: 'Student Scholar',
          subtitle: 'Blocks Reels/Shorts; keeps educational video tutorials & lectures',
          icon: '🎓',
          recommendedDailyFocusHours: 4,
        );
      case FocusArchetype.deepWorkEngineer:
        return const FocusArchetypeInfo(
          archetype: FocusArchetype.deepWorkEngineer,
          title: 'Deep Work Engineer',
          subtitle: 'Zero distraction tolerance; keeps GitHub, docs, and direct technical chat',
          icon: '💻',
          recommendedDailyFocusHours: 6,
        );
      case FocusArchetype.executiveSovereign:
        return const FocusArchetypeInfo(
          archetype: FocusArchetype.executiveSovereign,
          title: 'Executive Sovereign',
          subtitle: 'Decouples feeds from InMail, team messages, and scheduling tools',
          icon: '👔',
          recommendedDailyFocusHours: 5,
        );
      case FocusArchetype.zenMonk:
        return const FocusArchetypeInfo(
          archetype: FocusArchetype.zenMonk,
          title: 'Zen Monk',
          subtitle: 'Full dopamine blackhole; digital minimalism and radical presence',
          icon: '🧘',
          recommendedDailyFocusHours: 8,
        );
    }
  }

  /// Evaluates honorific title based on reclaimed hours.
  String get sovereigntyRank {
    if (totalLifetimeHoursReclaimed >= 500) return 'Dopamine Sovereign Grandmaster';
    if (totalLifetimeHoursReclaimed >= 250) return 'Cognitive Fortress Master';
    if (totalLifetimeHoursReclaimed >= 100) return 'Deep Work Centurion';
    if (totalLifetimeHoursReclaimed >= 50) return 'Focus Vanguard';
    if (totalLifetimeHoursReclaimed >= 20) return 'Intentional Apprentice';
    return 'Novice Reclaimer';
  }

  UserProfileModel copyWith({
    String? userId,
    String? displayName,
    String? email,
    String? avatarUrl,
    FocusArchetype? archetype,
    DateTime? createdAt,
    int? totalLifetimeHoursReclaimed,
    int? totalLifetimeTrapsSevered,
    int? bestLifetimeStreakDays,
    int? dopamineProtectionRating,
    bool? biometricUnlockRequired,
    bool? strictAntiUninstallEnabled,
    bool? emergencyPartnerRequired,
    String? pairedPartnerEmail,
  }) {
    return UserProfileModel(
      userId: userId ?? this.userId,
      displayName: displayName ?? this.displayName,
      email: email ?? this.email,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      archetype: archetype ?? this.archetype,
      createdAt: createdAt ?? this.createdAt,
      totalLifetimeHoursReclaimed: totalLifetimeHoursReclaimed ?? this.totalLifetimeHoursReclaimed,
      totalLifetimeTrapsSevered: totalLifetimeTrapsSevered ?? this.totalLifetimeTrapsSevered,
      bestLifetimeStreakDays: bestLifetimeStreakDays ?? this.bestLifetimeStreakDays,
      dopamineProtectionRating: dopamineProtectionRating ?? this.dopamineProtectionRating,
      biometricUnlockRequired: biometricUnlockRequired ?? this.biometricUnlockRequired,
      strictAntiUninstallEnabled: strictAntiUninstallEnabled ?? this.strictAntiUninstallEnabled,
      emergencyPartnerRequired: emergencyPartnerRequired ?? this.emergencyPartnerRequired,
      pairedPartnerEmail: pairedPartnerEmail ?? this.pairedPartnerEmail,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'userId': userId,
      'displayName': displayName,
      'email': email,
      'avatarUrl': avatarUrl,
      'archetype': archetype.name,
      'createdAt': createdAt.toIso8601String(),
      'totalLifetimeHoursReclaimed': totalLifetimeHoursReclaimed,
      'totalLifetimeTrapsSevered': totalLifetimeTrapsSevered,
      'bestLifetimeStreakDays': bestLifetimeStreakDays,
      'dopamineProtectionRating': dopamineProtectionRating,
      'biometricUnlockRequired': biometricUnlockRequired,
      'strictAntiUninstallEnabled': strictAntiUninstallEnabled,
      'emergencyPartnerRequired': emergencyPartnerRequired,
      'pairedPartnerEmail': pairedPartnerEmail,
    };
  }

  factory UserProfileModel.fromJson(Map<String, dynamic> json) {
    return UserProfileModel(
      userId: json['userId'] as String? ?? 'usr_default',
      displayName: json['displayName'] as String? ?? 'Focus Sovereign',
      email: json['email'] as String?,
      avatarUrl: json['avatarUrl'] as String?,
      archetype: FocusArchetype.values.firstWhere(
        (e) => e.name == json['archetype'],
        orElse: () => FocusArchetype.deepWorkEngineer,
      ),
      createdAt: json['createdAt'] != null
          ? DateTime.tryParse(json['createdAt'] as String) ?? DateTime.now()
          : DateTime.now(),
      totalLifetimeHoursReclaimed: json['totalLifetimeHoursReclaimed'] as int? ?? 0,
      totalLifetimeTrapsSevered: json['totalLifetimeTrapsSevered'] as int? ?? 0,
      bestLifetimeStreakDays: json['bestLifetimeStreakDays'] as int? ?? 0,
      dopamineProtectionRating: json['dopamineProtectionRating'] as int? ?? 85,
      biometricUnlockRequired: json['biometricUnlockRequired'] as bool? ?? false,
      strictAntiUninstallEnabled: json['strictAntiUninstallEnabled'] as bool? ?? true,
      emergencyPartnerRequired: json['emergencyPartnerRequired'] as bool? ?? false,
      pairedPartnerEmail: json['pairedPartnerEmail'] as String?,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is UserProfileModel &&
          runtimeType == other.runtimeType &&
          userId == other.userId &&
          displayName == other.displayName &&
          archetype == other.archetype &&
          totalLifetimeHoursReclaimed == other.totalLifetimeHoursReclaimed &&
          dopamineProtectionRating == other.dopamineProtectionRating;

  @override
  int get hashCode => Object.hash(
        userId,
        displayName,
        archetype,
        totalLifetimeHoursReclaimed,
        dopamineProtectionRating,
      );
}
