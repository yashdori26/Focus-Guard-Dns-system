import '../models/surgical_rule_model.dart';
import '../models/view_node_target.dart';
import 'surgical_subfeature_types.dart';

/// Exhaustive, production-grade catalog containing surgical dissection rules
/// and view node signatures for 12+ major mobile platforms.
class SurgicalPlatformCatalog {
  SurgicalPlatformCatalog._();

  // ===========================================================================
  // 1. INSTAGRAM (Reels vs DMs vs Stories vs Explore)
  // ===========================================================================
  static const SurgicalRuleModel instagram = SurgicalRuleModel(
    platformId: 'instagram',
    displayName: 'Instagram',
    iconGlyph: '📸',
    packageNames: ['com.instagram.android', 'com.instagram.lite'],
    subfeatureToggles: {
      SurgicalSubfeature.reelsOrShorts: true,
      SurgicalSubfeature.feed: true,
      SurgicalSubfeature.explore: true,
      SurgicalSubfeature.stories: false,
      SurgicalSubfeature.comments: false,
      SurgicalSubfeature.directMessages: false,
      SurgicalSubfeature.search: false,
    },
    subfeatureDomains: {
      SurgicalSubfeature.reelsOrShorts: [
        'reels.instagram.com',
        'z-p3-video.xx.fbcdn.net',
        'video.xx.fbcdn.net',
        'scontent-iad3-1.cdninstagram.com',
        'scontent.cdninstagram.com/o1/v/',
      ],
      SurgicalSubfeature.feed: [
        'graph.instagram.com/feed',
        'i.instagram.com/api/v1/feed/timeline',
        'i.instagram.com/api/v1/feed/timeline_stream',
      ],
      SurgicalSubfeature.explore: [
        'graph.instagram.com/explore',
        'i.instagram.com/api/v1/discover/topical_explore',
      ],
      SurgicalSubfeature.stories: [
        'i.instagram.com/api/v1/feed/reels_tray',
      ],
    },
    subfeatureUrlPaths: {
      SurgicalSubfeature.reelsOrShorts: ['/reels/', '/reel/', '/clips/'],
      SurgicalSubfeature.explore: ['/explore/'],
    },
    chatWhitelistDomains: [
      'direct.instagram.com',
      'edge-chat.instagram.com',
      'graph.instagram.com',
      'graph.instagram.com/direct_v2',
      'i.instagram.com/api/v1/direct_v2',
      'gateway.instagram.com',
    ],
    searchWhitelistDomains: [
      'instagram.com/web/search',
      'graph.instagram.com/search',
    ],
    viewNodeTargets: [
      ViewNodeTarget(
        targetId: 'ig_reels_tab',
        packageName: 'com.instagram.android',
        resourceIdPatterns: [
          'clips_viewer',
          'clips_video_container',
          'reel_viewer_layout',
          'tab_clips',
        ],
        contentDescriptionPatterns: ['Reels', 'Clips', 'Shorts'],
        defaultAction: ViewInterceptionAction.showMindfulNudge,
        description: 'Instagram Reels Video Viewer and Bottom Navigation Tab',
      ),
      ViewNodeTarget(
        targetId: 'ig_explore_grid',
        packageName: 'com.instagram.android',
        resourceIdPatterns: [
          'search_tab_layout',
          'explore_grid_container',
        ],
        contentDescriptionPatterns: ['Search and explore', 'Explore tab'],
        defaultAction: ViewInterceptionAction.navigateBack,
        description: 'Instagram Explore Algorithmic Grid',
      ),
    ],
    enableMindfulInterstitial: true,
    mindfulPauseSeconds: 10,
    motivationalPrompt: 'You opened Instagram for Direct Messages. Reels will consume your evening.',
  );

