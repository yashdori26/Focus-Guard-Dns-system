import 'package:flutter/foundation.dart';
import '../catalog/surgical_platform_catalog.dart';
import '../catalog/surgical_custom_rule_store.dart';
import '../catalog/surgical_subfeature_types.dart';
import '../models/surgical_interception_event.dart';
import '../models/surgical_rule_model.dart';
import '../models/view_node_target.dart';
import 'surgical_trie_matcher.dart';

/// The final surgical verdict rendered for an inbound request or view event.
enum SurgicalVerdict {
  /// Traffic is blackholed/sinkholed (Reels/Shorts/Explore media).
  blackhole,

  /// Explicitly permitted communication gateway (DMs, chat WebSockets).
  whitelistChat,

  /// Explicitly permitted search lookup.
  whitelistSearch,

  /// Presents a mindful interstitial nudge pause.
  mindfulNudge,

  /// View hierarchy redirected to direct messages or backwards.
  viewRedirect,

  /// Unfiltered pass-through (not subject to surgical rules).
  passThrough,
}

/// Comprehensive outcome of a surgical policy evaluation.
@immutable
class SurgicalPolicyDecision {
  final SurgicalVerdict verdict;
  final bool isBlocked;
  final ViewInterceptionAction action;
  final String platformId;
  final String platformName;
  final SurgicalSubfeature subfeature;
  final String matchedPattern;
  final String reason;
  final int estimatedSecondsSaved;
  final int estimatedBytesBlocked;
  final DopamineHazardLevel hazardLevel;

  const SurgicalPolicyDecision({
    required this.verdict,
    required this.isBlocked,
    required this.action,
    required this.platformId,
    required this.platformName,
    required this.subfeature,
    required this.matchedPattern,
    required this.reason,
    this.estimatedSecondsSaved = 0,
    this.estimatedBytesBlocked = 0,
    this.hazardLevel = DopamineHazardLevel.mild,
  });

  /// Pass-through default decision.
  factory SurgicalPolicyDecision.passThrough({String reason = 'No surgical policy matched'}) {
    return SurgicalPolicyDecision(
      verdict: SurgicalVerdict.passThrough,
      isBlocked: false,
      action: ViewInterceptionAction.navigateBack,
      platformId: 'none',
      platformName: 'Unknown',
      subfeature: SurgicalSubfeature.feed,
      matchedPattern: '',
      reason: reason,
      estimatedSecondsSaved: 0,
      estimatedBytesBlocked: 0,
      hazardLevel: DopamineHazardLevel.mild,
    );
  }

  /// Converts this decision into a full audit interception event.
  SurgicalInterceptionEvent toInterceptionEvent({
    required String interceptedTarget,
    required InterceptionTriggerSource triggerSource,
    required String packageName,
    String? viewResourceId,
  }) {
    return SurgicalInterceptionEvent(
      eventId: 'evt_${DateTime.now().microsecondsSinceEpoch}',
      timestamp: DateTime.now(),
      platformId: platformId,
      platformName: platformName,
      subfeature: subfeature,
      interceptedTarget: interceptedTarget,
      actionApplied: action,
      triggerSource: triggerSource,
      packageName: packageName,
      viewResourceId: viewResourceId,
      estimatedSecondsSaved: estimatedSecondsSaved,
      estimatedBytesBlocked: estimatedBytesBlocked,
      hazardLevel: hazardLevel,
      notes: reason,
    );
  }
}

/// Master policy evaluator combining Radix / Trie domain matching, active platform
/// sub-feature toggles, view hierarchy node targets, and custom user rules.
class SurgicalPolicyEvaluator {
  final SurgicalTrieMatcher _trieMatcher;
  final SurgicalCustomRuleStore _customRuleStore;

  final Map<String, SurgicalRuleModel> _compiledRules = {};
  final Map<String, String> _packageToPlatformMap = {};
  bool _isGlobalSurgicalDecouplingActive = true;

  SurgicalPolicyEvaluator({
    SurgicalTrieMatcher? trieMatcher,
    SurgicalCustomRuleStore? customRuleStore,
  })  : _trieMatcher = trieMatcher ?? SurgicalTrieMatcher(),
        _customRuleStore = customRuleStore ?? SurgicalCustomRuleStore() {
    compileAllRules();
  }

