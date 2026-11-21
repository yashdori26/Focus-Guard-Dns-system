import 'package:flutter/foundation.dart';
import '../catalog/surgical_subfeature_types.dart';
import 'surgical_interception_event.dart';

/// Aggregated, real-time snapshot of surgical decoupling metrics, dopamine recovery,
/// and selective communication flow.
@immutable
class SurgicalTelemetrySnapshot {
  /// When this snapshot was calculated.
  final DateTime timestamp;

  /// Total number of algorithmic addiction traps intercepted.
  final int totalInterceptions;

  /// Number of infinite home timeline feed requests blackholed.
  final int blockedFeedCount;

  /// Number of vertical short-form video reels/shorts blocked.
  final int blockedReelsCount;

  /// Number of algorithmic explore/discovery grid accesses prevented.
  final int blockedExploreCount;

  /// Number of ephemeral story carousels intercepted.
  final int blockedStoriesCount;

  /// Number of public comment threads blocked.
  final int blockedCommentsCount;

  /// Number of intentional direct messages/chat packets permitted and protected.
  final int allowedChatCount;

  /// Number of intentional search queries permitted and protected.
  final int allowedSearchCount;

  /// Number of monitored platforms actively being dissected.
  final int activePlatformsCount;

  /// Cumulative doomscroll time saved, expressed in hours.
  final double estimatedHoursReclaimed;

  /// Cumulative network bandwidth conserved by blocking CDN video streams.
  final double bandwidthSavedMegabytes;

  /// Overall Dopamine Decoupling Index score (0 to 100).
  /// 100 represents full freedom from algorithmic addiction with intact communication.
  final int dopamineIndexScore;

  /// Breakdown of interception counts indexed by platformId.
  final Map<String, int> platformInterceptionCounts;

  /// Breakdown of interception counts indexed by subfeature vector.
  final Map<SurgicalSubfeature, int> subfeatureInterceptionCounts;

  /// 24-hour activity distribution (counts per hour of day from 0 to 23).
  final List<int> hourlyActivityCurve;

  /// Most active addiction platform intercepted today.
  final String topAddictionPlatform;

  /// Sub-feature vector that incurred the highest interception count.
  final SurgicalSubfeature topSeveredSubfeature;

  const SurgicalTelemetrySnapshot({
    required this.timestamp,
    required this.totalInterceptions,
    required this.blockedFeedCount,
    required this.blockedReelsCount,
    required this.blockedExploreCount,
    required this.blockedStoriesCount,
    required this.blockedCommentsCount,
    required this.allowedChatCount,
    required this.allowedSearchCount,
    required this.activePlatformsCount,
    required this.estimatedHoursReclaimed,
    required this.bandwidthSavedMegabytes,
    required this.dopamineIndexScore,
    required this.platformInterceptionCounts,
    required this.subfeatureInterceptionCounts,
    required this.hourlyActivityCurve,
    this.topAddictionPlatform = 'None',
    this.topSeveredSubfeature = SurgicalSubfeature.reelsOrShorts,
  });

  /// Factory creating an initial empty snapshot.
  factory SurgicalTelemetrySnapshot.empty() => SurgicalTelemetrySnapshot(
        timestamp: DateTime.now(),
        totalInterceptions: 0,
        blockedFeedCount: 0,
        blockedReelsCount: 0,
        blockedExploreCount: 0,
        blockedStoriesCount: 0,
        blockedCommentsCount: 0,
        allowedChatCount: 0,
        allowedSearchCount: 0,
        activePlatformsCount: 0,
        estimatedHoursReclaimed: 0.0,
        bandwidthSavedMegabytes: 0.0,
        dopamineIndexScore: 50,
        platformInterceptionCounts: const {},
        subfeatureInterceptionCounts: const {},
        hourlyActivityCurve: List<int>.filled(24, 0),
        topAddictionPlatform: 'None',
        topSeveredSubfeature: SurgicalSubfeature.reelsOrShorts,
      );