  // ===========================================================================
  // 2. YOUTUBE (Shorts vs Educational Lectures & Search)
  // ===========================================================================
  static const SurgicalRuleModel youtube = SurgicalRuleModel(
    platformId: 'youtube',
    displayName: 'YouTube',
    iconGlyph: '▶️',
    packageNames: ['com.google.android.youtube', 'com.google.android.youtube.tv'],
    subfeatureToggles: {
      SurgicalSubfeature.reelsOrShorts: true,
      SurgicalSubfeature.feed: true,
      SurgicalSubfeature.explore: false,
      SurgicalSubfeature.comments: false,
      SurgicalSubfeature.directMessages: false,
      SurgicalSubfeature.search: false,
      SurgicalSubfeature.creatorStudio: false,
    },
    subfeatureDomains: {
      SurgicalSubfeature.reelsOrShorts: [
        'googlevideo.com',
        '*.googlevideo.com',
        'youtube.com/shorts',
        'i.ytimg.com/vi/shorts',
        'yt3.ggpht.com/shorts',
      ],
      SurgicalSubfeature.feed: [
        'youtube.com/feed/trending',
        'youtube.com/feed/subscriptions',
      ],
    },
    subfeatureUrlPaths: {
      SurgicalSubfeature.reelsOrShorts: [
        '/shorts/',
        '/youtubei/v1/reel',
        '/youtubei/v1/browse?browse_id=FEshorts',
      ],
    },
    chatWhitelistDomains: [
      'youtube.com/live_chat',
      'studio.youtube.com',
    ],
    searchWhitelistDomains: [
      'youtube.com/results',
      'suggestqueries.google.com',
      'youtube.com/watch',
    ],
    viewNodeTargets: [
      ViewNodeTarget(
        targetId: 'yt_shorts_tab',
        packageName: 'com.google.android.youtube',
        resourceIdPatterns: [
          'reel_recycler',
          'shorts_player_view',
          'pivot_bar_shorts',
        ],
        contentDescriptionPatterns: ['Shorts', 'YouTube Shorts'],
        defaultAction: ViewInterceptionAction.showMindfulNudge,
        description: 'YouTube Shorts Vertical Reel Viewer and Pivot Tab',
      ),
    ],
    enableMindfulInterstitial: true,
    mindfulPauseSeconds: 10,
    motivationalPrompt: 'Protect your focus. Search for specific educational topics instead of autoplay loops.',
  );

  // ===========================================================================
  // 3. REDDIT (Infinite Home/Popular Feeds vs Direct Chats)
  // ===========================================================================
  static const SurgicalRuleModel reddit = SurgicalRuleModel(
    platformId: 'reddit',
    displayName: 'Reddit',
    iconGlyph: '👾',
    packageNames: ['com.reddit.frontpage'],
    subfeatureToggles: {
      SurgicalSubfeature.feed: true,
      SurgicalSubfeature.reelsOrShorts: true,
      SurgicalSubfeature.explore: true,
      SurgicalSubfeature.comments: false,
      SurgicalSubfeature.directMessages: false,
      SurgicalSubfeature.search: false,
    },
    subfeatureDomains: {
      SurgicalSubfeature.feed: [
        'v.redd.it',
        'preview.redd.it',
        'reddit.com/r/all',
        'reddit.com/r/popular',
        'gateway.reddit.com/desktopapi/v1/subreddits/all',
      ],
      SurgicalSubfeature.reelsOrShorts: [
        'v.redd.it',
        '*.v.redd.it',
        'reddit.com/r/all/video',
      ],
    },
    subfeatureUrlPaths: {
      SurgicalSubfeature.feed: ['/r/all/', '/r/popular/', '/hot/'],
    },
    chatWhitelistDomains: [
      'chat.reddit.com',
      'sendbird.reddit.com',
      'reddit.com/message/messages',
      'reddit.com/message/inbox',
    ],
    searchWhitelistDomains: [
      'reddit.com/search',
    ],
    viewNodeTargets: [
      ViewNodeTarget(
        targetId: 'reddit_popular_tab',
        packageName: 'com.reddit.frontpage',
        resourceIdPatterns: [
          'popular_feed_recycler',
          'video_feed_player',
        ],
        contentDescriptionPatterns: ['Popular', 'Watch'],
        defaultAction: ViewInterceptionAction.navigateBack,
        description: 'Reddit Infinite Media Stream & Popular Feed',
      ),
    ],
    enableMindfulInterstitial: true,
    mindfulPauseSeconds: 10,
    motivationalPrompt: 'Use Reddit for targeted knowledge and direct messages, not infinite scroll.',
  );