  /// Reference to internal compiled Radix / Trie matcher.
  SurgicalTrieMatcher get trieMatcher => _trieMatcher;

  /// Whether the global surgical decoupling engine is active.
  bool get isGlobalActive => _isGlobalSurgicalDecouplingActive;

  /// Sets global master switch for surgical decoupling.
  set isGlobalActive(bool value) {
    _isGlobalSurgicalDecouplingActive = value;
  }

  /// Read-only map of all currently compiled platform rules.
  Map<String, SurgicalRuleModel> get compiledRules => Map.unmodifiable(_compiledRules);

  /// Compiles all platform catalog rules and user custom rules into the Trie.
  void compileAllRules() {
    _trieMatcher.clear();
    _compiledRules.clear();
    _packageToPlatformMap.clear();

    // 1. Load built-in platforms from catalog
    for (final rule in SurgicalPlatformCatalog.allPlatforms) {
      _compiledRules[rule.platformId] = rule;
      for (final pkg in rule.packageNames) {
        _packageToPlatformMap[pkg] = rule.platformId;
      }
    }

    // 2. Merge user custom rules from store
    for (final customRule in _customRuleStore.rules) {
      _compiledRules[customRule.platformId] = customRule;
      for (final pkg in customRule.packageNames) {
        _packageToPlatformMap[pkg] = customRule.platformId;
      }
    }

    // 3. Populate Trie with communication whitelist domains (chat / search)
    for (final rule in _compiledRules.values) {
      for (final entry in rule.chatWhitelistDomains) {
        if (entry.contains('/')) {
          final slashIdx = entry.indexOf('/');
          final path = entry.substring(slashIdx);
          _trieMatcher.insertPathPrefix(
            pathPrefix: path,
            platformId: rule.platformId,
            subfeature: SurgicalSubfeature.directMessages,
            isCommunicationWhitelist: true,
            action: ViewInterceptionAction.redirectToDirectMessages,
          );
        } else {
          _trieMatcher.insertDomain(
            domain: entry,
            platformId: rule.platformId,
            subfeature: SurgicalSubfeature.directMessages,
            isCommunicationWhitelist: true,
            action: ViewInterceptionAction.redirectToDirectMessages,
          );
        }
      }

      for (final entry in rule.searchWhitelistDomains) {
        if (entry.contains('/')) {
          final slashIdx = entry.indexOf('/');
          final path = entry.substring(slashIdx);
          _trieMatcher.insertPathPrefix(
            pathPrefix: path,
            platformId: rule.platformId,
            subfeature: SurgicalSubfeature.search,
            isCommunicationWhitelist: true,
          );
        } else {
          _trieMatcher.insertDomain(
            domain: entry,
            platformId: rule.platformId,
            subfeature: SurgicalSubfeature.search,
            isCommunicationWhitelist: true,
          );
        }
      }

      // 4. Populate Trie with sub-feature CDN and URL patterns
      rule.subfeatureDomains.forEach((subfeature, domainList) {
        for (final entry in domainList) {
          if (entry.contains('/')) {
            final slashIdx = entry.indexOf('/');
            final path = entry.substring(slashIdx);
            _trieMatcher.insertPathPrefix(
              pathPrefix: path,
              platformId: rule.platformId,
              subfeature: subfeature,
              isCommunicationWhitelist: false,
              action: rule.enableMindfulInterstitial
                  ? ViewInterceptionAction.showMindfulNudge
                  : ViewInterceptionAction.navigateBack,
            );
          } else {
            _trieMatcher.insertDomain(
              domain: entry,
              platformId: rule.platformId,
              subfeature: subfeature,
              isCommunicationWhitelist: false,
              action: rule.enableMindfulInterstitial
                  ? ViewInterceptionAction.showMindfulNudge
                  : ViewInterceptionAction.navigateBack,
            );
          }
        }
      });

      rule.subfeatureUrlPaths.forEach((subfeature, pathList) {
        for (final path in pathList) {
          _trieMatcher.insertPathPrefix(
            pathPrefix: path,
            platformId: rule.platformId,
            subfeature: subfeature,
            isCommunicationWhitelist: false,
            action: rule.enableMindfulInterstitial
                ? ViewInterceptionAction.showMindfulNudge
                : ViewInterceptionAction.navigateBack,
          );
        }
      });
    }
  }

