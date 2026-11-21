import 'package:flutter/foundation.dart';
import '../catalog/surgical_subfeature_types.dart';
import 'view_node_target.dart';

/// The layer or subsystem that detected and intercepted the sub-feature traffic.
enum InterceptionTriggerSource {
  /// Packet-level DNS query sinkholed at the local TUN/VPN loop.
  dnsQuery,

  /// TLS ClientHello SNI inspection match at the network socket layer.
  tlsSniInspection,

  /// HTTP/HTTPS URL path prefix matched in HTTP proxy or WebView sieve.
  urlPathPrefix,

  /// Native Android AccessibilityNodeInfo view hierarchy inspector detection.
  accessibilityViewTree,

  /// App window focus / foreground activity change detection.
  windowStateTransition,

  /// User-defined custom rule filter match.
  customPatternMatch,
}

/// Severity classification of the dopamine hazard prevented by this interception.
enum DopamineHazardLevel {
  /// Low hazard (e.g. general search, settings, profile lookups).
  mild,

  /// Moderate hazard (e.g. comments sections, story carousels).
  moderate,

  /// Severe hazard (e.g. algorithmic home timelines, explore discovery grids).
  high,

  /// Extreme hazard (e.g. short-form vertical autoplay reels, FYP, Shorts).
  critical,
}

/// Immutable audit record capturing a single sub-feature interception event.
@immutable
class SurgicalInterceptionEvent {
  /// Unique identifier for this interception event.
  final String eventId;

  /// Wall-clock timestamp when the interception occurred.
  final DateTime timestamp;

  /// Target platform identifier (e.g. 'instagram', 'youtube', 'reddit').
  final String platformId;

  /// Human-readable platform name (e.g. 'Instagram', 'YouTube').
  final String platformName;

  /// Specific sub-feature vector that was intercepted.
  final SurgicalSubfeature subfeature;

  /// Specific domain name or URL path intercepted (e.g. 'reels.instagram.com').
  final String interceptedTarget;

  /// Action applied to the intercepted request or view.
  final ViewInterceptionAction actionApplied;

  /// Subsystem that triggered the interception.
  final InterceptionTriggerSource triggerSource;

  /// Associated Android package name (e.g. 'com.instagram.android').
  final String packageName;

  /// Optional resource ID of the intercepted view if detected via accessibility.
  final String? viewResourceId;

  /// Estimated screen time saved in seconds by blocking this addiction loop.
  final int estimatedSecondsSaved;

  /// Estimated network payload bytes avoided by blackholing video delivery CDN.
  final int estimatedBytesBlocked;

  /// Dopamine hazard severity rating of the intercepted feature.
  final DopamineHazardLevel hazardLevel;

  /// Whether the user requested and was granted a mindful bypass.
  final bool userBypassGranted;

  /// Optional contextual note or rule description.
  final String notes;

  const SurgicalInterceptionEvent({
    required this.eventId,
    required this.timestamp,
    required this.platformId,
    required this.platformName,
    required this.subfeature,
    required this.interceptedTarget,
    required this.actionApplied,
    required this.triggerSource,
    required this.packageName,
    this.viewResourceId,
    this.estimatedSecondsSaved = 120,
    this.estimatedBytesBlocked = 2097152, // ~2 MB average per reel/short video chunk
    this.hazardLevel = DopamineHazardLevel.high,
    this.userBypassGranted = false,
    this.notes = '',
  });

  /// Computes the default dopamine hazard level based on the sub-feature vector.
  static DopamineHazardLevel calculateHazardLevel(SurgicalSubfeature subfeature) {
    switch (subfeature) {
      case SurgicalSubfeature.reelsOrShorts:
        return DopamineHazardLevel.critical;
      case SurgicalSubfeature.feed:
      case SurgicalSubfeature.explore:
        return DopamineHazardLevel.high;
      case SurgicalSubfeature.stories:
      case SurgicalSubfeature.comments:
        return DopamineHazardLevel.moderate;
      case SurgicalSubfeature.directMessages:
      case SurgicalSubfeature.search:
      case SurgicalSubfeature.creatorStudio:
        return DopamineHazardLevel.mild;
    }
  }

  /// Calculates reasonable estimate of seconds saved for a single block of this subfeature.
  static int defaultSecondsSaved(SurgicalSubfeature subfeature) {
    switch (subfeature) {
      case SurgicalSubfeature.reelsOrShorts:
        return 300; // 5 minutes of doomscrolling averted on average
      case SurgicalSubfeature.feed:
        return 240; // 4 minutes of timeline scrolling averted
      case SurgicalSubfeature.explore:
        return 180; // 3 minutes of discovery browsing averted
      case SurgicalSubfeature.stories:
        return 120; // 2 minutes of ephemeral story watching
      case SurgicalSubfeature.comments:
        return 90; // 1.5 minutes of public comment arguments
      default:
        return 30;
    }
  }

  /// Generates a human-friendly description of what was saved and blocked.
  String get displaySummary {
    final subMeta = SurgicalSubfeatureRegistry.getMetadata(subfeature);
    final minutes = (estimatedSecondsSaved / 60).toStringAsFixed(1);
    final mb = (estimatedBytesBlocked / (1024 * 1024)).toStringAsFixed(1);
    return 'Blocked ${subMeta.displayName} on $platformName (Averted ~$minutes min doomscroll, saved $mb MB)';
  }