  /// Computes a comprehensive snapshot from an audit list of interception events
  /// and communication counters.
  factory SurgicalTelemetrySnapshot.fromEvents({
    required List<SurgicalInterceptionEvent> events,
    int allowedChats = 0,
    int allowedSearches = 0,
    int activePlatforms = 12,
  }) {
    if (events.isEmpty) {
      return SurgicalTelemetrySnapshot.empty().copyWith(
        allowedChatCount: allowedChats,
        allowedSearchCount: allowedSearches,
        activePlatformsCount: activePlatforms,
      );
    }

    int feed = 0;
    int reels = 0;
    int explore = 0;
    int stories = 0;
    int comments = 0;
    int totalSecs = 0;
    int totalBytes = 0;

    final Map<String, int> platCounts = {};
    final Map<SurgicalSubfeature, int> subCounts = {};
    final List<int> hourly = List<int>.filled(24, 0);

    for (final evt in events) {
      platCounts[evt.platformId] = (platCounts[evt.platformId] ?? 0) + 1;
      subCounts[evt.subfeature] = (subCounts[evt.subfeature] ?? 0) + 1;

      final hour = evt.timestamp.hour;
      if (hour >= 0 && hour < 24) {
        hourly[hour] = hourly[hour] + 1;
      }

      totalSecs += evt.estimatedSecondsSaved;
      totalBytes += evt.estimatedBytesBlocked;

      switch (evt.subfeature) {
        case SurgicalSubfeature.feed:
          feed++;
          break;
        case SurgicalSubfeature.reelsOrShorts:
          reels++;
          break;
        case SurgicalSubfeature.explore:
          explore++;
          break;
        case SurgicalSubfeature.stories:
          stories++;
          break;
        case SurgicalSubfeature.comments:
          comments++;
          break;
        case SurgicalSubfeature.directMessages:
        case SurgicalSubfeature.search:
        case SurgicalSubfeature.creatorStudio:
          break;
      }
    }

    // Determine top platform
    String topPlat = 'None';
    int maxPlatCount = 0;
    platCounts.forEach((plat, count) {
      if (count > maxPlatCount) {
        maxPlatCount = count;
        topPlat = plat;
      }
    });

    // Determine top subfeature
    SurgicalSubfeature topSub = SurgicalSubfeature.reelsOrShorts;
    int maxSubCount = 0;
    subCounts.forEach((sub, count) {
      if (count > maxSubCount) {
        maxSubCount = count;
        topSub = sub;
      }
    });

    final hoursReclaimed = totalSecs / 3600.0;
    final mbSaved = totalBytes / (1024.0 * 1024.0);

    // Dopamine Index formula:
    // Base 50 + points for blocked high-addiction loops + points for intentional communication
    final addictionHits = (reels * 3) + (feed * 2) + (explore * 2) + stories + comments;
    final communicationBonus = (allowedChats > 0) ? (allowedChats * 0.5).clamp(0, 15).toInt() : 0;
    final score = (50 + (addictionHits * 1.5).toInt() + communicationBonus).clamp(20, 100);

    return SurgicalTelemetrySnapshot(
      timestamp: DateTime.now(),
      totalInterceptions: events.length,
      blockedFeedCount: feed,
      blockedReelsCount: reels,
      blockedExploreCount: explore,
      blockedStoriesCount: stories,
      blockedCommentsCount: comments,
      allowedChatCount: allowedChats,
      allowedSearchCount: allowedSearches,
      activePlatformsCount: activePlatforms,
      estimatedHoursReclaimed: double.parse(hoursReclaimed.toStringAsFixed(2)),
      bandwidthSavedMegabytes: double.parse(mbSaved.toStringAsFixed(1)),
      dopamineIndexScore: score,
      platformInterceptionCounts: platCounts,
      subfeatureInterceptionCounts: subCounts,
      hourlyActivityCurve: hourly,
      topAddictionPlatform: topPlat,
      topSeveredSubfeature: topSub,
    );
  }

  /// Ratio of blocked reels to allowed chat messages (e.g. 4.2x dopamine protection).
  double get reelsToChatRatio {
    if (allowedChatCount == 0) return blockedReelsCount.toDouble();
    return blockedReelsCount / allowedChatCount;
  }

