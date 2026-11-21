import 'package:flutter/foundation.dart';

/// Rule definition for cleaning, sanitizing, and filtering URLs
/// to eliminate autoplay triggers, dopamine recommendation query params, and tracking parameters.
@immutable
class SurgicalUrlSanitizerRule {
  final String domainPattern;
  final List<String> strippedQueryParams;
  final Map<String, String> replacedQueryParams;
  final List<String> blockedPathRegexes;
  final bool forceNoAutoplay;

  const SurgicalUrlSanitizerRule({
    required this.domainPattern,
    this.strippedQueryParams = const [],
    this.replacedQueryParams = const {},
    this.blockedPathRegexes = const [],
    this.forceNoAutoplay = true,
  });

  /// Sanitizes an input URL by removing tracking query parameters and disabling autoplay.
  String sanitizeUrl(String rawUrl) {
    try {
      final uri = Uri.parse(rawUrl);
      if (!uri.host.toLowerCase().contains(domainPattern.toLowerCase())) {
        return rawUrl;
      }

      // Check blocked paths
      for (final regexStr in blockedPathRegexes) {
        if (RegExp(regexStr, caseSensitive: false).hasMatch(uri.path)) {
          return ''; // Blackholed path
        }
      }

      final queryParams = Map<String, String>.from(uri.queryParameters);

      // Strip addictive / tracking parameters
      for (final param in strippedQueryParams) {
        queryParams.remove(param);
      }

      // Apply overrides (e.g. autoplay=0)
      replacedQueryParams.forEach((key, val) {
        queryParams[key] = val;
      });

      if (forceNoAutoplay) {
        queryParams['autoplay'] = '0';
        queryParams['auto_play'] = '0';
      }

      return uri.replace(queryParameters: queryParams.isEmpty ? null : queryParams).toString();
    } catch (_) {
      return rawUrl;
    }
  }
}

/// Registry of curated URL sanitization and autoplay suppression rules.
class SurgicalUrlFilterRules {
  SurgicalUrlFilterRules._();

  static const List<String> globalTrackingParams = [
    'fbclid',
    'igshid',
    'gclid',
    'utm_source',
    'utm_medium',
    'utm_campaign',
    'utm_term',
    'utm_content',
    'si', // YouTube Share tracking
    '_branch_match_id',
    'mc_cid',
    'mc_eid',
  ];

  static final List<SurgicalUrlSanitizerRule> builtInRules = [
    // YouTube: Strips autoplay and redirect loops
    const SurgicalUrlSanitizerRule(
      domainPattern: 'youtube.com',
      strippedQueryParams: ['si', 'feature', 'autoplay', 'app'],
      replacedQueryParams: {'autoplay': '0'},
      blockedPathRegexes: [r'^/shorts/'],
      forceNoAutoplay: true,
    ),

    // Instagram: Strips click tracking and reels redirects
    const SurgicalUrlSanitizerRule(
      domainPattern: 'instagram.com',
      strippedQueryParams: ['igshid', 'fbclid', 'utm_source'],
      blockedPathRegexes: [r'^/reels/'],
      forceNoAutoplay: true,
    ),

    // Reddit: Strips share tracking tokens
    const SurgicalUrlSanitizerRule(
      domainPattern: 'reddit.com',
      strippedQueryParams: ['utm_source', 'utm_medium', 'utm_name', 'share_id'],
      forceNoAutoplay: true,
    ),

    // Twitter / X: Strips analytics tracking tokens
    const SurgicalUrlSanitizerRule(
      domainPattern: 'twitter.com',
      strippedQueryParams: ['s', 't', 'ref_src', 'ref_url'],
      forceNoAutoplay: true,
    ),
    const SurgicalUrlSanitizerRule(
      domainPattern: 'x.com',
      strippedQueryParams: ['s', 't', 'ref_src', 'ref_url'],
      forceNoAutoplay: true,
    ),
  ];

  /// Sanitizes any inbound URL against global tracking lists and domain-specific rules.
  static String sanitize(String url) {
    try {
      var sanitized = url;
      for (final rule in builtInRules) {
        sanitized = rule.sanitizeUrl(sanitized);
        if (sanitized.isEmpty) return '';
      }

      // Universal tracking parameter purge
      final uri = Uri.parse(sanitized);
      if (uri.queryParameters.isNotEmpty) {
        final params = Map<String, String>.from(uri.queryParameters);
        for (final p in globalTrackingParams) {
          params.remove(p);
        }
        return uri.replace(queryParameters: params.isEmpty ? null : params).toString();
      }

      return sanitized;
    } catch (_) {
      return url;
    }
  }

  /// Checks if a URL path matches a severed subfeature route.
  static bool isSeveredPath(String url) {
    final lower = url.toLowerCase();
    return lower.contains('/shorts/') ||
        lower.contains('/reels/') ||
        lower.contains('/foryou') ||
        lower.contains('/explore');
  }
}
