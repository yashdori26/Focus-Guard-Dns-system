import 'package:flutter_test/flutter_test.dart';
import 'package:focus_dns/engine/per_app/catalog/app_category_metadata.dart';
import 'package:focus_dns/engine/per_app/catalog/app_definition.dart';
import 'package:focus_dns/engine/per_app/catalog/comprehensive_app_catalog.dart';
import 'package:focus_dns/engine/per_app/catalog/productive_alternative_registry.dart';
import 'package:focus_dns/engine/per_app/per_app_database.dart';

void main() {
  group('ComprehensiveAppCatalog & Categorization Deep Tests', () {
    test('1. AppCategoryMetadata contains rich descriptors for all 11 categories', () {
      for (final cat in AppCategory.values) {
        final meta = AppCategoryMetadata.of(cat);
        expect(meta.category, equals(cat));
        expect(meta.displayName.isNotEmpty, isTrue);
        expect(meta.shortDescription.isNotEmpty, isTrue);
        expect(meta.iconGlyph.isNotEmpty, isTrue);
        expect(meta.baseAddictivenessScore, inInclusiveRange(0, 100));
        expect(meta.commonKeywords.isNotEmpty, isTrue);
      }
    });

    test('2. Extreme harm categories are correctly flagged (Adult & Gambling)', () {
      final adultMeta = AppCategoryMetadata.of(AppCategory.adult);
      final gamblingMeta = AppCategoryMetadata.of(AppCategory.gambling);
      final socialMeta = AppCategoryMetadata.of(AppCategory.social);

      expect(adultMeta.isExtremeHarmCategory, isTrue);
      expect(gamblingMeta.isExtremeHarmCategory, isTrue);
      expect(socialMeta.isExtremeHarmCategory, isFalse);
    });

    test('3. Comprehensive catalog contains extensive app definitions', () {
      expect(ComprehensiveAppCatalog.allDefinitions.length, greaterThanOrEqualTo(25));
    });

    test('4. All catalog definitions have non-empty packages and valid domains', () {
      for (final def in ComprehensiveAppCatalog.allDefinitions) {
        expect(def.id.isNotEmpty, isTrue);
        expect(def.name.isNotEmpty, isTrue);
        expect(def.primaryPackage.isNotEmpty, isTrue);
        expect(def.networkDomains.isNotEmpty, isTrue);
        expect(def.dopamineScore, inInclusiveRange(1, 100));
        expect(def.defaultAllocatedLockMinutes, greaterThan(0));
      }
    });

    test('5. findByPackage resolves Instagram, TikTok, and YouTube packages correctly', () {
      final insta = ComprehensiveAppCatalog.findByPackage('com.instagram.android');
      expect(insta, isNotNull);
      expect(insta!.id, equals('instagram'));

      final tiktok = ComprehensiveAppCatalog.findByPackage('com.zhiliaoapp.musically');
      expect(tiktok, isNotNull);
      expect(tiktok!.id, equals('tiktok'));

      final yt = ComprehensiveAppCatalog.findByPackage('com.google.android.youtube');
      expect(yt, isNotNull);
      expect(yt!.id, equals('youtube_shorts'));
    });

    test('6. findByDomain resolves subdomains and CDNs accurately', () {
      final reels = ComprehensiveAppCatalog.findByDomain('edge-chat.instagram.com');
      expect(reels, isNotNull);
      expect(reels!.id, equals('instagram'));

      final tiktokCdn = ComprehensiveAppCatalog.findByDomain('v16m.tiktokcdn.com');
      expect(tiktokCdn, isNotNull);
      expect(tiktokCdn!.id, equals('tiktok'));

      final nonExistent = ComprehensiveAppCatalog.findByDomain('completely-unknown-domain-xyz.org');
      expect(nonExistent, isNull);
    });

    test('7. AppDefinition conversion to ManagedAppRecord preserves properties', () {
      final def = ComprehensiveAppCatalog.allDefinitions.first;
      final record = def.toManagedRecord(allocatedMinutes: 300, isLocked: true);

      expect(record.appId, equals(def.id));
      expect(record.appName, equals(def.name));
      expect(record.packageName, equals(def.primaryPackage));
      expect(record.allocatedLockMinutes, equals(300));
      expect(record.isLocked, isTrue);
    });

    test('8. ProductiveAlternativeRegistry provides high-value substitutes', () {
      expect(ProductiveAlternativeRegistry.alternatives.length, greaterThanOrEqualTo(8));

      final kindle = ProductiveAlternativeRegistry.findById('kindle');
      expect(kindle.name, contains('Kindle'));
      expect(kindle.webUrl, contains('amazon.com'));

      final suggested = ProductiveAlternativeRegistry.getSuggestedForCategory('gaming');
      expect(suggested.id, equals('lichess'));
    });
  });
}