  /// Total averted doomscroll minutes.
  int get totalAvertedMinutes => (estimatedHoursReclaimed * 60).round();

  /// Human-readable bandwidth string (e.g. '420.5 MB' or '1.4 GB').
  String get formattedBandwidthSaved {
    if (bandwidthSavedMegabytes >= 1024.0) {
      final gb = bandwidthSavedMegabytes / 1024.0;
      return '${gb.toStringAsFixed(2)} GB';
    }
    return '${bandwidthSavedMegabytes.toStringAsFixed(1)} MB';
  }

  /// Dopamine health tier title based on the index score.
  String get dopamineStatusTitle {
    if (dopamineIndexScore >= 90) return 'Dopamine Sovereign';
    if (dopamineIndexScore >= 75) return 'Digital Minimalist';
    if (dopamineIndexScore >= 60) return 'Focus Shield Active';
    if (dopamineIndexScore >= 40) return 'Decoupling in Progress';
    return 'Addiction Vulnerable';
  }

  /// Detailed descriptive evaluation of the user's current cognitive state.
  String get dopamineStatusDescription {
    if (dopamineIndexScore >= 90) {
      return 'Exceptional cognitive sovereignty. Short-form autoplay is severed while communication channels flow unhindered.';
    } else if (dopamineIndexScore >= 75) {
      return 'High resilience against algorithmic traps. You are using mobile tools for genuine communication rather than passive consumption.';
    } else if (dopamineIndexScore >= 60) {
      return 'Surgical filtering is actively intercepting dopamine triggers throughout your daily workflow.';
    } else {
      return 'Algorithmic feeds are competing for your attention. Enable surgical rules for your primary communication apps.';
    }
  }

  /// Creates a copy of the snapshot with specific fields overridden.
  SurgicalTelemetrySnapshot copyWith({
    DateTime? timestamp,
    int? totalInterceptions,
    int? blockedFeedCount,
    int? blockedReelsCount,
    int? blockedExploreCount,
    int? blockedStoriesCount,
    int? blockedCommentsCount,
    int? allowedChatCount,
    int? allowedSearchCount,
    int? activePlatformsCount,
    double? estimatedHoursReclaimed,
    double? bandwidthSavedMegabytes,
    int? dopamineIndexScore,
    Map<String, int>? platformInterceptionCounts,
    Map<SurgicalSubfeature, int>? subfeatureInterceptionCounts,
    List<int>? hourlyActivityCurve,
    String? topAddictionPlatform,
    SurgicalSubfeature? topSeveredSubfeature,
  }) {
    return SurgicalTelemetrySnapshot(
      timestamp: timestamp ?? this.timestamp,
      totalInterceptions: totalInterceptions ?? this.totalInterceptions,
      blockedFeedCount: blockedFeedCount ?? this.blockedFeedCount,
      blockedReelsCount: blockedReelsCount ?? this.blockedReelsCount,
      blockedExploreCount: blockedExploreCount ?? this.blockedExploreCount,
      blockedStoriesCount: blockedStoriesCount ?? this.blockedStoriesCount,
      blockedCommentsCount: blockedCommentsCount ?? this.blockedCommentsCount,
      allowedChatCount: allowedChatCount ?? this.allowedChatCount,
      allowedSearchCount: allowedSearchCount ?? this.allowedSearchCount,
      activePlatformsCount: activePlatformsCount ?? this.activePlatformsCount,
      estimatedHoursReclaimed: estimatedHoursReclaimed ?? this.estimatedHoursReclaimed,
      bandwidthSavedMegabytes: bandwidthSavedMegabytes ?? this.bandwidthSavedMegabytes,
      dopamineIndexScore: dopamineIndexScore ?? this.dopamineIndexScore,
      platformInterceptionCounts: platformInterceptionCounts ?? this.platformInterceptionCounts,
      subfeatureInterceptionCounts: subfeatureInterceptionCounts ?? this.subfeatureInterceptionCounts,
      hourlyActivityCurve: hourlyActivityCurve ?? this.hourlyActivityCurve,
      topAddictionPlatform: topAddictionPlatform ?? this.topAddictionPlatform,
      topSeveredSubfeature: topSeveredSubfeature ?? this.topSeveredSubfeature,
    );
  }

