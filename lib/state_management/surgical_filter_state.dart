import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../backend/vpn_service.dart';

class SurgicalFilterState {
  // Instagram: Feed/Reels vs Direct Messages
  final bool blockInstagramReels;
  final bool allowInstagramDms;

  // YouTube: Shorts & Recommendations vs Search & Educational videos
  final bool blockYouTubeShorts;
  final bool blockYouTubeRecommendations;
  final bool enforceYouTubeRestricted;

  // Reddit: Infinite Home Feed vs Subreddits & Messages
  final bool blockRedditFeed;
  final bool allowRedditDms;

  const SurgicalFilterState({
    this.blockInstagramReels = true,
    this.allowInstagramDms = true,
    this.blockYouTubeShorts = true,
    this.blockYouTubeRecommendations = true,
    this.enforceYouTubeRestricted = true,
    this.blockRedditFeed = true,
    this.allowRedditDms = true,
  });

  SurgicalFilterState copyWith({
    bool? blockInstagramReels,
    bool? allowInstagramDms,
    bool? blockYouTubeShorts,
    bool? blockYouTubeRecommendations,
    bool? enforceYouTubeRestricted,
    bool? blockRedditFeed,
    bool? allowRedditDms,
  }) {
    return SurgicalFilterState(
      blockInstagramReels: blockInstagramReels ?? this.blockInstagramReels,
      allowInstagramDms: allowInstagramDms ?? this.allowInstagramDms,
      blockYouTubeShorts: blockYouTubeShorts ?? this.blockYouTubeShorts,
      blockYouTubeRecommendations: blockYouTubeRecommendations ?? this.blockYouTubeRecommendations,
      enforceYouTubeRestricted: enforceYouTubeRestricted ?? this.enforceYouTubeRestricted,
      blockRedditFeed: blockRedditFeed ?? this.blockRedditFeed,
      allowRedditDms: allowRedditDms ?? this.allowRedditDms,
    );
  }

  bool get isAnyFeedBlocked =>
      blockInstagramReels ||
      blockYouTubeShorts ||
      blockYouTubeRecommendations ||
      blockRedditFeed;

  List<String> get activeBlockedDomains {
    final list = <String>[];
    if (blockInstagramReels) {
      list.addAll(['reels.instagram.com', 'graph.instagram.com/logging_client_events', 'edge-chat.instagram.com']);
    }
    if (blockYouTubeShorts) {
      list.addAll(['youtube.com/shorts', 'i.ytimg.com/vi/shorts', 'shorts.youtube.com']);
    }
    if (blockYouTubeRecommendations) {
      list.addAll(['suggestqueries.google.com', 'youtubei.googleapis.com/youtubei/v1/browse']);
    }
    if (blockRedditFeed) {
      list.addAll(['gateway.reddit.com/desktopapi/v1/subreddits/all', 'reddit.com/r/popular']);
    }
    return list;
  }

  List<String> get activeAllowedDomains {
    final list = <String>[];
    if (allowInstagramDms) {
      list.addAll(['direct.instagram.com', 'b-graph.facebook.com']);
    }
    if (allowRedditDms) {
      list.addAll(['chat.reddit.com', 'sendbird.reddit.com']);
    }
    return list;
  }
}

class SurgicalFilterNotifier extends StateNotifier<SurgicalFilterState> {
  SurgicalFilterNotifier() : super(const SurgicalFilterState()) {
    _syncWithVpn();
  }

  void toggleInstagramReels(bool value) {
    state = state.copyWith(blockInstagramReels: value);
    _syncWithVpn();
  }

  void toggleInstagramDms(bool value) {
    state = state.copyWith(allowInstagramDms: value);
    _syncWithVpn();
  }

  void toggleYouTubeShorts(bool value) {
    state = state.copyWith(blockYouTubeShorts: value);
    _syncWithVpn();
  }

  void toggleYouTubeRecommendations(bool value) {
    state = state.copyWith(blockYouTubeRecommendations: value);
    _syncWithVpn();
  }

  void toggleRedditFeed(bool value) {
    state = state.copyWith(blockRedditFeed: value);
    _syncWithVpn();
  }

  void toggleRedditDms(bool value) {
    state = state.copyWith(allowRedditDms: value);
    _syncWithVpn();
  }

  void setAllFeedsBlocked(bool value) {
    state = state.copyWith(
      blockInstagramReels: value,
      blockYouTubeShorts: value,
      blockYouTubeRecommendations: value,
      blockRedditFeed: value,
    );
    _syncWithVpn();
  }

  void _syncWithVpn() {
    try {
      FocusDnsVpnManager.updateDnsRules(
        blockedDomains: state.activeBlockedDomains,
        allowedDomains: state.activeAllowedDomains,
      );
    } catch (_) {}
  }
}

final surgicalFilterProvider =
    StateNotifierProvider<SurgicalFilterNotifier, SurgicalFilterState>((ref) {
  return SurgicalFilterNotifier();
});
