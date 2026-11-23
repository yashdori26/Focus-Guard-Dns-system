import 'per_app_database.dart';

/// Pre-configured definitions for common addictive applications.
class InstalledAppsCatalog {
  static const List<ManagedAppRecord> defaultPresets = [
    // Social / Short-form Media
    ManagedAppRecord(
      appId: 'instagram',
      appName: 'Instagram',
      packageName: 'com.instagram.android',
      secondaryPackages: ['com.instagram.lite', 'com.instagram.threadsapp'],
      networkDomains: ['instagram.com', 'cdninstagram.com', 'threads.net'],
      category: AppCategory.shortFormVideo,
      riskRating: DopamineRiskRating.extremeDopamineTrap,
      iconGlyph: '📸',
      allocatedLockMinutes: 480, // 8 hours
    ),
    ManagedAppRecord(
      appId: 'youtube',
      appName: 'YouTube',
      packageName: 'com.google.android.youtube',
      secondaryPackages: ['com.google.android.apps.youtube.music', 'com.google.android.youtube.tv'],
      networkDomains: ['youtube.com', 'googlevideo.com', 'ytimg.com', 'youtu.be'],
      category: AppCategory.longFormVideo,
      riskRating: DopamineRiskRating.high,
      iconGlyph: '▶️',
      allocatedLockMinutes: 120, // 2 hours
    ),
    ManagedAppRecord(
      appId: 'reddit',
      appName: 'Reddit',
      packageName: 'com.reddit.frontpage',
      secondaryPackages: ['reddit.news', 'com.rubenmayayo.reddit'],
      networkDomains: ['reddit.com', 'redd.it', 'redditmedia.com', 'redditstatic.com'],
      category: AppCategory.social,
      riskRating: DopamineRiskRating.high,
      iconGlyph: '👾',
      allocatedLockMinutes: 360, // 6 hours
    ),
    ManagedAppRecord(
      appId: 'tiktok',
      appName: 'TikTok',
      packageName: 'com.zhiliaoapp.musically',
      secondaryPackages: ['com.ss.android.ugc.trill', 'com.zhiliaoapp.musically.go'],
      networkDomains: ['tiktok.com', 'tiktokv.com', 'byteoversea.com', 'ibytedtos.com'],
      category: AppCategory.shortFormVideo,
      riskRating: DopamineRiskRating.extremeDopamineTrap,
      iconGlyph: '🎵',
      allocatedLockMinutes: 240, // 4 hours
    ),
    ManagedAppRecord(
      appId: 'twitter_x',
      appName: 'X (formerly Twitter)',
      packageName: 'com.twitter.android',
      secondaryPackages: ['com.twitter.android.lite'],
      networkDomains: ['twitter.com', 'x.com', 'twimg.com', 't.co'],
      category: AppCategory.social,
      riskRating: DopamineRiskRating.high,
      iconGlyph: '𝕏',
      allocatedLockMinutes: 180, // 3 hours
    ),
    ManagedAppRecord(
      appId: 'snapchat',
      appName: 'Snapchat',
      packageName: 'com.snapchat.android',
      networkDomains: ['snapchat.com', 'sc-cdn.net'],
      category: AppCategory.shortFormVideo,
      riskRating: DopamineRiskRating.high,
      iconGlyph: '👻',
      allocatedLockMinutes: 180,
    ),
    ManagedAppRecord(
      appId: 'facebook',
      appName: 'Facebook',
      packageName: 'com.facebook.katana',
      secondaryPackages: ['com.facebook.lite'],
      networkDomains: ['facebook.com', 'fbcdn.net', 'fbsbx.com'],
      category: AppCategory.social,
      riskRating: DopamineRiskRating.moderate,
      iconGlyph: '📘',
      allocatedLockMinutes: 120,
    ),

    // Gaming
    ManagedAppRecord(
      appId: 'pubg_mobile',
      appName: 'PUBG MOBILE / BGMI',
      packageName: 'com.tencent.ig',
      secondaryPackages: ['com.pubg.krmobile', 'com.pubg.imobile'],
      networkDomains: ['pubgmobile.com', 'krafton.com'],
      category: AppCategory.gaming,
      riskRating: DopamineRiskRating.extremeDopamineTrap,
      iconGlyph: '🎯',
      allocatedLockMinutes: 240,
    ),
    ManagedAppRecord(
      appId: 'roblox',
      appName: 'Roblox',
      packageName: 'com.roblox.client',
      networkDomains: ['roblox.com', 'rbxcdn.com'],
      category: AppCategory.gaming,
      riskRating: DopamineRiskRating.extremeDopamineTrap,
      iconGlyph: '🧱',
      allocatedLockMinutes: 180,
    ),
    ManagedAppRecord(
      appId: 'genshin',
      appName: 'Genshin Impact',
      packageName: 'com.miHoYo.GenshinImpact',
      networkDomains: ['hoyoverse.com', 'mihoyo.com'],
      category: AppCategory.gaming,
      riskRating: DopamineRiskRating.high,
      iconGlyph: '⚔️',
      allocatedLockMinutes: 180,
    ),

    // Shopping / Impulse
    ManagedAppRecord(
      appId: 'amazon_shopping',
      appName: 'Amazon Shopping',
      packageName: 'com.amazon.mShop.android.shopping',
      networkDomains: ['amazon.com', 'media-amazon.com'],
      category: AppCategory.shopping,
      riskRating: DopamineRiskRating.moderate,
      iconGlyph: '📦',
      allocatedLockMinutes: 60,
    ),
    ManagedAppRecord(
      appId: 'shein',
      appName: 'SHEIN',
      packageName: 'com.zzkko',
      networkDomains: ['shein.com'],
      category: AppCategory.shopping,
      riskRating: DopamineRiskRating.high,
      iconGlyph: '👗',
      allocatedLockMinutes: 90,
    ),
  ];

  /// Returns the default preset map indexed by appId.
  static Map<String, ManagedAppRecord> getInitialPresetsMap() {
    final map = <String, ManagedAppRecord>{};
    for (final app in defaultPresets) {
      map[app.appId] = app;
    }
    return map;
  }
}
