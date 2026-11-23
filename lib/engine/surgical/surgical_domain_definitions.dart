import 'package:flutter/foundation.dart';

/// Platform identifier for surgical feed separation.
enum SurgicalPlatform {
  instagram,
  youtube,
  reddit,
  tiktok,
  twitterX,
  linkedin,
}

/// Rule definition specifying blocked feed domains vs whitelisted messaging/search gateways.
@immutable
class PlatformSurgicalRule {
  final SurgicalPlatform platform;
  final String displayName;
  final String iconGlyph;
  final List<String> feedBlacklistDomains;
  final List<String> feedUrlPathPatterns;
  final List<String> chatWhitelistDomains;
  final List<String> searchWhitelistDomains;
  final String feedDescription;
  final String chatDescription;

  const PlatformSurgicalRule({
    required this.platform,
    required this.displayName,
    required this.iconGlyph,
    required this.feedBlacklistDomains,
    required this.feedUrlPathPatterns,
    required this.chatWhitelistDomains,
    required this.searchWhitelistDomains,
    required this.feedDescription,
    required this.chatDescription,
  });
}

/// Comprehensive, exhaustive database of surgical domain and path definitions.
class SurgicalDomainDefinitions {
  static const Map<SurgicalPlatform, PlatformSurgicalRule> platformRules = {
    SurgicalPlatform.instagram: PlatformSurgicalRule(
      platform: SurgicalPlatform.instagram,
      displayName: 'Instagram (Reels vs DMs)',
      iconGlyph: '📸',
      feedBlacklistDomains: [
        'reels.instagram.com',
        'z-p3-video.xx.fbcdn.net',
        'video.xx.fbcdn.net',
        'scontent-iad3-1.cdninstagram.com',
        'scontent.cdninstagram.com',
        'graph.instagram.com/explore',
      ],
      feedUrlPathPatterns: [
        '/reels/',
        '/explore/',
        '/reel/',
      ],
      chatWhitelistDomains: [
        'direct.instagram.com',
        'edge-chat.instagram.com',
        'graph.instagram.com/direct_v2',
        'i.instagram.com/api/v1/direct_v2',
      ],
      searchWhitelistDomains: [
        'instagram.com/web/search',
        'graph.instagram.com/search',
      ],
      feedDescription: 'Blackholes Reels CDN video nodes & algorithmic Explore feed',
      chatDescription: 'Maintains active Direct Messages, group chats & calling WebSockets',
    ),

    SurgicalPlatform.youtube: PlatformSurgicalRule(
      platform: SurgicalPlatform.youtube,
      displayName: 'YouTube (Shorts vs Lectures)',
      iconGlyph: '▶️',
      feedBlacklistDomains: [
        'youtube.com/shorts',
        'i.ytimg.com/vi/shorts',
        'yt3.ggpht.com/shorts',
      ],
      feedUrlPathPatterns: [
        '/shorts/',
        '/youtubei/v1/reel',
        '/youtubei/v1/browse?browse_id=FEshorts',
      ],
      chatWhitelistDomains: [
        'youtube.com/live_chat',
        'studio.youtube.com',
      ],
      searchWhitelistDomains: [
        'youtube.com/results',
        'suggestqueries.google.com',
        'youtube.com/watch',
      ],
      feedDescription: 'Blocks infinite vertical video Shorts player & autoplay reels',
      chatDescription: 'Preserves targeted educational search, lectures, and live chat',
    ),

    SurgicalPlatform.reddit: PlatformSurgicalRule(
      platform: SurgicalPlatform.reddit,
      displayName: 'Reddit (Infinite Feed vs DMs)',
      iconGlyph: '👾',
      feedBlacklistDomains: [
        'v.redd.it',
        'preview.redd.it',
        'reddit.com/r/all',
        'reddit.com/r/popular',
        'gateway.reddit.com/desktopapi/v1/subreddits/all',
      ],
      feedUrlPathPatterns: [
        '/r/all/',
        '/r/popular/',
        '/hot/',
      ],
      chatWhitelistDomains: [
        'chat.reddit.com',
        'sendbird.reddit.com',
        'reddit.com/message/messages',
        'reddit.com/message/inbox',
      ],
      searchWhitelistDomains: [
        'reddit.com/search',
      ],
      feedDescription: 'Blackholes algorithmic popular stream & infinite video feed',
      chatDescription: 'Preserves direct messaging, private modmail & specific search',
    ),

    SurgicalPlatform.tiktok: PlatformSurgicalRule(
      platform: SurgicalPlatform.tiktok,
      displayName: 'TikTok (FYP vs Direct Messages)',
      iconGlyph: '🎵',
      feedBlacklistDomains: [
        'v16-webapp.tiktok.com',
        'v16-webapp-prime.tiktok.com',
        'api16-normal-c-alisg.tiktokv.com',
      ],
      feedUrlPathPatterns: [
        '/foryou',
        '/tag/',
      ],
      chatWhitelistDomains: [
        'webcast.tiktok.com',
        'im-api.tiktok.com',
        'tiktok.com/messages',
      ],
      searchWhitelistDomains: [
        'tiktok.com/search',
      ],
      feedDescription: 'Kills infinite algorithm FYP video delivery servers',
      chatDescription: 'Allows messaging and specific creator profile lookups',
    ),

    SurgicalPlatform.twitterX: PlatformSurgicalRule(
      platform: SurgicalPlatform.twitterX,
      displayName: 'X / Twitter (For You vs DMs)',
      iconGlyph: '𝕏',
      feedBlacklistDomains: [
        'video.twimg.com',
        'api.twitter.com/1.1/strato/column/None/guide/cards',
      ],
      feedUrlPathPatterns: [
        '/i/timeline/for_you',
        '/explore',
      ],
      chatWhitelistDomains: [
        'api.twitter.com/1.1/direct_messages',
        'twitter.com/messages',
        'x.com/messages',
      ],
      searchWhitelistDomains: [
        'twitter.com/search',
        'x.com/search',
      ],
      feedDescription: 'Blackholes "For You" algorithmic timeline & auto-playing video',
      chatDescription: 'Leaves direct messages and private group conversations intact',
    ),
  };
}
