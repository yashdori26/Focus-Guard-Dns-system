import 'dart:math' as math;
import 'package:flutter/foundation.dart';

/// Clinical stages of digital dopamine receptor rehabilitation.
enum DopamineRehabilitationStage {
  acuteWithdrawal, // Days 1 to 3
  neurochemicalReset, // Days 4 to 10
  synapticPruning, // Days 11 to 21
  dopaminergicEquilibrium, // Days 22+
}

/// Information describing a rehabilitation stage.
class DopamineStageInfo {
  final DopamineRehabilitationStage stage;
  final String title;
  final String description;
  final String neurochemicalState;
  final int minDays;
  final int maxDays;

  const DopamineStageInfo({
    required this.stage,
    required this.title,
    required this.description,
    required this.neurochemicalState,
    required this.minDays,
    required this.maxDays,
  });
}

/// Tangible real-world focus equivalents calculated from reclaimed time.
@immutable
class TangibleFocusEquivalents {
  final double booksReadEquivalent;
  final double deepWorkBlocks;
  final double coursesCompleted;
  final double lateNightSleepQualityBoost;
  final int attentionSpanReclaimedSeconds;

  const TangibleFocusEquivalents({
    required this.booksReadEquivalent,
    required this.deepWorkBlocks,
    required this.coursesCompleted,
    required this.lateNightSleepQualityBoost,
    required this.attentionSpanReclaimedSeconds,
  });
}

/// Longitudinal dopamine rehabilitation historian and mathematical receptor simulator.
class DopamineRehabilitationHistorian {
  static const double baselineReceptorSensitivity = 25.0; // Baseline pre-detox sensitivity %
  static const double tauDays = 14.0; // Biological half-life for dopamine receptor up-regulation

  static const List<DopamineStageInfo> stageRegistry = [
    DopamineStageInfo(
      stage: DopamineRehabilitationStage.acuteWithdrawal,
      title: 'Acute Withdrawal',
      description: 'Impulse cravings peak as the brain seeks rapid micro-dopamine hits from infinite feeds.',
      neurochemicalState: 'Low receptor density; dopamine transporter down-regulation.',
      minDays: 1,
      maxDays: 3,
    ),
    DopamineStageInfo(
      stage: DopamineRehabilitationStage.neurochemicalReset,
      title: 'Neurochemical Reset',
      description: 'Receptors begin up-regulation. Mental fog lifts and sustained reading becomes effortless.',
      neurochemicalState: 'D2 receptor density expanding by ~35%. Baseline baseline resetting.',
      minDays: 4,
      maxDays: 10,
    ),
    DopamineStageInfo(
      stage: DopamineRehabilitationStage.synapticPruning,
      title: 'Synaptic Pruning',
      description: 'Compulsive phone picking loops are extinguished. High focus endurance unlocked.',
      neurochemicalState: 'Prefrontal cortex synaptic pruning of addictive doomscroll loops.',
      minDays: 11,
      maxDays: 21,
    ),
    DopamineStageInfo(
      stage: DopamineRehabilitationStage.dopaminergicEquilibrium,
      title: 'Dopaminergic Equilibrium',
      description: 'Complete digital sovereignty. Natural joy in slow, high-value intellectual endeavors.',
      neurochemicalState: 'Optimal homeostasis. Receptors sensitized to subtle, sustained achievements.',
      minDays: 22,
      maxDays: 9999,
    ),
  ];

  /// Calculates predicted receptor sensitivity (0.0% to 100.0%) for a given number of days clean.
  /// Formula: R(t) = R_base + (100 - R_base) * (1 - e^(-t / tau))
  static double calculateReceptorSensitivity(int daysClean) {
    if (daysClean <= 0) return baselineReceptorSensitivity;
    final progress = 1.0 - math.exp(-daysClean / tauDays);
    final sensitivity = baselineReceptorSensitivity + (100.0 - baselineReceptorSensitivity) * progress;
    return sensitivity.clamp(0.0, 100.0);
  }

  /// Resolves the current rehabilitation stage for a user based on days clean.
  static DopamineStageInfo getStageForDays(int daysClean) {
    for (final info in stageRegistry) {
      if (daysClean >= info.minDays && daysClean <= info.maxDays) {
        return info;
      }
    }
    return stageRegistry.last;
  }

  /// Calculates real-world tangible equivalents from reclaimed focus minutes.
  static TangibleFocusEquivalents calculateTangibleEquivalents(int totalReclaimedMinutes, {int lateNightTrapsSevered = 0}) {
    // Average reading speed: 250 words/min. Standard non-fiction book: 70,000 words (~280 mins)
    final books = totalReclaimedMinutes / 280.0;

    // Standard Pomodoro deep work block: 90 minutes
    final deepBlocks = totalReclaimedMinutes / 90.0;

    // Standard online technical course: ~15 hours (900 mins)
    final courses = totalReclaimedMinutes / 900.0;

    // Late-night doomscroll avoidance improves REM sleep quality score (0 - 30% boost)
    final sleepBoost = math.min(30.0, lateNightTrapsSevered * 3.5);

    // Attention span recovery (each 10 hours reclaimed restores ~45s of continuous cognitive attention)
    final attentionSeconds = math.min(300, (totalReclaimedMinutes ~/ 60) * 5);

    return TangibleFocusEquivalents(
      booksReadEquivalent: books,
      deepWorkBlocks: deepBlocks,
      coursesCompleted: courses,
      lateNightSleepQualityBoost: sleepBoost,
      attentionSpanReclaimedSeconds: attentionSeconds,
    );
  }

  /// Generates a 30-day projected curve data points for charting.
  static List<Map<String, double>> generateRecoveryCurveData([int currentDay = 14]) {
    final points = <Map<String, double>>[];
    for (int t = 0; t <= 30; t++) {
      points.add({
        'day': t.toDouble(),
        'sensitivity': calculateReceptorSensitivity(t),
        'isCurrentDay': (t == currentDay) ? 1.0 : 0.0,
      });
    }
    return points;
  }
}
