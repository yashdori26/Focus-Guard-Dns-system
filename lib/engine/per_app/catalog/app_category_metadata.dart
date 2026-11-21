import 'package:flutter/material.dart';
import '../per_app_database.dart';

/// Rich metadata descriptor for each managed application category.
class AppCategoryMetadata {
  final AppCategory category;
  final String displayName;
  final String shortDescription;
  final String iconGlyph;
  final IconData materialIcon;
  final Color primaryColor;
  final Color accentColor;
  final int baseAddictivenessScore;
  final bool isDefaultBlockedInStrictMode;
  final bool isExtremeHarmCategory;
  final List<String> commonKeywords;

  const AppCategoryMetadata({
    required this.category,
    required this.displayName,
    required this.shortDescription,
    required this.iconGlyph,
    required this.materialIcon,
    required this.primaryColor,
    required this.accentColor,
    required this.baseAddictivenessScore,
    this.isDefaultBlockedInStrictMode = true,
    this.isExtremeHarmCategory = false,
    required this.commonKeywords,
  });

  static const Map<AppCategory, AppCategoryMetadata> registry = {
    AppCategory.shortFormVideo: AppCategoryMetadata(
      category: AppCategory.shortFormVideo,
      displayName: 'Short-Form Video',
      shortDescription: 'Algorithmic vertical video loops designed for dopamine spikes and infinite scroll.',
      iconGlyph: '⚡',
      materialIcon: Icons.play_circle_filled_rounded,
      primaryColor: Color(0xFFFF2A54),
      accentColor: Color(0xFFFF6584),
      baseAddictivenessScore: 98,
      isDefaultBlockedInStrictMode: true,
      isExtremeHarmCategory: false,
      commonKeywords: ['tiktok', 'reels', 'shorts', 'short video', 'vertical video', 'clips'],
    ),
    AppCategory.social: AppCategoryMetadata(
      category: AppCategory.social,
      displayName: 'Social Media',
      shortDescription: 'Feeds, status updates, stories, and algorithmic social validation loops.',
      iconGlyph: '🌐',
      materialIcon: Icons.share_rounded,
      primaryColor: Color(0xFF3B82F6),
      accentColor: Color(0xFF60A5FA),
      baseAddictivenessScore: 88,
      isDefaultBlockedInStrictMode: true,
      isExtremeHarmCategory: false,
      commonKeywords: ['social', 'feed', 'post', 'friends', 'followers', 'threads'],
    ),
    AppCategory.longFormVideo: AppCategoryMetadata(
      category: AppCategory.longFormVideo,
      displayName: 'Video & Streaming',
      shortDescription: 'Full-length video streaming, live broadcasts, and episodic binge entertainment.',
      iconGlyph: '🎬',
      materialIcon: Icons.movie_filter_rounded,
      primaryColor: Color(0xFFE11D48),
      accentColor: Color(0xFFFB7185),
      baseAddictivenessScore: 82,
      isDefaultBlockedInStrictMode: true,
      isExtremeHarmCategory: false,
      commonKeywords: ['stream', 'movie', 'tv', 'youtube', 'netflix', 'twitch', 'broadcast'],
    ),
    AppCategory.gaming: AppCategoryMetadata(
      category: AppCategory.gaming,
      displayName: 'Mobile Games',
      shortDescription: 'Free-to-play mobile games with microtransactions, loot boxes, and retention loops.',
      iconGlyph: '🎮',
      materialIcon: Icons.sports_esports_rounded,
      primaryColor: Color(0xFF8B5CF6),
      accentColor: Color(0xFFA78BFA),
      baseAddictivenessScore: 92,
      isDefaultBlockedInStrictMode: true,
      isExtremeHarmCategory: false,
      commonKeywords: ['game', 'arcade', 'battle royale', 'rpg', 'gacha', 'multiplayer'],
    ),
    AppCategory.adult: AppCategoryMetadata(
      category: AppCategory.adult,
      displayName: 'Adult & 18+ Content',
      shortDescription: 'Explicit adult media, pornography, cam sites, and high-neurochemical stimulants.',
      iconGlyph: '🔞',
      materialIcon: Icons.warning_amber_rounded,
      primaryColor: Color(0xFFDC2626),
      accentColor: Color(0xFFEF4444),
      baseAddictivenessScore: 100,
      isDefaultBlockedInStrictMode: true,
      isExtremeHarmCategory: true,
      commonKeywords: ['adult', 'porn', 'nsfw', 'xxx', 'cam', 'erotic'],
    ),
    AppCategory.gambling: AppCategoryMetadata(
      category: AppCategory.gambling,
      displayName: 'Gambling & Betting',
      shortDescription: 'Online casinos, sports betting, crypto slots, and variable-reward financial traps.',
      iconGlyph: '🎰',
      materialIcon: Icons.casino_rounded,
      primaryColor: Color(0xFFD97706),
      accentColor: Color(0xFFFBBF24),
      baseAddictivenessScore: 99,
      isDefaultBlockedInStrictMode: true,
      isExtremeHarmCategory: true,
      commonKeywords: ['bet', 'casino', 'poker', 'slots', 'jackpot', 'lottery', 'stake'],
    ),
    AppCategory.shopping: AppCategoryMetadata(
      category: AppCategory.shopping,
      displayName: 'Impulse Shopping',
      shortDescription: 'E-commerce flash sales, algorithmic product feeds, and impulse micro-purchases.',
      iconGlyph: '🛍️',
      materialIcon: Icons.shopping_bag_rounded,
      primaryColor: Color(0xFF059669),
      accentColor: Color(0xFF34D399),
      baseAddictivenessScore: 75,
      isDefaultBlockedInStrictMode: false,
      isExtremeHarmCategory: false,
      commonKeywords: ['shopping', 'deals', 'sale', 'store', 'cart', 'buy', 'discount'],
    ),
    AppCategory.browser: AppCategoryMetadata(
      category: AppCategory.browser,
      displayName: 'Web Browsers',
      shortDescription: 'General web browsers capable of unrestricted web access and bypassing app gates.',
      iconGlyph: '🌍',
      materialIcon: Icons.language_rounded,
      primaryColor: Color(0xFF0284C7),
      accentColor: Color(0xFF38BDF8),
      baseAddictivenessScore: 65,
      isDefaultBlockedInStrictMode: false,
      isExtremeHarmCategory: false,
      commonKeywords: ['browser', 'chrome', 'firefox', 'safari', 'opera', 'edge', 'web'],
    ),
    AppCategory.communication: AppCategoryMetadata(
      category: AppCategory.communication,
      displayName: 'Direct Communication',
      shortDescription: 'One-on-one and group messaging apps required for essential interpersonal communication.',
      iconGlyph: '💬',
      materialIcon: Icons.chat_bubble_rounded,
      primaryColor: Color(0xFF10B981),
      accentColor: Color(0xFF6EE7B7),
      baseAddictivenessScore: 45,
      isDefaultBlockedInStrictMode: false,
      isExtremeHarmCategory: false,
      commonKeywords: ['chat', 'message', 'dm', 'sms', 'call', 'talk'],
    ),
    AppCategory.productivity: AppCategoryMetadata(
      category: AppCategory.productivity,
      displayName: 'Productivity & Study',
      shortDescription: 'Tools for notes, study, reading, learning, coding, and healthy digital creation.',
      iconGlyph: '📚',
      materialIcon: Icons.auto_stories_rounded,
      primaryColor: Color(0xFF6366F1),
      accentColor: Color(0xFF818CF8),
      baseAddictivenessScore: 10,
      isDefaultBlockedInStrictMode: false,
      isExtremeHarmCategory: false,
      commonKeywords: ['study', 'book', 'notes', 'work', 'code', 'reading', 'focus'],
    ),
    AppCategory.system: AppCategoryMetadata(
      category: AppCategory.system,
      displayName: 'System & Utilities',
      shortDescription: 'Critical OS services, settings, phone dials, and system navigation tools.',
      iconGlyph: '⚙️',
      materialIcon: Icons.settings_suggest_rounded,
      primaryColor: Color(0xFF64748B),
      accentColor: Color(0xFF94A3B8),
      baseAddictivenessScore: 5,
      isDefaultBlockedInStrictMode: false,
      isExtremeHarmCategory: false,
      commonKeywords: ['system', 'android', 'settings', 'phone', 'utility'],
    ),
  };

  static AppCategoryMetadata of(AppCategory cat) {
    return registry[cat] ?? registry[AppCategory.social]!;
  }
}
