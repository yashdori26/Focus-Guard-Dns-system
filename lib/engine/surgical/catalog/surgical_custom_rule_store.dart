import 'dart:convert';
import 'package:flutter/foundation.dart';
import '../models/surgical_rule_model.dart';
import 'surgical_platform_catalog.dart';
import 'surgical_subfeature_types.dart';

/// In-memory and persistent store for platform rule configurations and custom rules.
class SurgicalCustomRuleStore extends ChangeNotifier {
  final Map<String, SurgicalRuleModel> _rules = {};
  final List<SurgicalRuleModel> _customRules = [];

  SurgicalCustomRuleStore() {
    _loadBuiltinDefaults();
  }

  void _loadBuiltinDefaults() {
    for (final p in SurgicalPlatformCatalog.allPlatforms) {
      _rules[p.platformId] = p;
    }
  }

  List<SurgicalRuleModel> get allRules => [
        ..._rules.values,
        ..._customRules,
      ];

  List<SurgicalRuleModel> get rules => allRules;

  List<SurgicalRuleModel> get customRules => List.unmodifiable(_customRules);

  SurgicalRuleModel? getRule(String platformId) {
    return _rules[platformId] ??
        _customRules.cast<SurgicalRuleModel?>().firstWhere(
              (r) => r?.platformId == platformId,
              orElse: () => null,
            );
  }

  /// Toggles a specific sub-feature for a platform.
  void toggleSubfeature({
    required String platformId,
    required SurgicalSubfeature feature,
    required bool isBlocked,
  }) {
    final existing = getRule(platformId);
    if (existing == null) return;

    final updatedToggles = Map<SurgicalSubfeature, bool>.from(existing.subfeatureToggles);
    updatedToggles[feature] = isBlocked;

    final updated = existing.copyWith(subfeatureToggles: updatedToggles);
    if (_rules.containsKey(platformId)) {
      _rules[platformId] = updated;
    } else {
      final idx = _customRules.indexWhere((r) => r.platformId == platformId);
      if (idx >= 0) _customRules[idx] = updated;
    }

    notifyListeners();
  }

  /// Adds a custom user-defined surgical platform rule.
  void addCustomRule(SurgicalRuleModel rule) {
    _customRules.removeWhere((r) => r.platformId == rule.platformId);
    _customRules.add(rule);
    notifyListeners();
  }

  /// Removes a custom rule.
  void removeCustomRule(String platformId) {
    _customRules.removeWhere((r) => r.platformId == platformId);
    notifyListeners();
  }

  /// Resets all platforms to default factory settings.
  void resetToDefaults() {
    _rules.clear();
    _customRules.clear();
    _loadBuiltinDefaults();
    notifyListeners();
  }

  /// Serializes active rules state for persistence.
  String exportStateToJson() {
    final list = allRules.map((r) => r.toJson()).toList();
    return jsonEncode(list);
  }

  /// Restores state from exported JSON.
  void importStateFromJson(String jsonString) {
    try {
      final List<dynamic> list = jsonDecode(jsonString) as List<dynamic>;
      for (final item in list) {
        final rule = SurgicalRuleModel.fromJson(item as Map<String, dynamic>);
        if (_rules.containsKey(rule.platformId)) {
          _rules[rule.platformId] = rule;
        } else {
          _customRules.add(rule);
        }
      }
      notifyListeners();
    } catch (_) {}
  }
}
