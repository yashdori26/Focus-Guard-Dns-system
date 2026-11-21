import 'package:flutter_test/flutter_test.dart';
import 'package:focus_dns/engine/surgical/catalog/surgical_url_filter_rules.dart';

void main() {
  group('Surgical URL Filter Rules & Sanitizer Tests', () {
    test('Strips global tracking query parameters (fbclid, igshid, utm_source)', () {
      const dirtyUrl = 'https://example.com/article?fbclid=IwAR123&utm_source=newsletter&utm_medium=email&title=Clean';
      final clean = SurgicalUrlFilterRules.sanitize(dirtyUrl);

      expect(clean.contains('fbclid'), isFalse);
      expect(clean.contains('utm_source'), isFalse);
      expect(clean.contains('utm_medium'), isFalse);
      expect(clean.contains('title=Clean'), isTrue);
    });

    test('YouTube URLs have autoplay stripped and forced to 0', () {
      const ytUrl = 'https://www.youtube.com/watch?v=dQw4w9WgXcQ&autoplay=1&feature=share&si=abc123';
      final sanitized = SurgicalUrlFilterRules.sanitize(ytUrl);

      expect(sanitized.contains('autoplay=0'), isTrue);
      expect(sanitized.contains('si='), isFalse);
      expect(sanitized.contains('feature='), isFalse);
      expect(sanitized.contains('v=dQw4w9WgXcQ'), isTrue);
    });

    test('YouTube Shorts path is blackholed (returns empty string)', () {
      const shortsUrl = 'https://www.youtube.com/shorts/dQw4w9WgXcQ';
      final sanitized = SurgicalUrlFilterRules.sanitize(shortsUrl);

      expect(sanitized, isEmpty);
    });

    test('Instagram Reels path is blackholed (returns empty string)', () {
      const reelsUrl = 'https://www.instagram.com/reels/123456789/';
      final sanitized = SurgicalUrlFilterRules.sanitize(reelsUrl);

      expect(sanitized, isEmpty);
    });

    test('Instagram normal post with tracking params is cleaned but preserved', () {
      const igPost = 'https://www.instagram.com/p/C12345/?igshid=YmMyMTA2M2Y=&utm_source=ig_web_copy_link';
      final sanitized = SurgicalUrlFilterRules.sanitize(igPost);

      expect(sanitized.contains('/p/C12345/'), isTrue);
      expect(sanitized.contains('igshid'), isFalse);
      expect(sanitized.contains('utm_source'), isFalse);
    });

    test('Twitter / X share links have analytics tracking stripped', () {
      const tweetUrl = 'https://twitter.com/user/status/123456789?s=20&t=abcdef&ref_src=twsrc';
      final sanitized = SurgicalUrlFilterRules.sanitize(tweetUrl);

      expect(sanitized.contains('/status/123456789'), isTrue);
      expect(sanitized.contains('s=20'), isFalse);
      expect(sanitized.contains('t=abcdef'), isFalse);
      expect(sanitized.contains('ref_src'), isFalse);
    });

    test('isSeveredPath identifies addictive media paths accurately', () {
      expect(SurgicalUrlFilterRules.isSeveredPath('https://youtube.com/shorts/abc'), isTrue);
      expect(SurgicalUrlFilterRules.isSeveredPath('https://instagram.com/reels/xyz'), isTrue);
      expect(SurgicalUrlFilterRules.isSeveredPath('https://tiktok.com/@user/video/foryou'), isTrue);
      expect(SurgicalUrlFilterRules.isSeveredPath('https://twitter.com/explore'), isTrue);

      expect(SurgicalUrlFilterRules.isSeveredPath('https://instagram.com/direct/inbox'), isFalse);
      expect(SurgicalUrlFilterRules.isSeveredPath('https://youtube.com/watch?v=123'), isFalse);
    });

    test('Malformed and empty URLs handled defensively', () {
      expect(SurgicalUrlFilterRules.sanitize(''), equals(''));
      expect(SurgicalUrlFilterRules.sanitize('not a url'), equals('not a url'));
    });
  });
}