  // ===========================================================================
  // 4. TIKTOK (For You Page vs Direct Messages)
  // ===========================================================================
  static const SurgicalRuleModel tiktok = SurgicalRuleModel(
    platformId: 'tiktok',
    displayName: 'TikTok',
    iconGlyph: '🎵',
    packageNames: ['com.zhiliaoapp.musically', 'com.ss.android.ugc.trill'],
    subfeatureToggles: {
      SurgicalSubfeature.reelsOrShorts: true,
      SurgicalSubfeature.feed: true,
      SurgicalSubfeature.explore: true,
      SurgicalSubfeature.directMessages: false,
      SurgicalSubfeature.search: false,
    },
    subfeatureDomains: {
      SurgicalSubfeature.reelsOrShorts: [
        'v16-webapp.tiktok.com',
        'v16-webapp-prime.tiktok.com',
        'api16-normal-c-alisg.tiktokv.com',
        'api22-normal-c-useast1a.tiktokv.com',
      ],
    },
    subfeatureUrlPaths: {
      SurgicalSubfeature.reelsOrShorts: ['/foryou', '/tag/'],
    },
    chatWhitelistDomains: [
      'webcast.tiktok.com',
      'im-api.tiktok.com',
      'tiktok.com/messages',
    ],
    searchWhitelistDomains: [
      'tiktok.com/search',
    ],
    viewNodeTargets: [
      ViewNodeTarget(
        targetId: 'tiktok_fyp_feed',
        packageName: 'com.zhiliaoapp.musically',
        resourceIdPatterns: ['view_pager', 'vertical_video_container'],
        contentDescriptionPatterns: ['For You', 'Following'],
        defaultAction: ViewInterceptionAction.showMindfulNudge,
        description: 'TikTok Fullscreen Vertical FYP ViewPager',
      ),
    ],
    enableMindfulInterstitial: true,
    mindfulPauseSeconds: 15,
    motivationalPrompt: 'TikTok FYP is engineered for addiction. Keep to messaging or read an educational article.',
  );

  // ===========================================================================
  // 5. X / TWITTER (For You vs Direct Messages)
  // ===========================================================================
  static const SurgicalRuleModel twitterX = SurgicalRuleModel(
    platformId: 'twitter_x',
    displayName: 'X / Twitter',
    iconGlyph: '𝕏',
    packageNames: ['com.twitter.android', 'com.twitter.android.lite'],
    subfeatureToggles: {
      SurgicalSubfeature.feed: true,
      SurgicalSubfeature.explore: true,
      SurgicalSubfeature.reelsOrShorts: true,
      SurgicalSubfeature.directMessages: false,
      SurgicalSubfeature.search: false,
    },
    subfeatureDomains: {
      SurgicalSubfeature.reelsOrShorts: [
        'video.twimg.com',
      ],
      SurgicalSubfeature.feed: [
        'video.twimg.com',
        'api.twitter.com/1.1/strato/column/None/guide/cards',
        'twitter.com/i/timeline/for_you',
      ],
    },
    subfeatureUrlPaths: {
      SurgicalSubfeature.feed: ['/i/timeline/for_you', '/explore'],
    },
    chatWhitelistDomains: [
      'api.twitter.com/1.1/direct_messages',
      'twitter.com/messages',
      'twitter.com/i/chat',
      'x.com/messages',
    ],
    searchWhitelistDomains: [
      'twitter.com/search',
      'x.com/search',
    ],
    viewNodeTargets: [
      ViewNodeTarget(
        targetId: 'twitter_for_you_tab',
        packageName: 'com.twitter.android',
        resourceIdPatterns: ['timeline_view_pager'],
        contentDescriptionPatterns: ['For you', 'Trending'],
        defaultAction: ViewInterceptionAction.navigateBack,
        description: 'Twitter / X "For You" Algorithmic Feed Tab',
      ),
    ],
    enableMindfulInterstitial: true,
    mindfulPauseSeconds: 10,
    motivationalPrompt: 'Outrage algorithms steal hours. Direct messages only.',
  );

  // ===========================================================================
  // 6. LINKEDIN (Feed vs InMail & Jobs)
  // ===========================================================================
  static const SurgicalRuleModel linkedin = SurgicalRuleModel(
    platformId: 'linkedin',
    displayName: 'LinkedIn',
    iconGlyph: '💼',
    packageNames: ['com.linkedin.android'],
    subfeatureToggles: {
      SurgicalSubfeature.feed: true,
      SurgicalSubfeature.directMessages: false,
      SurgicalSubfeature.search: false,
    },
    subfeatureDomains: {
      SurgicalSubfeature.feed: [
        'media.licdn.com/dms/image',
        'media.licdn.com/dms/video',
        'linkedin.com/feed',
      ],
    },
    subfeatureUrlPaths: {
      SurgicalSubfeature.feed: ['/feed/'],
    },
    chatWhitelistDomains: [
      'linkedin.com/messaging',
      'realtime.www.linkedin.com',
    ],
    searchWhitelistDomains: [
      'linkedin.com/jobs',
      'linkedin.com/search',
    ],
    viewNodeTargets: [
      ViewNodeTarget(
        targetId: 'linkedin_home_feed',
        packageName: 'com.linkedin.android',
        resourceIdPatterns: ['feed_recycler_view'],
        contentDescriptionPatterns: ['Home', 'Feed'],
        defaultAction: ViewInterceptionAction.redirectToDirectMessages,
        description: 'LinkedIn Main Corporate Engagement Feed',
      ),
    ],
    enableMindfulInterstitial: true,
    mindfulPauseSeconds: 8,
    motivationalPrompt: 'Reply to professional messages without browsing engagement-bait.',
  );