  /// Evaluates an inbound domain name (e.g. from DNS packet or TLS SNI).
  SurgicalPolicyDecision evaluateDomain(String domain, {String? packageName}) {
    if (!_isGlobalSurgicalDecouplingActive) {
      return SurgicalPolicyDecision.passThrough(reason: 'Global surgical engine disabled');
    }

    final match = _trieMatcher.lookupDomain(domain);
    if (match == null) {
      return SurgicalPolicyDecision.passThrough(reason: 'No surgical rule matched domain: $domain');
    }

    return _evaluateMatchResult(match, domain);
  }

  /// Evaluates an inbound URL (e.g. from HTTP proxy or WebView navigation).
  SurgicalPolicyDecision evaluateUrl(String url, {String? packageName}) {
    if (!_isGlobalSurgicalDecouplingActive) {
      return SurgicalPolicyDecision.passThrough(reason: 'Global surgical engine disabled');
    }

    final match = _trieMatcher.lookupUrl(url);
    if (match == null) {
      return SurgicalPolicyDecision.passThrough(reason: 'No surgical rule matched URL: $url');
    }

    return _evaluateMatchResult(match, url);
  }

  /// Evaluates an Android view hierarchy event from the accessibility service.
  SurgicalPolicyDecision evaluateAccessibilityView({
    required String packageName,
    String? resourceId,
    String? contentDescription,
    String? text,
    String? className,
  }) {
    if (!_isGlobalSurgicalDecouplingActive) {
      return SurgicalPolicyDecision.passThrough(reason: 'Global surgical engine disabled');
    }

    final platformId = _packageToPlatformMap[packageName];
    if (platformId == null) {
      return SurgicalPolicyDecision.passThrough(reason: 'Package $packageName not monitored');
    }

    final rule = _compiledRules[platformId];
    if (rule == null) {
      return SurgicalPolicyDecision.passThrough(reason: 'No rule found for platform $platformId');
    }

    // Inspect view targets defined for this platform
    for (final target in rule.viewNodeTargets) {
      if (target.matches(
        pkg: packageName,
        resourceId: resourceId,
        contentDescription: contentDescription,
        text: text,
        className: className,
      )) {
        // Map targetId to subfeature
        final subfeature = _targetIdToSubfeature(target.targetId);
        final isBlocked = rule.isSubfeatureBlocked(subfeature);

        if (!isBlocked) {
          return SurgicalPolicyDecision.passThrough(
            reason: 'Subfeature ${subfeature.name} is currently allowed in settings',
          );
        }

        final action = rule.enableMindfulInterstitial
            ? ViewInterceptionAction.showMindfulNudge
            : target.defaultAction;

        return SurgicalPolicyDecision(
          verdict: (action == ViewInterceptionAction.showMindfulNudge)
              ? SurgicalVerdict.mindfulNudge
              : SurgicalVerdict.viewRedirect,
          isBlocked: true,
          action: action,
          platformId: platformId,
          platformName: rule.displayName,
          subfeature: subfeature,
          matchedPattern: target.targetId,
          reason: 'Accessibility View intercepted: ${target.description}',
          estimatedSecondsSaved: SurgicalInterceptionEvent.defaultSecondsSaved(subfeature),
          estimatedBytesBlocked: 0, // View redirection avoids downloading upcoming videos
          hazardLevel: SurgicalInterceptionEvent.calculateHazardLevel(subfeature),
        );
      }
    }

    return SurgicalPolicyDecision.passThrough(reason: 'No view target matched in $packageName');
  }

  /// Modifies an individual sub-feature toggle for a platform.
  void setSubfeatureToggle({
    required String platformId,
    required SurgicalSubfeature subfeature,
    required bool blocked,
  }) {
    final existing = _compiledRules[platformId];
    if (existing != null) {
      final updatedToggles = Map<SurgicalSubfeature, bool>.from(existing.subfeatureToggles);
      updatedToggles[subfeature] = blocked;
      _compiledRules[platformId] = existing.copyWith(subfeatureToggles: updatedToggles);
    }
  }

