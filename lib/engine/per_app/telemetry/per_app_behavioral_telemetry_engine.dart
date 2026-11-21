import 'dart:math';
import 'package:flutter/foundation.dart';
import '../models/app_usage_record.dart';

/// Behavioral analytics tracking dopamine impulse velocity and longitudinal compliance.
class PerAppBehavioralTelemetryEngine {
  /// Computes the Dopamine Addiction Velocity Index (DAVI) on a 0-100 scale.
  /// Evaluates launch frequency, night-time usage proportion, and blocked intervention attempts.
  static double computeDopamineVelocityIndex({
    required int totalLaunches,
    required int totalForegroundSeconds,
    required int totalBlockedAttempts,
    required List<int> hourlyUsageSeconds,
  }) {
    if (totalForegroundSeconds == 0 && totalLaunches == 0) return 0.0;

    // 1. Launch density score (frequent opens indicate compulsive habit loops)
    final launchDensity = (totalLaunches / max(1, totalForegroundSeconds / 3600.0)) * 5.0;
    final normalizedLaunchScore = min(35.0, launchDensity);

    // 2. High-risk night-time usage (10 PM to 4 AM)
    int nightUsageSeconds = 0;
    for (int h in [22, 23, 0, 1, 2, 3]) {
      if (h < hourlyUsageSeconds.length) {
        nightUsageSeconds += hourlyUsageSeconds[h];
      }
    }
    final nightRatio = totalForegroundSeconds > 0 ? (nightUsageSeconds / totalForegroundSeconds) : 0.0;
    final nightPenalty = nightRatio * 35.0;

    // 3. Craving resistance friction score (blocked attempts when locked)
    final cravingImpulses = min(30.0, totalBlockedAttempts * 4.0);

    final rawScore = normalizedLaunchScore + nightPenalty + cravingImpulses;
    return rawScore.clamp(0.0, 100.0);
  }

  /// Calculates total hours reclaimed from addictive doomscrolling today.
  static double calculateReclaimedHours({
    required int baselineDailySeconds,
    required int actualForegroundSeconds,
  }) {
    final diffSec = baselineDailySeconds - actualForegroundSeconds;
    if (diffSec <= 0) return 0.0;
    return (diffSec / 3600.0);
  }

  /// Evaluates Habit Reversal Compliance Rate (0-100%).
  static double computeComplianceRate({
    required int successfulFocusSessions,
    required int totalSessionAttempts,
    required int emergencyUnlocksUsed,
  }) {
    if (totalSessionAttempts == 0) return 100.0;
    final baseCompliance = (successfulFocusSessions / totalSessionAttempts) * 100.0;
    final penalty = emergencyUnlocksUsed * 15.0;
    return (baseCompliance - penalty).clamp(0.0, 100.0);
  }

  /// Generates behavioral insight diagnosis message.
  static String generateBehavioralDiagnosis(double daviScore) {
    if (daviScore >= 80.0) {
      return 'Critical Dopamine Trap: Severe compulsive loop detected. Highly recommended to engage Strict Unbreakable Lockout.';
    } else if (daviScore >= 55.0) {
      return 'Elevated Craving Index: Moderate habit friction observed. Daily quota allowance advised.';
    } else if (daviScore >= 25.0) {
      return 'Balanced Digital Hygiene: Controlled interaction patterns. Keep maintaining healthy bounds.';
    } else {
      return 'Optimal Cognitive Serenity: Zero impulsive triggers detected. Prefrontal autonomy fully restored.';
    }
  }
}
