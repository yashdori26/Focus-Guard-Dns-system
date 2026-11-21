import 'package:flutter/foundation.dart';
import 'surgical_domain_definitions.dart';

/// Compiled pattern match result.
enum SurgicalDecision {
  blackholeFeed,
  whitelistChat,
  whitelistSearch,
  passThrough,
}

/// High-performance wildcard and URL path compiler for surgical traffic inspection.
class SurgicalPatternCompiler {
  final Set<String> _feedBlacklist = {};
  final Set<String> _chatWhitelist = {};
  final Set<String> _searchWhitelist = {};
  final List<String> _feedPathSubstrings = [];

  SurgicalPatternCompiler({
    Map<SurgicalPlatform, bool>? platformToggles,
  }) {
    _compile(platformToggles ?? {});
  }

  void _compile(Map<SurgicalPlatform, bool> toggles) {
    _feedBlacklist.clear();
    _chatWhitelist.clear();
    _searchWhitelist.clear();
    _feedPathSubstrings.clear();

    SurgicalDomainDefinitions.platformRules.forEach((platform, rule) {
      final isEnabled = toggles[platform] ?? true;
      if (isEnabled) {
        _feedBlacklist.addAll(rule.feedBlacklistDomains);
        _chatWhitelist.addAll(rule.chatWhitelistDomains);
        _searchWhitelist.addAll(rule.searchWhitelistDomains);
        _feedPathSubstrings.addAll(rule.feedUrlPathPatterns);
      }
    });
  }

  /// Evaluates an incoming domain name.
  SurgicalDecision evaluateDomain(String domain) {
    final clean = domain.trim().toLowerCase();

    // Check chat whitelist first
    for (final white in _chatWhitelist) {
      if (clean == white || clean.endsWith('.$white')) {
        return SurgicalDecision.whitelistChat;
      }
    }

    // Check search whitelist
    for (final white in _searchWhitelist) {
      if (clean == white || clean.endsWith('.$white')) {
        return SurgicalDecision.whitelistSearch;
      }
    }

    // Check feed blackhole list
    for (final black in _feedBlacklist) {
      if (clean == black || clean.endsWith('.$black') || black.contains(clean)) {
        return SurgicalDecision.blackholeFeed;
      }
    }

    return SurgicalDecision.passThrough;
  }

  /// Evaluates a full URL path.
  SurgicalDecision evaluateUrlPath(String urlOrPath) {
    final lower = urlOrPath.toLowerCase();

    for (final pattern in _feedPathSubstrings) {
      if (lower.contains(pattern)) {
        return SurgicalDecision.blackholeFeed;
      }
    }

    return evaluateDomain(urlOrPath);
  }

  Set<String> get allActiveBlockedDomains => Set.unmodifiable(_feedBlacklist);
  Set<String> get allActiveAllowedDomains => Set.unmodifiable(_chatWhitelist..addAll(_searchWhitelist));
}
