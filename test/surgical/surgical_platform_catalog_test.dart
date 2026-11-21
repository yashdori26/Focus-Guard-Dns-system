import 'package:flutter_test/flutter_test.dart';
import 'package:focus_dns/engine/surgical/catalog/surgical_platform_catalog.dart';
import 'package:focus_dns/engine/surgical/catalog/surgical_subfeature_types.dart';
import 'package:focus_dns/engine/surgical/models/surgical_rule_model.dart';
import 'package:focus_dns/engine/surgical/models/view_node_target.dart';

void main() {
  group('1. Surgical Platform Catalog Integrity Tests', () {
    test('All 12+ built-in platforms are registered with valid metadata', () {
      final platforms = SurgicalPlatformCatalog.allPlatforms;
      expect(platforms.length, greaterThanOrEqualTo(12));

      final expectedPlatforms = [
        'instagram',
        'youtube',
        'reddit',
        'tiktok',
        'twitter',
        'linkedin',
        'snapchat',
        'facebook',
        'twitch',
        'pinterest',
        'threads',
        'discord',
      ];

      for (final id in expectedPlatforms) {
        final platform = SurgicalPlatformCatalog.getPlatform(id);
        expect(platform, isNotNull, reason: 'Platform $id should be present in catalog');
        expect(platform!.displayName.isNotEmpty, isTrue);
        expect(platform.iconGlyph.isNotEmpty, isTrue);
        expect(platform.chatWhitelistDomains.isNotEmpty, isTrue,
            reason: 'Platform $id must define communication whitelist gateways');
      }
    });

    test('Instagram policy correctly defines reels, explore, feed and direct messages', () {
      final ig = SurgicalPlatformCatalog.getPlatform('instagram');
      expect(ig, isNotNull);
      expect(ig!.packageNames, contains('com.instagram.android'));

      // Check subfeature domains
      expect(ig.subfeatureDomains[SurgicalSubfeature.reelsOrShorts], isNotEmpty);
      expect(ig.subfeatureDomains[SurgicalSubfeature.reelsOrShorts], contains('reels.instagram.com'));
      expect(ig.subfeatureDomains[SurgicalSubfeature.explore], isNotEmpty);

      // Check communication whitelist
      expect(ig.chatWhitelistDomains, contains('edge-chat.instagram.com'));
      expect(ig.chatWhitelistDomains, contains('graph.instagram.com'));

      // Check view node targets
      expect(ig.viewNodeTargets.isNotEmpty, isTrue);
      final hasReelsTarget = ig.viewNodeTargets.any(
        (t) => t.targetId.contains('reel') || t.resourceIdPatterns.any((p) => p.contains('clip')),
      );
      expect(hasReelsTarget, isTrue);
    });

    test('YouTube policy correctly defines shorts, feeds, and live chat whitelist', () {
      final yt = SurgicalPlatformCatalog.getPlatform('youtube');
      expect(yt, isNotNull);
      expect(yt!.packageNames, contains('com.google.android.youtube'));
      expect(yt.subfeatureDomains[SurgicalSubfeature.reelsOrShorts], contains('googlevideo.com'));
      expect(yt.chatWhitelistDomains, contains('youtube.com/live_chat'));

      final shortsTarget = yt.viewNodeTargets.firstWhere((t) => t.targetId == 'yt_shorts_tab');
      expect(shortsTarget.resourceIdPatterns, contains('reel_recycler'));
    });

    test('Reddit policy decouples r/popular and media CDN from Reddit Chat', () {
      final reddit = SurgicalPlatformCatalog.getPlatform('reddit');
      expect(reddit, isNotNull);
      expect(reddit!.packageNames, contains('com.reddit.frontpage'));
      expect(reddit.subfeatureDomains[SurgicalSubfeature.reelsOrShorts], contains('v.redd.it'));
      expect(reddit.chatWhitelistDomains, contains('chat.reddit.com'));
      expect(reddit.chatWhitelistDomains, contains('sendbird.reddit.com'));
    });

    test('TikTok policy severs For You Page video CDNs while protecting messages', () {
      final tiktok = SurgicalPlatformCatalog.getPlatform('tiktok');
      expect(tiktok, isNotNull);
      expect(tiktok!.packageNames, contains('com.zhiliaoapp.musically'));
      expect(tiktok.subfeatureDomains[SurgicalSubfeature.reelsOrShorts], isNotEmpty);
      expect(tiktok.chatWhitelistDomains, contains('im-api.tiktok.com'));
    });

    test('X / Twitter policy decouples algorithmic timeline from Direct Messages', () {
      final twitter = SurgicalPlatformCatalog.getPlatform('twitter');
      expect(twitter, isNotNull);
      expect(twitter!.packageNames, contains('com.twitter.android'));
      expect(twitter.subfeatureDomains[SurgicalSubfeature.reelsOrShorts], contains('video.twimg.com'));
      expect(twitter.chatWhitelistDomains, contains('twitter.com/i/chat'));
      expect(twitter.chatWhitelistDomains, contains('x.com/messages'));
    });

    test('LinkedIn policy decouples feed scroll from InMail and Job Search', () {
      final linkedin = SurgicalPlatformCatalog.getPlatform('linkedin');
      expect(linkedin, isNotNull);
      expect(linkedin!.packageNames, contains('com.linkedin.android'));
      expect(linkedin.chatWhitelistDomains, contains('linkedin.com/messaging'));
      expect(linkedin.searchWhitelistDomains, contains('linkedin.com/jobs'));
    });

    test('Discord policy isolates discoverable servers while preserving direct messages', () {
      final discord = SurgicalPlatformCatalog.getPlatform('discord');
      expect(discord, isNotNull);
      expect(discord!.packageNames, contains('com.discord'));
      expect(discord.chatWhitelistDomains, contains('gateway.discord.gg'));
    });
  });

  group('2. Serialization & Model Round-Trip Tests', () {
    test('ViewNodeTarget JSON serialization round-trip', () {
      const target = ViewNodeTarget(
        targetId: 'test_node_id',
        packageName: 'com.test.app',
        resourceIdPatterns: ['recycler_view', 'reel_container'],
        contentDescriptionPatterns: ['Reels tab', 'Shorts'],
        textPatterns: ['Reels'],
        classNamePatterns: ['android.widget.RecyclerView'],
        defaultAction: ViewInterceptionAction.showMindfulNudge,
        description: 'Test view sentinel description',
      );

      final json = target.toJson();
      final restored = ViewNodeTarget.fromJson(json);

      expect(restored.targetId, equals(target.targetId));
      expect(restored.packageName, equals(target.packageName));
      expect(restored.resourceIdPatterns, equals(target.resourceIdPatterns));
      expect(restored.contentDescriptionPatterns, equals(target.contentDescriptionPatterns));
      expect(restored.textPatterns, equals(target.textPatterns));
      expect(restored.classNamePatterns, equals(target.classNamePatterns));
      expect(restored.defaultAction, equals(ViewInterceptionAction.showMindfulNudge));
      expect(restored.description, equals(target.description));
    });

    test('ViewNodeTarget matches correctly based on package and resource ID', () {
      const target = ViewNodeTarget(
        targetId: 'ig_reels',
        packageName: 'com.instagram.android',
        resourceIdPatterns: ['clips_viewer', 'reel_player'],
        contentDescriptionPatterns: ['Reels'],
        description: 'IG Reels',
      );

      // Positive match by resource ID
      expect(
        target.matches(
          pkg: 'com.instagram.android',
          resourceId: 'com.instagram.android:id/clips_viewer',
        ),
        isTrue,
      );

      // Positive match by content description
      expect(
        target.matches(
          pkg: 'com.instagram.android',
          contentDescription: 'Reels video playback',
        ),
        isTrue,
      );

      // Negative match by wrong package
      expect(
        target.matches(
          pkg: 'com.different.app',
          resourceId: 'com.instagram.android:id/clips_viewer',
        ),
        isFalse,
      );

      // Negative match with no matching pattern
      expect(
        target.matches(
          pkg: 'com.instagram.android',
          resourceId: 'com.instagram.android:id/direct_message_thread',
        ),
        isFalse,
      );
    });

    test('SurgicalRuleModel JSON serialization round-trip', () {
      final rule = SurgicalRuleModel(
        platformId: 'test_platform',
        displayName: 'Test App',
        iconGlyph: '🧪',
        packageNames: const ['com.test.app'],
        subfeatureToggles: const {
          SurgicalSubfeature.reelsOrShorts: true,
          SurgicalSubfeature.directMessages: false,
        },
        subfeatureDomains: const {
          SurgicalSubfeature.reelsOrShorts: ['reels.test.com', '*.video.test.com'],
        },
        subfeatureUrlPaths: const {
          SurgicalSubfeature.reelsOrShorts: ['/reels', '/shorts'],
        },
        chatWhitelistDomains: const ['chat.test.com'],
        searchWhitelistDomains: const ['search.test.com'],
        viewNodeTargets: const [
          ViewNodeTarget(
            targetId: 'test_target',
            packageName: 'com.test.app',
            description: 'Test target',
          ),
        ],
        enableMindfulInterstitial: true,
        mindfulPauseSeconds: 15,
        motivationalPrompt: 'Custom prompt text',
      );

      final json = rule.toJson();
      final restored = SurgicalRuleModel.fromJson(json);

      expect(restored.platformId, equals('test_platform'));
      expect(restored.displayName, equals('Test App'));
      expect(restored.iconGlyph, equals('🧪'));
      expect(restored.packageNames, contains('com.test.app'));
      expect(restored.isSubfeatureBlocked(SurgicalSubfeature.reelsOrShorts), isTrue);
      expect(restored.isSubfeatureBlocked(SurgicalSubfeature.directMessages), isFalse);
      expect(restored.chatWhitelistDomains, contains('chat.test.com'));
      expect(restored.searchWhitelistDomains, contains('search.test.com'));
      expect(restored.viewNodeTargets.length, equals(1));
      expect(restored.enableMindfulInterstitial, isTrue);
      expect(restored.mindfulPauseSeconds, equals(15));
      expect(restored.motivationalPrompt, equals('Custom prompt text'));
    });
  });

  group('3. Subfeature Metadata Registry Tests', () {
    test('All 8 subfeatures have defined metadata', () {
      for (final feature in SurgicalSubfeature.values) {
        final meta = SurgicalSubfeatureRegistry.getMetadata(feature);
        expect(meta.displayName.isNotEmpty, isTrue);
        expect(meta.description.isNotEmpty, isTrue);
        expect(meta.dopamineAddictionScore, inInclusiveRange(1, 100));
      }
    });

    test('Reels has higher addiction score than Direct Messages', () {
      final reels = SurgicalSubfeatureRegistry.getMetadata(SurgicalSubfeature.reelsOrShorts);
      final dms = SurgicalSubfeatureRegistry.getMetadata(SurgicalSubfeature.directMessages);

      expect(reels.dopamineAddictionScore, greaterThan(dms.dopamineAddictionScore));
      expect(reels.isCommunicationChannel, isFalse);
      expect(dms.isCommunicationChannel, isTrue);
    });
  });
}
