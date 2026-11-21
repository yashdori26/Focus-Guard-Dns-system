import 'package:flutter/material.dart';

/// Distinct sub-feature vectors within modern mobile applications.
enum SurgicalSubfeature {
  /// The infinite algorithmic home timeline or feed (e.g. Instagram Home, Twitter For You).
  feed,

  /// Short-form vertical autoplay video reels (e.g. Instagram Reels, YouTube Shorts, TikTok FYP).
  reelsOrShorts,

  /// Ephemeral 24-hour stories carousel (e.g. Instagram Stories, Snapchat Stories).
  stories,

  /// Algorithmic discovery or explore grid (e.g. Instagram Explore, Twitter Explore).
  explore,

  /// Public comment sections and debate threads.
  comments,

  /// Direct 1-on-1 and group messaging channels (e.g. Instagram DMs, Reddit Chat, Twitter DMs).
  directMessages,

  /// Intentional keyword search bar and query results.
  search,

  /// Creator analytics, publishing dashboard, and studio tools.
  creatorStudio,
}

/// Metadata describing a specific sub-feature vector.
@immutable
class SubfeatureMetadata {
  final SurgicalSubfeature feature;
  final String displayName;
  final String description;
  final IconData icon;
  final int dopamineAddictionScore; // 1 - 100
  final bool isCommunicationChannel;
  final bool isDefaultBlocked;

  const SubfeatureMetadata({
    required this.feature,
    required this.displayName,
    required this.description,
    required this.icon,
    required this.dopamineAddictionScore,
    this.isCommunicationChannel = false,
    this.isDefaultBlocked = false,
  });

  Map<String, dynamic> toJson() => {
        'feature': feature.name,
        'displayName': displayName,
        'description': description,
        'dopamineAddictionScore': dopamineAddictionScore,
        'isCommunicationChannel': isCommunicationChannel,
        'isDefaultBlocked': isDefaultBlocked,
      };
}

/// Central registry of metadata for all 8 surgical sub-feature types.
class SurgicalSubfeatureRegistry {
  SurgicalSubfeatureRegistry._();

  static const Map<SurgicalSubfeature, SubfeatureMetadata> metadata = {
    SurgicalSubfeature.feed: SubfeatureMetadata(
      feature: SurgicalSubfeature.feed,
      displayName: 'Home Algorithmic Feed',
      description: 'Infinite scrolling timeline designed for continuous engagement.',
      icon: Icons.dynamic_feed_rounded,
      dopamineAddictionScore: 88,
      isCommunicationChannel: false,
      isDefaultBlocked: true,
    ),
    SurgicalSubfeature.reelsOrShorts: SubfeatureMetadata(
      feature: SurgicalSubfeature.reelsOrShorts,
      displayName: 'Reels & Shorts Autoplay',
      description: 'Ultra-fast vertical video stream with variable reward scheduling.',
      icon: Icons.play_circle_filled_rounded,
      dopamineAddictionScore: 98,
      isCommunicationChannel: false,
      isDefaultBlocked: true,
    ),
    SurgicalSubfeature.stories: SubfeatureMetadata(
      feature: SurgicalSubfeature.stories,
      displayName: '24-Hour Stories Carousel',
      description: 'FOMO-inducing ephemeral photo and video updates.',
      icon: Icons.history_toggle_off_rounded,
      dopamineAddictionScore: 74,
      isCommunicationChannel: false,
      isDefaultBlocked: false,
    ),
    SurgicalSubfeature.explore: SubfeatureMetadata(
      feature: SurgicalSubfeature.explore,
      displayName: 'Explore & Discovery Grid',
      description: 'AI-curated grid targeting hyper-personalized curiosity.',
      icon: Icons.explore_rounded,
      dopamineAddictionScore: 82,
      isCommunicationChannel: false,
      isDefaultBlocked: true,
    ),
    SurgicalSubfeature.comments: SubfeatureMetadata(
      feature: SurgicalSubfeature.comments,
      displayName: 'Comments & Arguments',
      description: 'Public argument loops, outrage triggers, and validation chasing.',
      icon: Icons.mode_comment_outlined,
      dopamineAddictionScore: 68,
      isCommunicationChannel: false,
      isDefaultBlocked: false,
    ),
    SurgicalSubfeature.directMessages: SubfeatureMetadata(
      feature: SurgicalSubfeature.directMessages,
      displayName: 'Direct Messages (DMs)',
      description: 'Intentional 1-on-1 and group communication with real contacts.',
      icon: Icons.mark_chat_unread_rounded,
      dopamineAddictionScore: 25,
      isCommunicationChannel: true,
      isDefaultBlocked: false,
    ),
    SurgicalSubfeature.search: SubfeatureMetadata(
      feature: SurgicalSubfeature.search,
      displayName: 'Search & Keyword Lookups',
      description: 'Targeted user search queries without unsolicited recommendations.',
      icon: Icons.search_rounded,
      dopamineAddictionScore: 18,
      isCommunicationChannel: false,
      isDefaultBlocked: false,
    ),
    SurgicalSubfeature.creatorStudio: SubfeatureMetadata(
      feature: SurgicalSubfeature.creatorStudio,
      displayName: 'Creator Tools & Studio',
      description: 'Content uploading, business dashboards, and message management.',
      icon: Icons.dashboard_customize_rounded,
      dopamineAddictionScore: 20,
      isCommunicationChannel: false,
      isDefaultBlocked: false,
    ),
  };

  static SubfeatureMetadata getMetadata(SurgicalSubfeature feature) {
    return metadata[feature] ?? metadata[SurgicalSubfeature.feed]!;
  }
}
