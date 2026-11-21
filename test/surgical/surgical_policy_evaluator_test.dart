import 'package:flutter_test/flutter_test.dart';
import 'package:focus_dns/engine/surgical/catalog/surgical_subfeature_types.dart';
import 'package:focus_dns/engine/surgical/core/surgical_policy_evaluator.dart';
import 'package:focus_dns/engine/surgical/models/view_node_target.dart';

void main() {
  group('Surgical Policy Evaluator Tests', () {
    late SurgicalPolicyEvaluator evaluator;

    setUp(() {
      evaluator = SurgicalPolicyEvaluator();
    });

    test('Instagram: Reels video domain is blackholed while DMs are whitelisted', () {
      // 1. Reels CDN -> Blackhole verdict
      final reelsDecision = evaluator.evaluateDomain('reels.instagram.com');
      expect(reelsDecision.verdict, equals(SurgicalVerdict.blackhole));
      expect(reelsDecision.isBlocked, isTrue);
      expect(reelsDecision.platformId, equals('instagram'));
      expect(reelsDecision.subfeature, equals(SurgicalSubfeature.reelsOrShorts));
      expect(reelsDecision.estimatedSecondsSaved, greaterThan(0));

      // 2. Direct Messages Gateway -> WhitelistChat verdict
      final chatDecision = evaluator.evaluateDomain('edge-chat.instagram.com');
      expect(chatDecision.verdict, equals(SurgicalVerdict.whitelistChat));
      expect(chatDecision.isBlocked, isFalse);
      expect(chatDecision.subfeature, equals(SurgicalSubfeature.directMessages));
      expect(chatDecision.action, equals(ViewInterceptionAction.redirectToDirectMessages));
    });

    test('YouTube: Shorts video CDN is blackholed while Live Chat is whitelisted', () {
      final shortsDecision = evaluator.evaluateDomain('googlevideo.com');
      expect(shortsDecision.verdict, equals(SurgicalVerdict.blackhole));
      expect(shortsDecision.isBlocked, isTrue);
      expect(shortsDecision.platformId, equals('youtube'));

      final chatDecision = evaluator.evaluateUrl('https://www.youtube.com/live_chat');
      expect(chatDecision.verdict, equals(SurgicalVerdict.whitelistChat));
      expect(chatDecision.isBlocked, isFalse);
    });

    test('Reddit: Media CDN is blackholed while Reddit Chat is whitelisted', () {
      final redditMedia = evaluator.evaluateDomain('v.redd.it');
      expect(redditMedia.verdict, equals(SurgicalVerdict.blackhole));
      expect(redditMedia.isBlocked, isTrue);

      final redditChat = evaluator.evaluateDomain('chat.reddit.com');
      expect(redditChat.verdict, equals(SurgicalVerdict.whitelistChat));
      expect(redditChat.isBlocked, isFalse);
    });

    test('Twitter / X: Video CDN is blackholed while Messages are whitelisted', () {
      final twVideo = evaluator.evaluateDomain('video.twimg.com');
      expect(twVideo.verdict, equals(SurgicalVerdict.blackhole));
      expect(twVideo.isBlocked, isTrue);

      final twChat = evaluator.evaluateUrl('https://x.com/messages');
      expect(twChat.verdict, equals(SurgicalVerdict.whitelistChat));
      expect(twChat.isBlocked, isFalse);
    });

    test('Unmonitored / safe domains receive passThrough verdict', () {
      final wikiDecision = evaluator.evaluateDomain('wikipedia.org');
      expect(wikiDecision.verdict, equals(SurgicalVerdict.passThrough));
      expect(wikiDecision.isBlocked, isFalse);
    });

    test('Dynamic subfeature toggling at runtime updates decision', () {
      // Initially reels are blocked
      expect(evaluator.isSubfeatureBlocked('instagram', SurgicalSubfeature.reelsOrShorts), isTrue);
      expect(evaluator.evaluateDomain('reels.instagram.com').isBlocked, isTrue);

      // User unblocks reels for testing
      evaluator.setSubfeatureToggle(
        platformId: 'instagram',
        subfeature: SurgicalSubfeature.reelsOrShorts,
        blocked: false,
      );

      expect(evaluator.isSubfeatureBlocked('instagram', SurgicalSubfeature.reelsOrShorts), isFalse);
      final unblockedDecision = evaluator.evaluateDomain('reels.instagram.com');
      expect(unblockedDecision.isBlocked, isFalse);
      expect(unblockedDecision.verdict, equals(SurgicalVerdict.passThrough));

      // Re-block reels
      evaluator.setSubfeatureToggle(
        platformId: 'instagram',
        subfeature: SurgicalSubfeature.reelsOrShorts,
        blocked: true,
      );
      expect(evaluator.evaluateDomain('reels.instagram.com').isBlocked, isTrue);
    });

    test('Global surgical master switch pauses all interceptions', () {
      expect(evaluator.evaluateDomain('reels.instagram.com').isBlocked, isTrue);

      // Pause global engine
      evaluator.isGlobalActive = false;
      expect(evaluator.evaluateDomain('reels.instagram.com').isBlocked, isFalse);
      expect(evaluator.evaluateDomain('reels.instagram.com').verdict, equals(SurgicalVerdict.passThrough));

      // Resume global engine
      evaluator.isGlobalActive = true;
      expect(evaluator.evaluateDomain('reels.instagram.com').isBlocked, isTrue);
    });

    test('Batch domain evaluation processes multiple queries correctly', () {
      final domains = [
        'reels.instagram.com',
        'edge-chat.instagram.com',
        'v.redd.it',
        'wikipedia.org',
      ];

      final results = evaluator.batchEvaluateDomains(domains);
      expect(results.length, equals(4));

      expect(results[0].verdict, equals(SurgicalVerdict.blackhole));
      expect(results[1].verdict, equals(SurgicalVerdict.whitelistChat));
      expect(results[2].verdict, equals(SurgicalVerdict.blackhole));
      expect(results[3].verdict, equals(SurgicalVerdict.passThrough));
    });

    test('Evaluates Android accessibility view node targets accurately', () {
      // Instagram Reels fragment
      final igViewDecision = evaluator.evaluateAccessibilityView(
        packageName: 'com.instagram.android',
        resourceId: 'com.instagram.android:id/clips_viewer',
      );
      expect(igViewDecision.isBlocked, isTrue);
      expect(igViewDecision.platformId, equals('instagram'));
      expect(igViewDecision.subfeature, equals(SurgicalSubfeature.reelsOrShorts));

      // YouTube Shorts fragment
      final ytViewDecision = evaluator.evaluateAccessibilityView(
        packageName: 'com.google.android.youtube',
        resourceId: 'com.google.android.youtube:id/reel_recycler',
      );
      expect(ytViewDecision.isBlocked, isTrue);
      expect(ytViewDecision.platformId, equals('youtube'));

      // Non-monitored package
      final nonMonitoredDecision = evaluator.evaluateAccessibilityView(
        packageName: 'com.example.calculator',
        resourceId: 'calc_display',
      );
      expect(nonMonitoredDecision.isBlocked, isFalse);
    });
  });
}
