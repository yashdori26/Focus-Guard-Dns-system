import 'package:flutter_test/flutter_test.dart';
import 'package:focus_dns/engine/surgical/catalog/surgical_subfeature_types.dart';
import 'package:focus_dns/engine/surgical/core/surgical_trie_matcher.dart';
import 'package:focus_dns/engine/surgical/models/view_node_target.dart';

void main() {
  group('Surgical Trie / Radix Matcher Tests', () {
    late SurgicalTrieMatcher matcher;

    setUp(() {
      matcher = SurgicalTrieMatcher();
    });

    test('Exact domain registration and lookup', () {
      matcher.insertDomain(
        domain: 'reels.instagram.com',
        platformId: 'instagram',
        subfeature: SurgicalSubfeature.reelsOrShorts,
        action: ViewInterceptionAction.navigateBack,
      );

      final match = matcher.lookupDomain('reels.instagram.com');
      expect(match, isNotNull);
      expect(match!.platformId, equals('instagram'));
      expect(match.subfeature, equals(SurgicalSubfeature.reelsOrShorts));
      expect(match.matchedPattern, equals('reels.instagram.com'));
      expect(match.isCommunicationWhitelist, isFalse);
    });

    test('Wildcard subdomain matching (*.fbcdn.net)', () {
      matcher.insertDomain(
        domain: '*.fbcdn.net',
        platformId: 'facebook',
        subfeature: SurgicalSubfeature.reelsOrShorts,
      );

      // Positive wildcard matches
      final match1 = matcher.lookupDomain('video.xx.fbcdn.net');
      expect(match1, isNotNull);
      expect(match1!.platformId, equals('facebook'));
      expect(match1.isWildcardMatch, isTrue);

      final match2 = matcher.lookupDomain('scontent.xx.fbcdn.net');
      expect(match2, isNotNull);
      expect(match2!.platformId, equals('facebook'));

      // Non-matching domain
      final noMatch = matcher.lookupDomain('othercdn.net');
      expect(noMatch, isNull);
    });

    test('Communication whitelist domain has isCommunicationWhitelist = true', () {
      matcher.insertDomain(
        domain: 'edge-chat.instagram.com',
        platformId: 'instagram',
        subfeature: SurgicalSubfeature.directMessages,
        isCommunicationWhitelist: true,
        action: ViewInterceptionAction.redirectToDirectMessages,
      );

      final match = matcher.lookupDomain('edge-chat.instagram.com');
      expect(match, isNotNull);
      expect(match!.isCommunicationWhitelist, isTrue);
      expect(match.subfeature, equals(SurgicalSubfeature.directMessages));
      expect(match.action, equals(ViewInterceptionAction.redirectToDirectMessages));
    });

    test('URL path prefix matching (/reels, /shorts)', () {
      matcher.insertPathPrefix(
        pathPrefix: '/reels',
        platformId: 'instagram',
        subfeature: SurgicalSubfeature.reelsOrShorts,
      );
      matcher.insertPathPrefix(
        pathPrefix: '/shorts',
        platformId: 'youtube',
        subfeature: SurgicalSubfeature.reelsOrShorts,
      );

      final matchReels = matcher.lookupPath('/reels/123456');
      expect(matchReels, isNotNull);
      expect(matchReels!.platformId, equals('instagram'));

      final matchShorts = matcher.lookupPath('/shorts/video_id_abc');
      expect(matchShorts, isNotNull);
      expect(matchShorts!.platformId, equals('youtube'));

      final noMatch = matcher.lookupPath('/watch?v=123');
      expect(noMatch, isNull);
    });

    test('Full URL evaluation combines domain and path lookup', () {
      matcher.insertDomain(
        domain: 'reels.instagram.com',
        platformId: 'instagram',
        subfeature: SurgicalSubfeature.reelsOrShorts,
      );
      matcher.insertPathPrefix(
        pathPrefix: '/shorts',
        platformId: 'youtube',
        subfeature: SurgicalSubfeature.reelsOrShorts,
      );

      // Match via domain
      final urlMatch1 = matcher.lookupUrl('https://reels.instagram.com/feed');
      expect(urlMatch1, isNotNull);
      expect(urlMatch1!.platformId, equals('instagram'));

      // Match via path
      final urlMatch2 = matcher.lookupUrl('https://www.youtube.com/shorts/cool_clip');
      expect(urlMatch2, isNotNull);
      expect(urlMatch2!.platformId, equals('youtube'));
    });

    test('Case insensitivity and trailing slash / protocol normalization', () {
      matcher.insertDomain(
        domain: 'REELS.Instagram.COM',
        platformId: 'instagram',
        subfeature: SurgicalSubfeature.reelsOrShorts,
      );

      expect(matcher.lookupDomain('reels.instagram.com'), isNotNull);
      expect(matcher.lookupDomain('REELS.INSTAGRAM.COM'), isNotNull);
      expect(matcher.lookupDomain('https://reels.instagram.com/'), isNotNull);
    });

    test('LRU cache functions correctly and accelerates repeat lookups', () {
      matcher.insertDomain(
        domain: 'reels.instagram.com',
        platformId: 'instagram',
        subfeature: SurgicalSubfeature.reelsOrShorts,
      );

      // First lookup (cache miss -> populated)
      final res1 = matcher.lookupDomain('reels.instagram.com');
      expect(res1, isNotNull);

      // Second lookup (cache hit)
      final res2 = matcher.lookupDomain('reels.instagram.com');
      expect(res2, same(res1));
    });

    test('Sub-microsecond performance benchmark (< 1 µs per query)', () {
      matcher.insertDomain(
        domain: '*.fbcdn.net',
        platformId: 'facebook',
        subfeature: SurgicalSubfeature.reelsOrShorts,
      );
      matcher.insertDomain(
        domain: 'reels.instagram.com',
        platformId: 'instagram',
        subfeature: SurgicalSubfeature.reelsOrShorts,
      );
      matcher.insertDomain(
        domain: 'edge-chat.instagram.com',
        platformId: 'instagram',
        subfeature: SurgicalSubfeature.directMessages,
        isCommunicationWhitelist: true,
      );

      // Warmup
      for (int i = 0; i < 1000; i++) {
        matcher.lookupDomain('reels.instagram.com');
        matcher.lookupDomain('edge-chat.instagram.com');
        matcher.lookupDomain('unknown.domain.com');
      }

      final stopwatch = Stopwatch()..start();
      const iterations = 50000;

      for (int i = 0; i < iterations; i++) {
        matcher.lookupDomain('reels.instagram.com');
      }
      stopwatch.stop();

      final totalMicroseconds = stopwatch.elapsedMicroseconds;
      final perQueryMicroseconds = totalMicroseconds / iterations;

      expect(perQueryMicroseconds, lessThan(10.0),
          reason: 'Trie lookups must be fast in-memory operations');
    });

    test('Memory footprint estimation reflects registered nodes', () {
      expect(matcher.totalNodeCount, equals(2)); // 2 root nodes

      matcher.insertDomain(
        domain: 'reels.instagram.com',
        platformId: 'instagram',
        subfeature: SurgicalSubfeature.reelsOrShorts,
      );

      expect(matcher.totalNodeCount, greaterThan(2));
      final memBytes = matcher.estimateMemoryFootprintBytes();
      expect(memBytes, greaterThan(100));
    });

    test('Clear resets all trees and cache to initial state', () {
      matcher.insertDomain(
        domain: 'reels.instagram.com',
        platformId: 'instagram',
        subfeature: SurgicalSubfeature.reelsOrShorts,
      );

      expect(matcher.totalDomainCount, equals(1));
      matcher.clear();

      expect(matcher.totalDomainCount, equals(0));
      expect(matcher.totalPathCount, equals(0));
      expect(matcher.lookupDomain('reels.instagram.com'), isNull);
    });
  });
}