  /// Checks if an individual sub-feature is blocked for a platform.
  bool isSubfeatureBlocked(String platformId, SurgicalSubfeature subfeature) {
    final rule = _compiledRules[platformId];
    if (rule == null) return false;
    return rule.isSubfeatureBlocked(subfeature);
  }

  /// Batch evaluates multiple domains (e.g. DNS burst resolutions).
  List<SurgicalPolicyDecision> batchEvaluateDomains(List<String> domains) {
    return domains.map((d) => evaluateDomain(d)).toList();
  }

  SurgicalPolicyDecision _evaluateMatchResult(
    SurgicalTrieMatchResult match,
    String originalQuery,
  ) {
    final rule = _compiledRules[match.platformId];
    final platformName = rule?.displayName ?? match.platformId;

    // 1. Whitelist Channels (DMs, Search)
    if (match.isCommunicationWhitelist) {
      if (match.subfeature == SurgicalSubfeature.directMessages) {
        return SurgicalPolicyDecision(
          verdict: SurgicalVerdict.whitelistChat,
          isBlocked: false,
          action: ViewInterceptionAction.redirectToDirectMessages,
          platformId: match.platformId,
          platformName: platformName,
          subfeature: SurgicalSubfeature.directMessages,
          matchedPattern: match.matchedPattern,
          reason: 'Communication gateway explicitly whitelisted for intentional messaging',
          estimatedSecondsSaved: 0,
          estimatedBytesBlocked: 0,
          hazardLevel: DopamineHazardLevel.mild,
        );
      } else {
        return SurgicalPolicyDecision(
          verdict: SurgicalVerdict.whitelistSearch,
          isBlocked: false,
          action: ViewInterceptionAction.navigateBack,
          platformId: match.platformId,
          platformName: platformName,
          subfeature: SurgicalSubfeature.search,
          matchedPattern: match.matchedPattern,
          reason: 'Search gateway explicitly whitelisted for intentional knowledge lookup',
          estimatedSecondsSaved: 0,
          estimatedBytesBlocked: 0,
          hazardLevel: DopamineHazardLevel.mild,
        );
      }
    }

    // 2. Addictive Subfeature Traps (Reels, Feed, Explore, etc.)
    final isSubBlocked = rule?.isSubfeatureBlocked(match.subfeature) ?? true;
    if (!isSubBlocked) {
      return SurgicalPolicyDecision.passThrough(
        reason: 'Subfeature ${match.subfeature.name} on $platformName is toggled ALLOWED by user',
      );
    }

    // 3. Blackhole Decision
    final action = (rule?.enableMindfulInterstitial ?? true)
        ? ViewInterceptionAction.showMindfulNudge
        : ViewInterceptionAction.navigateBack;

    return SurgicalPolicyDecision(
      verdict: SurgicalVerdict.blackhole,
      isBlocked: true,
      action: action,
      platformId: match.platformId,
      platformName: platformName,
      subfeature: match.subfeature,
      matchedPattern: match.matchedPattern,
      reason: 'Severed ${match.subfeature.name} CDN delivery cluster to decouple dopamine loop',
      estimatedSecondsSaved: SurgicalInterceptionEvent.defaultSecondsSaved(match.subfeature),
      estimatedBytesBlocked: 2621440, // 2.5 MB chunk
      hazardLevel: SurgicalInterceptionEvent.calculateHazardLevel(match.subfeature),
    );
  }

  SurgicalSubfeature _targetIdToSubfeature(String targetId) {
    final lower = targetId.toLowerCase();
    if (lower.contains('reel') || lower.contains('short') || lower.contains('clip') || lower.contains('fyp')) {
      return SurgicalSubfeature.reelsOrShorts;
    }
    if (lower.contains('explore') || lower.contains('discover')) {
      return SurgicalSubfeature.explore;
    }
    if (lower.contains('story') || lower.contains('stories')) {
      return SurgicalSubfeature.stories;
    }
    if (lower.contains('comment')) {
      return SurgicalSubfeature.comments;
    }
    if (lower.contains('chat') || lower.contains('direct') || lower.contains('dm') || lower.contains('message')) {
      return SurgicalSubfeature.directMessages;
    }
    if (lower.contains('search')) {
      return SurgicalSubfeature.search;
    }
    return SurgicalSubfeature.feed;
  }
}
