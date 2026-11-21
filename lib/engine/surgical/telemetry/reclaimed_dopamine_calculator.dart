import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import '../catalog/surgical_subfeature_types.dart';
import '../models/surgical_telemetry_snapshot.dart';

/// Milestone achievements awarded based on cognitive recovery and reclaimed focus.
enum DopamineMilestone {
  /// First algorithmic trap intercepted.
  firstSever,

  /// 50 short-form reels or shorts blackholed.
  reelsNemesis,

  /// Over 5 hours of doomscrolling averted.
  timeReclaimer,

  /// Over 20 hours of doomscrolling averted.
  attentionGuardian,

  /// 100 intentional direct messages exchanged with 0 algorithmic feeds opened.
  pureCommunicator,

  /// 72 hours of baseline dopamine receptor sensitivity reset.
  dopamineReset,

  /// Over 50 hours reclaimed; supreme digital sovereignty achieved.
  zenMonk,
}

/// Metadata and badge description for cognitive milestones.
@immutable
class MilestoneMetadata {
  final DopamineMilestone milestone;
  final String title;
  final String description;
  final String iconGlyph;
  final int requiredThreshold;

  const MilestoneMetadata({
    required this.milestone,
    required this.title,
    required this.description,
    required this.iconGlyph,
    required this.requiredThreshold,
  });
}

/// Mathematical model for quantifying dopamine recovery, attention span restoration,
/// cognitive fatigue reduction, and long-term focus projections.
class ReclaimedDopamineCalculator {
  ReclaimedDopamineCalculator._();

  /// Estimated baseline dopamine reset time in hours for neurotransmitter sensitivity.
  static const double dopamineResetTargetHours = 72.0;

  /// Average words per page for book reading equivalent calculation.
  static const int wordsPerPage = 250;

  /// Average reading speed in words per minute.
  static const int wordsPerMinute = 220;

  /// Milestone definitions registry.
  static const Map<DopamineMilestone, MilestoneMetadata> milestoneRegistry = {
    DopamineMilestone.firstSever: MilestoneMetadata(
      milestone: DopamineMilestone.firstSever,
      title: 'First Surgical Sever',
      description: 'First algorithmic distraction successfully decoupled.',
      iconGlyph: '⚡',
      requiredThreshold: 1,
    ),
    DopamineMilestone.reelsNemesis: MilestoneMetadata(
      milestone: DopamineMilestone.reelsNemesis,
      title: 'Reels Nemesis',
      description: 'Severed 50+ vertical video autoplay loops.',
      iconGlyph: '🛡️',
      requiredThreshold: 50,
    ),
    DopamineMilestone.timeReclaimer: MilestoneMetadata(
      milestone: DopamineMilestone.timeReclaimer,
      title: 'Time Reclaimer',
      description: 'Reclaimed 5+ cumulative hours from algorithmic feeds.',
      iconGlyph: '⏳',
      requiredThreshold: 5,
    ),
    DopamineMilestone.attentionGuardian: MilestoneMetadata(
      milestone: DopamineMilestone.attentionGuardian,
      title: 'Attention Guardian',
      description: 'Reclaimed 20+ cumulative hours of focused human life.',
      iconGlyph: '⚔️',
      requiredThreshold: 20,
    ),
    DopamineMilestone.pureCommunicator: MilestoneMetadata(
      milestone: DopamineMilestone.pureCommunicator,
      title: 'Pure Communicator',
      description: 'Exchanged 100+ intentional messages without opening a single feed.',
      iconGlyph: '💬',
      requiredThreshold: 100,
    ),
    DopamineMilestone.dopamineReset: MilestoneMetadata(
      milestone: DopamineMilestone.dopamineReset,
      title: 'Neurochemical Reset',
      description: 'Achieved 72 hours of uninterrupted short-form decoupling.',
      iconGlyph: '🧠',
      requiredThreshold: 72,
    ),
    DopamineMilestone.zenMonk: MilestoneMetadata(
      milestone: DopamineMilestone.zenMonk,
      title: 'Zen Monk',
      description: 'Reclaimed 50+ hours; complete mastery over your devices.',
      iconGlyph: '🧘',
      requiredThreshold: 50,
    ),
  };

  /// Calculates the Dopamine Recovery Percentage (0.0% to 100.0%) based on cumulative hours saved.
  /// Uses a logarithmic saturation curve: R(t) = 100 * (1 - e^(-t / 24))
  static double computeDopamineSensitivityRecovery(double hoursReclaimed) {
    if (hoursReclaimed <= 0) return 0.0;
    final recovery = 100.0 * (1.0 - math.exp(-hoursReclaimed / 24.0));
    return double.parse(recovery.clamp(0.0, 100.0).toStringAsFixed(1));
  }