  // ===========================================================================
  // 7. SNAPCHAT (Spotlight & Discover vs Chats)
  // ===========================================================================
  static const SurgicalRuleModel snapchat = SurgicalRuleModel(
    platformId: 'snapchat',
    displayName: 'Snapchat',
    iconGlyph: '👻',
    packageNames: ['com.snapchat.android'],
    subfeatureToggles: {
      SurgicalSubfeature.reelsOrShorts: true,
      SurgicalSubfeature.explore: true,
      SurgicalSubfeature.stories: false,
      SurgicalSubfeature.directMessages: false,
    },
    subfeatureDomains: {
      SurgicalSubfeature.reelsOrShorts: [
        'spotlight.snapchat.com',
        'discover.snapchat.com',
        'bolt-gcdn.sc-cdn.net',
      ],
    },
    chatWhitelistDomains: [
      'chat.snapchat.com',
      'app.snapchat.com',
    ],
    searchWhitelistDomains: [],
    viewNodeTargets: [
      ViewNodeTarget(
        targetId: 'snap_spotlight_tab',
        packageName: 'com.snapchat.android',
        resourceIdPatterns: ['spotlight_page_container'],
        contentDescriptionPatterns: ['Spotlight', 'Discover'],
        defaultAction: ViewInterceptionAction.navigateBack,
        description: 'Snapchat Spotlight Endless Video Scroll',
      ),
    ],
    enableMindfulInterstitial: true,
    mindfulPauseSeconds: 10,
    motivationalPrompt: 'Spotlight is pure distraction. Snap your close friends directly.',
  );

  // ===========================================================================
  // 8. FACEBOOK (Watch & Feed vs Messenger & Marketplace)
  // ===========================================================================
  static const SurgicalRuleModel facebook = SurgicalRuleModel(
    platformId: 'facebook',
    displayName: 'Facebook',
    iconGlyph: '👥',
    packageNames: ['com.facebook.katana', 'com.facebook.lite'],
    subfeatureToggles: {
      SurgicalSubfeature.feed: true,
      SurgicalSubfeature.reelsOrShorts: true,
      SurgicalSubfeature.directMessages: false,
      SurgicalSubfeature.search: false,
    },
    subfeatureDomains: {
      SurgicalSubfeature.feed: [
        'm.facebook.com/watch',
        'video.xx.fbcdn.net',
      ],
      SurgicalSubfeature.reelsOrShorts: [
        'facebook.com/reel',
      ],
    },
    chatWhitelistDomains: [
      'edge-chat.messenger.com',
      'graph.facebook.com/v19.0/me/messages',
    ],
    searchWhitelistDomains: [
      'facebook.com/marketplace',
      'facebook.com/search',
    ],
    viewNodeTargets: [
      ViewNodeTarget(
        targetId: 'fb_watch_tab',
        packageName: 'com.facebook.katana',
        resourceIdPatterns: ['video_home_root_view'],
        contentDescriptionPatterns: ['Video', 'Watch'],
        defaultAction: ViewInterceptionAction.navigateBack,
        description: 'Facebook Watch Infinite Video Stream',
      ),
    ],
    enableMindfulInterstitial: true,
    mindfulPauseSeconds: 10,
    motivationalPrompt: 'Use Facebook for Marketplace or Groups, avoid the algorithmic feed.',
  );

