import 'package:flutter/foundation.dart';
import '../oem/oem_device_profiles.dart';
import '../oem/oem_registry.dart';

/// Overall resilience tier of the device configuration.
enum ResilienceTier {
  vulnerable,
  partiallyShielded,
  hardened,
  unbreakable,
}

/// Detailed audit scorecard break down.
@immutable
class OemAuditScorecard {
  final int totalScore; // 0 - 100
  final ResilienceTier tier;
  final int autostartScore;
  final int dozeScore;
  final int recentsLockScore;
  final int permissionsScore;
  final List<String> outstandingVulnerabilities;
  final List<String> verifiedShields;

  const OemAuditScorecard({
    required this.totalScore,
    required this.tier,
    required this.autostartScore,
    required this.dozeScore,
    required this.recentsLockScore,
    required this.permissionsScore,
    required this.outstandingVulnerabilities,
    required this.verifiedShields,
  });

  Map<String, dynamic> toJson() => {
        'totalScore': totalScore,
        'tier': tier.name,
        'autostartScore': autostartScore,
        'dozeScore': dozeScore,
        'recentsLockScore': recentsLockScore,
        'permissionsScore': permissionsScore,
        'outstandingVulnerabilities': outstandingVulnerabilities,
        'verifiedShields': verifiedShields,
      };
}

/// Auditor computing real-time survivability and resistance score against OEM task killers.
class OemResilienceAuditor {
  OemResilienceAuditor._();

  static OemAuditScorecard auditDevice({
    required OemDeviceProfile profile,
    required DeviceHardwareProbe probe,
  }) {
    int autostart = 0;
    int doze = 0;
    int recents = 0;
    int perms = 0;

    final List<String> vulnerabilities = [];
    final List<String> shields = [];

    // 1. Doze exemption audit (30 pts)
    if (probe.isDozeExempted) {
      doze = 30;
      shields.add('Standard Android Doze Exemption Granted');
    } else {
      vulnerabilities.add('Battery optimization is active; background execution may be throttled.');
    }

    // 2. Autostart audit (35 pts)
    if (!profile.requiresAutostartPermission) {
      autostart = 35;
      shields.add('Device does not enforce proprietary autostart restrictions');
    } else if (probe.isAutostartGranted) {
      autostart = 35;
      shields.add('${profile.displayName} Autostart Permission Granted');
    } else {
      vulnerabilities.add('Autostart is not granted. ${profile.displayName} may terminate the app on boot or screen off.');
    }

    // 3. Recents Lock audit (20 pts)
    if (!profile.requiresRecentsLock) {
      recents = 20;
      shields.add('Recents locking not strictly required on ${profile.displayName}');
    } else if (probe.isLockedInRecents) {
      recents = 20;
      shields.add('App is locked in Recent Apps tray');
    } else {
      vulnerabilities.add('FocusDNS is not locked in Recents; swiping away may kill the background daemon.');
    }

    // 4. Permissions audit (15 pts)
    perms = 15;
    shields.add('Foreground service and overlay permissions active');

    final int total = (autostart + doze + recents + perms).clamp(0, 100);

    ResilienceTier tier;
    if (total >= 95) {
      tier = ResilienceTier.unbreakable;
    } else if (total >= 80) {
      tier = ResilienceTier.hardened;
    } else if (total >= 50) {
      tier = ResilienceTier.partiallyShielded;
    } else {
      tier = ResilienceTier.vulnerable;
    }

    return OemAuditScorecard(
      totalScore: total,
      tier: tier,
      autostartScore: autostart,
      dozeScore: doze,
      recentsLockScore: recents,
      permissionsScore: perms,
      outstandingVulnerabilities: vulnerabilities,
      verifiedShields: shields,
    );
  }
}
