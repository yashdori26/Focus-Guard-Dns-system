import 'package:flutter/foundation.dart';
import '../catalog/surgical_subfeature_types.dart';
import 'view_node_target.dart';

/// Complete surgical policy definition for a platform.
@immutable
class SurgicalRuleModel {
  final String platformId;
  final String displayName;
  final String iconGlyph;
  final List<String> packageNames;
  final Map<SurgicalSubfeature, bool> subfeatureToggles;
  final Map<SurgicalSubfeature, List<String>> subfeatureDomains;
  final Map<SurgicalSubfeature, List<String>> subfeatureUrlPaths;
  final List<String> chatWhitelistDomains;
  final List<String> searchWhitelistDomains;
  final List<ViewNodeTarget> viewNodeTargets;
  final bool enableMindfulInterstitial;
  final int mindfulPauseSeconds;
  final String motivationalPrompt;

  const SurgicalRuleModel({
    required this.platformId,
    required this.displayName,
    required this.iconGlyph,
    required this.packageNames,
    required this.subfeatureToggles,
    required this.subfeatureDomains,
    this.subfeatureUrlPaths = const {},
    required this.chatWhitelistDomains,
    required this.searchWhitelistDomains,
    this.viewNodeTargets = const [],
    this.enableMindfulInterstitial = true,
    this.mindfulPauseSeconds = 10,
    this.motivationalPrompt = 'You opened this app for communication. Protect your focus.',
  });

  bool isSubfeatureBlocked(SurgicalSubfeature feature) {
    return subfeatureToggles[feature] == true;
  }

  SurgicalRuleModel copyWith({
    Map<SurgicalSubfeature, bool>? subfeatureToggles,
    bool? enableMindfulInterstitial,
    int? mindfulPauseSeconds,
    String? motivationalPrompt,
  }) {
    return SurgicalRuleModel(
      platformId: platformId,
      displayName: displayName,
      iconGlyph: iconGlyph,
      packageNames: packageNames,
      subfeatureToggles: subfeatureToggles ?? this.subfeatureToggles,
      subfeatureDomains: subfeatureDomains,
      subfeatureUrlPaths: subfeatureUrlPaths,
      chatWhitelistDomains: chatWhitelistDomains,
      searchWhitelistDomains: searchWhitelistDomains,
      viewNodeTargets: viewNodeTargets,
      enableMindfulInterstitial: enableMindfulInterstitial ?? this.enableMindfulInterstitial,
      mindfulPauseSeconds: mindfulPauseSeconds ?? this.mindfulPauseSeconds,
      motivationalPrompt: motivationalPrompt ?? this.motivationalPrompt,
    );
  }

  Map<String, dynamic> toJson() => {
        'platformId': platformId,
        'displayName': displayName,
        'iconGlyph': iconGlyph,
        'packageNames': packageNames,
        'subfeatureToggles': subfeatureToggles.map((k, v) => MapEntry(k.name, v)),
        'subfeatureDomains': subfeatureDomains.map((k, v) => MapEntry(k.name, v)),
        'subfeatureUrlPaths': subfeatureUrlPaths.map((k, v) => MapEntry(k.name, v)),
        'chatWhitelistDomains': chatWhitelistDomains,
        'searchWhitelistDomains': searchWhitelistDomains,
        'viewNodeTargets': viewNodeTargets.map((t) => t.toJson()).toList(),
        'enableMindfulInterstitial': enableMindfulInterstitial,
        'mindfulPauseSeconds': mindfulPauseSeconds,
        'motivationalPrompt': motivationalPrompt,
      };

  factory SurgicalRuleModel.fromJson(Map<String, dynamic> json) {
    final Map<String, dynamic> rawToggles = json['subfeatureToggles'] as Map<String, dynamic>? ?? {};
    final Map<SurgicalSubfeature, bool> toggles = {};
    for (final entry in rawToggles.entries) {
      final f = SurgicalSubfeature.values.firstWhere(
        (e) => e.name == entry.key,
        orElse: () => SurgicalSubfeature.feed,
      );
      toggles[f] = entry.value as bool? ?? false;
    }

    final Map<String, dynamic> rawDomains = json['subfeatureDomains'] as Map<String, dynamic>? ?? {};
    final Map<SurgicalSubfeature, List<String>> domains = {};
    for (final entry in rawDomains.entries) {
      final f = SurgicalSubfeature.values.firstWhere(
        (e) => e.name == entry.key,
        orElse: () => SurgicalSubfeature.feed,
      );
      domains[f] = List<String>.from(entry.value as List? ?? []);
    }

    final Map<String, dynamic> rawPaths = json['subfeatureUrlPaths'] as Map<String, dynamic>? ?? {};
    final Map<SurgicalSubfeature, List<String>> paths = {};
    for (final entry in rawPaths.entries) {
      final f = SurgicalSubfeature.values.firstWhere(
        (e) => e.name == entry.key,
        orElse: () => SurgicalSubfeature.feed,
      );
      paths[f] = List<String>.from(entry.value as List? ?? []);
    }

    return SurgicalRuleModel(
      platformId: json['platformId'] as String,
      displayName: json['displayName'] as String,
      iconGlyph: json['iconGlyph'] as String? ?? '📱',
      packageNames: List<String>.from(json['packageNames'] as List? ?? []),
      subfeatureToggles: toggles,
      subfeatureDomains: domains,
      subfeatureUrlPaths: paths,
      chatWhitelistDomains: List<String>.from(json['chatWhitelistDomains'] as List? ?? []),
      searchWhitelistDomains: List<String>.from(json['searchWhitelistDomains'] as List? ?? []),
      viewNodeTargets: (json['viewNodeTargets'] as List? ?? [])
          .map((t) => ViewNodeTarget.fromJson(t as Map<String, dynamic>))
          .toList(),
      enableMindfulInterstitial: json['enableMindfulInterstitial'] as bool? ?? true,
      mindfulPauseSeconds: json['mindfulPauseSeconds'] as int? ?? 10,
      motivationalPrompt: json['motivationalPrompt'] as String? ?? '',
    );
  }
}