  /// Computes the Cognitive Fatigue Index (0 to 100), where lower is better.
  /// Context-switching fatigue decreases as unhindered intentional communication increases.
  static int computeCognitiveFatigueIndex({
    required int totalInterceptions,
    required int allowedChats,
  }) {
    if (totalInterceptions == 0 && allowedChats == 0) return 30; // neutral
    // Higher interceptions mean the user was exposed to fewer distraction triggers
    final baseFatigue = 85.0;
    final reliefFactor = (totalInterceptions * 1.8) + (allowedChats * 0.4);
    final fatigue = (baseFatigue - reliefFactor).clamp(12.0, 95.0);
    return fatigue.round();
  }

  /// Calculates equivalent books read that could fit in the reclaimed doomscroll hours.
  static double computeBooksReadEquivalent(double hoursReclaimed) {
    if (hoursReclaimed <= 0) return 0.0;
    final totalMinutes = hoursReclaimed * 60.0;
    final totalWords = totalMinutes * wordsPerMinute;
    // Assume average book is 65,000 words (~260 pages)
    final books = totalWords / 65000.0;
    return double.parse(books.toStringAsFixed(1));
  }

  /// Calculates equivalent deep work 90-minute ultradian cycles reclaimed.
  static double computeDeepWorkCyclesReclaimed(double hoursReclaimed) {
    if (hoursReclaimed <= 0) return 0.0;
    final cycles = hoursReclaimed / 1.5;
    return double.parse(cycles.toStringAsFixed(1));
  }

  /// Projects 30-day reclaimed hours based on current daily average.
  static double project30DayReclaimedHours(double dailyHoursReclaimed) {
    return double.parse((dailyHoursReclaimed * 30.0).toStringAsFixed(1));
  }

  /// Projects 1-year reclaimed hours based on current daily average.
  static double project1YearReclaimedHours(double dailyHoursReclaimed) {
    return double.parse((dailyHoursReclaimed * 365.25).toStringAsFixed(1));
  }

  /// Evaluates which milestone achievements the user has unlocked.
  static List<MilestoneMetadata> evaluateUnlockedMilestones(
    SurgicalTelemetrySnapshot snapshot,
  ) {
    final List<MilestoneMetadata> unlocked = [];

    // First sever
    if (snapshot.totalInterceptions >= 1) {
      unlocked.add(milestoneRegistry[DopamineMilestone.firstSever]!);
    }

    // Reels Nemesis
    if (snapshot.blockedReelsCount >= 50) {
      unlocked.add(milestoneRegistry[DopamineMilestone.reelsNemesis]!);
    }

    // Time Reclaimer (5h)
    if (snapshot.estimatedHoursReclaimed >= 5.0) {
      unlocked.add(milestoneRegistry[DopamineMilestone.timeReclaimer]!);
    }

    // Attention Guardian (20h)
    if (snapshot.estimatedHoursReclaimed >= 20.0) {
      unlocked.add(milestoneRegistry[DopamineMilestone.attentionGuardian]!);
    }

    // Pure Communicator (100 chats, 0 feed)
    if (snapshot.allowedChatCount >= 100 && snapshot.blockedFeedCount > 0) {
      unlocked.add(milestoneRegistry[DopamineMilestone.pureCommunicator]!);
    }

    // Dopamine Reset (72h)
    if (snapshot.estimatedHoursReclaimed >= 72.0) {
      unlocked.add(milestoneRegistry[DopamineMilestone.dopamineReset]!);
    }

    // Zen Monk (50h)
    if (snapshot.estimatedHoursReclaimed >= 50.0) {
      unlocked.add(milestoneRegistry[DopamineMilestone.zenMonk]!);
    }

    return unlocked;
  }

  /// Returns inspiring contextual text summarizing the user's cognitive gains.
  static String generateCognitiveSummary(SurgicalTelemetrySnapshot snapshot) {
    final hours = snapshot.estimatedHoursReclaimed;
    final books = computeBooksReadEquivalent(hours);
    final cycles = computeDeepWorkCyclesReclaimed(hours);
    final recovery = computeDopamineSensitivityRecovery(hours);

    return 'By severing ${snapshot.totalInterceptions} addiction loops while protecting '
        '${snapshot.allowedChatCount} direct messages, you reclaimed ~$hours hours of life '
        '(equivalent to reading ~$books books or ~$cycles deep work cycles). '
        'Dopamine receptor sensitivity restored by $recovery%.';
  }
}