  // ===========================================================================
  // 9. TWITCH (Discovery Browse vs Followed Channels & Chat)
  // ===========================================================================
  static const SurgicalRuleModel twitch = SurgicalRuleModel(
    platformId: 'twitch',
    displayName: 'Twitch',
    iconGlyph: '🎮',
    packageNames: ['tv.twitch.android.app'],
    subfeatureToggles: {
      SurgicalSubfeature.explore: true,
      SurgicalSubfeature.directMessages: false,
      SurgicalSubfeature.search: false,
    },
    subfeatureDomains: {
      SurgicalSubfeature.explore: [
        'gql.twitch.tv/browse',
      ],
    },
    chatWhitelistDomains: [
      'irc-ws.chat.twitch.tv',
      'whispers.twitch.tv',
    ],
    searchWhitelistDomains: [
      'twitch.tv/search',
    ],
    enableMindfulInterstitial: false,
    mindfulPauseSeconds: 10,
    motivationalPrompt: 'Watch intentional streams, skip mindless feed browsing.',
  );

  // ===========================================================================
  // 10. PINTEREST (Infinite Scroll vs Specific Boards)
  // ===========================================================================
  static const SurgicalRuleModel pinterest = SurgicalRuleModel(
    platformId: 'pinterest',
    displayName: 'Pinterest',
    iconGlyph: '📌',
    packageNames: ['com.pinterest'],
    subfeatureToggles: {
      SurgicalSubfeature.feed: true,
      SurgicalSubfeature.search: false,
      SurgicalSubfeature.directMessages: false,
    },
    subfeatureDomains: {
      SurgicalSubfeature.feed: [
        'api.pinterest.com/v3/feeds/home',
      ],
    },
    chatWhitelistDomains: [
      'api.pinterest.com/v3/conversations',
    ],
    searchWhitelistDomains: [
      'pinterest.com/search',
    ],
    enableMindfulInterstitial: false,
    mindfulPauseSeconds: 10,
    motivationalPrompt: 'Search for what you need instead of aimless pin scrolling.',
  );

  // ===========================================================================
  // 11. THREADS (Algorithmic Feed vs Notifications)
  // ===========================================================================
  static const SurgicalRuleModel threads = SurgicalRuleModel(
    platformId: 'threads',
    displayName: 'Threads',
    iconGlyph: '🧵',
    packageNames: ['com.instagram.barcelona'],
    subfeatureToggles: {
      SurgicalSubfeature.feed: true,
      SurgicalSubfeature.search: false,
    },
    subfeatureDomains: {
      SurgicalSubfeature.feed: [
        'graph.threads.net/feed',
      ],
    },
    chatWhitelistDomains: [
      'threads.net/activity',
      'graph.threads.net/messages',
    ],
    searchWhitelistDomains: [
      'threads.net/search',
    ],
    enableMindfulInterstitial: true,
    mindfulPauseSeconds: 10,
    motivationalPrompt: 'Algorithmic text streams trigger compulsive checking.',
  );

  // ===========================================================================
  // 12. DISCORD (Discovery vs DMs & Friend Servers)
  // ===========================================================================
  static const SurgicalRuleModel discord = SurgicalRuleModel(
    platformId: 'discord',
    displayName: 'Discord',
    iconGlyph: '💬',
    packageNames: ['com.discord'],
    subfeatureToggles: {
      SurgicalSubfeature.explore: true,
      SurgicalSubfeature.directMessages: false,
    },
    subfeatureDomains: {
      SurgicalSubfeature.explore: [
        'discord.com/api/v9/discoverable-guilds',
      ],
    },
    chatWhitelistDomains: [
      'gateway.discord.gg',
      'discord.com/api/v9/channels',
    ],
    searchWhitelistDomains: [],
    enableMindfulInterstitial: false,
    mindfulPauseSeconds: 5,
    motivationalPrompt: 'Stay connected with your core community.',
  );

  /// All 12 curated surgical platform rules in prioritized order.
  static const List<SurgicalRuleModel> allPlatforms = [
    instagram,
    youtube,
    reddit,
    tiktok,
    twitterX,
    linkedin,
    snapchat,
    facebook,
    twitch,
    pinterest,
    threads,
    discord,
  ];

  /// Resolves surgical rule model by platform ID.
  static SurgicalRuleModel? getPlatformById(String id) {
    for (final p in allPlatforms) {
      if (p.platformId == id) return p;
    }
    return null;
  }

  /// Alias for getPlatformById supporting common platform identifiers.
  static SurgicalRuleModel? getPlatform(String id) {
    return getPlatformById(id) ?? (id == 'twitter' ? twitterX : null);
  }

  /// Resolves surgical rule model matching an Android package name.
  static SurgicalRuleModel? getPlatformByPackage(String packageName) {
    for (final p in allPlatforms) {
      if (p.packageNames.contains(packageName)) return p;
    }
    return null;
  }
}