  /// Creates a copy of this event with optional modified fields.
  SurgicalInterceptionEvent copyWith({
    String? eventId,
    DateTime? timestamp,
    String? platformId,
    String? platformName,
    SurgicalSubfeature? subfeature,
    String? interceptedTarget,
    ViewInterceptionAction? actionApplied,
    InterceptionTriggerSource? triggerSource,
    String? packageName,
    String? viewResourceId,
    int? estimatedSecondsSaved,
    int? estimatedBytesBlocked,
    DopamineHazardLevel? hazardLevel,
    bool? userBypassGranted,
    String? notes,
  }) {
    return SurgicalInterceptionEvent(
      eventId: eventId ?? this.eventId,
      timestamp: timestamp ?? this.timestamp,
      platformId: platformId ?? this.platformId,
      platformName: platformName ?? this.platformName,
      subfeature: subfeature ?? this.subfeature,
      interceptedTarget: interceptedTarget ?? this.interceptedTarget,
      actionApplied: actionApplied ?? this.actionApplied,
      triggerSource: triggerSource ?? this.triggerSource,
      packageName: packageName ?? this.packageName,
      viewResourceId: viewResourceId ?? this.viewResourceId,
      estimatedSecondsSaved: estimatedSecondsSaved ?? this.estimatedSecondsSaved,
      estimatedBytesBlocked: estimatedBytesBlocked ?? this.estimatedBytesBlocked,
      hazardLevel: hazardLevel ?? this.hazardLevel,
      userBypassGranted: userBypassGranted ?? this.userBypassGranted,
      notes: notes ?? this.notes,
    );
  }

  /// Serializes the event to a JSON map.
  Map<String, dynamic> toJson() => {
        'eventId': eventId,
        'timestamp': timestamp.toIso8601String(),
        'platformId': platformId,
        'platformName': platformName,
        'subfeature': subfeature.name,
        'interceptedTarget': interceptedTarget,
        'actionApplied': actionApplied.name,
        'triggerSource': triggerSource.name,
        'packageName': packageName,
        'viewResourceId': viewResourceId,
        'estimatedSecondsSaved': estimatedSecondsSaved,
        'estimatedBytesBlocked': estimatedBytesBlocked,
        'hazardLevel': hazardLevel.name,
        'userBypassGranted': userBypassGranted,
        'notes': notes,
      };

  /// Deserializes the event from a JSON map with defensive fallbacks.
  factory SurgicalInterceptionEvent.fromJson(Map<String, dynamic> json) {
    final subfeatureName = json['subfeature'] as String? ?? 'feed';
    final parsedSubfeature = SurgicalSubfeature.values.firstWhere(
      (e) => e.name == subfeatureName,
      orElse: () => SurgicalSubfeature.feed,
    );

    final actionName = json['actionApplied'] as String? ?? 'navigateBack';
    final parsedAction = ViewInterceptionAction.values.firstWhere(
      (a) => a.name == actionName,
      orElse: () => ViewInterceptionAction.navigateBack,
    );

    final triggerName = json['triggerSource'] as String? ?? 'dnsQuery';
    final parsedTrigger = InterceptionTriggerSource.values.firstWhere(
      (t) => t.name == triggerName,
      orElse: () => InterceptionTriggerSource.dnsQuery,
    );

    final hazardName = json['hazardLevel'] as String? ?? 'high';
    final parsedHazard = DopamineHazardLevel.values.firstWhere(
      (h) => h.name == hazardName,
      orElse: () => DopamineHazardLevel.high,
    );

    final timestampStr = json['timestamp'] as String?;
    final parsedTimestamp = timestampStr != null
        ? DateTime.tryParse(timestampStr) ?? DateTime.now()
        : DateTime.now();

    return SurgicalInterceptionEvent(
      eventId: json['eventId'] as String? ?? 'evt_${DateTime.now().microsecondsSinceEpoch}',
      timestamp: parsedTimestamp,
      platformId: json['platformId'] as String? ?? 'unknown',
      platformName: json['platformName'] as String? ?? 'Unknown Platform',
      subfeature: parsedSubfeature,
      interceptedTarget: json['interceptedTarget'] as String? ?? '',
      actionApplied: parsedAction,
      triggerSource: parsedTrigger,
      packageName: json['packageName'] as String? ?? '',
      viewResourceId: json['viewResourceId'] as String?,
      estimatedSecondsSaved: json['estimatedSecondsSaved'] as int? ?? 120,
      estimatedBytesBlocked: json['estimatedBytesBlocked'] as int? ?? 2097152,
      hazardLevel: parsedHazard,
      userBypassGranted: json['userBypassGranted'] as bool? ?? false,
      notes: json['notes'] as String? ?? '',
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SurgicalInterceptionEvent &&
          runtimeType == other.runtimeType &&
          eventId == other.eventId;

  @override
  int get hashCode => eventId.hashCode;

  @override
  String toString() {
    return 'SurgicalInterceptionEvent(id: $eventId, platform: $platformName, subfeature: ${subfeature.name}, action: ${actionApplied.name}, saved: ${estimatedSecondsSaved}s)';
  }
}