  /// Serializes to JSON map.
  Map<String, dynamic> toJson() => {
        'timestamp': timestamp.toIso8601String(),
        'totalInterceptions': totalInterceptions,
        'blockedFeedCount': blockedFeedCount,
        'blockedReelsCount': blockedReelsCount,
        'blockedExploreCount': blockedExploreCount,
        'blockedStoriesCount': blockedStoriesCount,
        'blockedCommentsCount': blockedCommentsCount,
        'allowedChatCount': allowedChatCount,
        'allowedSearchCount': allowedSearchCount,
        'activePlatformsCount': activePlatformsCount,
        'estimatedHoursReclaimed': estimatedHoursReclaimed,
        'bandwidthSavedMegabytes': bandwidthSavedMegabytes,
        'dopamineIndexScore': dopamineIndexScore,
        'platformInterceptionCounts': platformInterceptionCounts,
        'subfeatureInterceptionCounts': subfeatureInterceptionCounts.map(
          (k, v) => MapEntry(k.name, v),
        ),
        'hourlyActivityCurve': hourlyActivityCurve,
        'topAddictionPlatform': topAddictionPlatform,
        'topSeveredSubfeature': topSeveredSubfeature.name,
      };

  /// Deserializes from JSON map.
  factory SurgicalTelemetrySnapshot.fromJson(Map<String, dynamic> json) {
    final Map<String, dynamic> rawSubCounts =
        json['subfeatureInterceptionCounts'] as Map<String, dynamic>? ?? {};
    final Map<SurgicalSubfeature, int> subCounts = {};
    for (final entry in rawSubCounts.entries) {
      final f = SurgicalSubfeature.values.firstWhere(
        (e) => e.name == entry.key,
        orElse: () => SurgicalSubfeature.feed,
      );
      subCounts[f] = entry.value as int? ?? 0;
    }

    final topSubName = json['topSeveredSubfeature'] as String? ?? 'reelsOrShorts';
    final parsedTopSub = SurgicalSubfeature.values.firstWhere(
      (e) => e.name == topSubName,
      orElse: () => SurgicalSubfeature.reelsOrShorts,
    );

    final rawHourly = json['hourlyActivityCurve'] as List? ?? [];
    final List<int> hourly = rawHourly.map((e) => e as int? ?? 0).toList();
    while (hourly.length < 24) {
      hourly.add(0);
    }

    return SurgicalTelemetrySnapshot(
      timestamp: DateTime.tryParse(json['timestamp'] as String? ?? '') ?? DateTime.now(),
      totalInterceptions: json['totalInterceptions'] as int? ?? 0,
      blockedFeedCount: json['blockedFeedCount'] as int? ?? 0,
      blockedReelsCount: json['blockedReelsCount'] as int? ?? 0,
      blockedExploreCount: json['blockedExploreCount'] as int? ?? 0,
      blockedStoriesCount: json['blockedStoriesCount'] as int? ?? 0,
      blockedCommentsCount: json['blockedCommentsCount'] as int? ?? 0,
      allowedChatCount: json['allowedChatCount'] as int? ?? 0,
      allowedSearchCount: json['allowedSearchCount'] as int? ?? 0,
      activePlatformsCount: json['activePlatformsCount'] as int? ?? 0,
      estimatedHoursReclaimed: (json['estimatedHoursReclaimed'] as num?)?.toDouble() ?? 0.0,
      bandwidthSavedMegabytes: (json['bandwidthSavedMegabytes'] as num?)?.toDouble() ?? 0.0,
      dopamineIndexScore: json['dopamineIndexScore'] as int? ?? 50,
      platformInterceptionCounts: Map<String, int>.from(
        json['platformInterceptionCounts'] as Map? ?? {},
      ),
      subfeatureInterceptionCounts: subCounts,
      hourlyActivityCurve: hourly,
      topAddictionPlatform: json['topAddictionPlatform'] as String? ?? 'None',
      topSeveredSubfeature: parsedTopSub,
    );
  }
}
