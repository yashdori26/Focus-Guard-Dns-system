import 'package:flutter/foundation.dart';

/// Represents a recommended productive substitute application.
@immutable
class ProductiveAlternativeApp {
  final String id;
  final String name;
  final String categoryTag;
  final String packageName;
  final String webUrl;
  final String iconGlyph;
  final String slogan;
  final String whyRecommended;

  const ProductiveAlternativeApp({
    required this.id,
    required this.name,
    required this.categoryTag,
    required this.packageName,
    required this.webUrl,
    required this.iconGlyph,
    required this.slogan,
    required this.whyRecommended,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'categoryTag': categoryTag,
    'packageName': packageName,
    'webUrl': webUrl,
    'iconGlyph': iconGlyph,
    'slogan': slogan,
    'whyRecommended': whyRecommended,
  };

  factory ProductiveAlternativeApp.fromJson(Map<String, dynamic> json) {
    return ProductiveAlternativeApp(
      id: json['id'] as String,
      name: json['name'] as String,
      categoryTag: json['categoryTag'] as String,
      packageName: json['packageName'] as String,
      webUrl: json['webUrl'] as String,
      iconGlyph: json['iconGlyph'] as String,
      slogan: json['slogan'] as String,
      whyRecommended: json['whyRecommended'] as String,
    );
  }
}

/// Curated registry of healthy replacement applications when an addictive app is locked.
class ProductiveAlternativeRegistry {
  static const List<ProductiveAlternativeApp> alternatives = [
    ProductiveAlternativeApp(
      id: 'kindle',
      name: 'Amazon Kindle',
      categoryTag: 'Reading',
      packageName: 'com.amazon.kindle',
      webUrl: 'https://read.amazon.com',
      iconGlyph: '📖',
      slogan: 'Read real books instead of infinite social feeds.',
      whyRecommended: 'Deep reading trains long-form attention spans and neuroplasticity.',
    ),
    ProductiveAlternativeApp(
      id: 'notion',
      name: 'Notion',
      categoryTag: 'Knowledge',
      packageName: 'notion.id',
      webUrl: 'https://notion.so',
      iconGlyph: '📓',
      slogan: 'Write down your ideas and organize your life.',
      whyRecommended: 'Channel restless creative energy into structuring personal goals.',
    ),
    ProductiveAlternativeApp(
      id: 'duolingo',
      name: 'Duolingo',
      categoryTag: 'Languages',
      packageName: 'com.duolingo',
      webUrl: 'https://duolingo.com',
      iconGlyph: '🦉',
      slogan: 'Learn a foreign language in 5-minute micro-bites.',
      whyRecommended: 'Replaces passive doomscrolling with active linguistic mastery.',
    ),
    ProductiveAlternativeApp(
      id: 'anki',
      name: 'AnkiDroid Flashcards',
      categoryTag: 'Spaced Repetition',
      packageName: 'com.ichi2.anki',
      webUrl: 'https://apps.ankiweb.net',
      iconGlyph: '🗂️',
      slogan: 'Master anything through active recall.',
      whyRecommended: 'Solidifies critical knowledge into permanent long-term memory.',
    ),
    ProductiveAlternativeApp(
      id: 'obsidian',
      name: 'Obsidian Notes',
      categoryTag: 'Knowledge Graph',
      packageName: 'md.obsidian',
      webUrl: 'https://obsidian.md',
      iconGlyph: '💎',
      slogan: 'Build your second brain with connected markdown.',
      whyRecommended: 'Builds compound intellectual wealth through interconnected ideas.',
    ),
    ProductiveAlternativeApp(
      id: 'khan_academy',
      name: 'Khan Academy',
      categoryTag: 'Education',
      packageName: 'org.khanacademy.android',
      webUrl: 'https://khanacademy.org',
      iconGlyph: '🎓',
      slogan: 'Learn math, science, and history for free.',
      whyRecommended: 'Structured learning creates genuine intellectual fulfillment.',
    ),
    ProductiveAlternativeApp(
      id: 'audible',
      name: 'Audible Audiobooks',
      categoryTag: 'Audiobooks',
      packageName: 'com.audible.application',
      webUrl: 'https://audible.com',
      iconGlyph: '🎧',
      slogan: 'Listen to world-class literature while resting your eyes.',
      whyRecommended: 'Reduces visual blue-light strain while enriching the mind.',
    ),
    ProductiveAlternativeApp(
      id: 'lichess',
      name: 'Lichess Chess',
      categoryTag: 'Mindful Strategy',
      packageName: 'org.lichess.mobileapp',
      webUrl: 'https://lichess.org',
      iconGlyph: '♟️',
      slogan: 'Play open-source chess with zero ads and pure strategy.',
      whyRecommended: 'Stimulates strategic foresight without dopamine-draining loot boxes.',
    ),
    ProductiveAlternativeApp(
      id: 'waking_up',
      name: 'Waking Up',
      categoryTag: 'Mindfulness',
      packageName: 'org.wakingup.android',
      webUrl: 'https://wakingup.com',
      iconGlyph: '🧘',
      slogan: 'Discover the nature of your mind and step out of distraction.',
      whyRecommended: 'Direct mindfulness practice reduces the root craving impulse.',
    ),
    ProductiveAlternativeApp(
      id: 'coursera',
      name: 'Coursera',
      categoryTag: 'University Courses',
      packageName: 'org.coursera.android',
      webUrl: 'https://coursera.org',
      iconGlyph: '🏛️',
      slogan: 'Advance your career with university certificates.',
      whyRecommended: 'High-value career skill development during reclaimed hours.',
    ),
  ];

  static ProductiveAlternativeApp findById(String id) {
    return alternatives.firstWhere(
      (a) => a.id == id,
      orElse: () => alternatives.first,
    );
  }

  static ProductiveAlternativeApp getSuggestedForCategory(String categoryName) {
    switch (categoryName.toLowerCase()) {
      case 'shortformvideo':
      case 'social':
        return findById('kindle');
      case 'gaming':
        return findById('lichess');
      case 'longformvideo':
        return findById('khan_academy');
      case 'adult':
      case 'gambling':
        return findById('waking_up');
      default:
        return findById('notion');
    }
  }
}
