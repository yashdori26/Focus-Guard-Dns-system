import 'dart:async';
import 'package:flutter/foundation.dart';
import '../models/view_node_target.dart';
import '../catalog/surgical_subfeature_types.dart';
import 'surgical_policy_evaluator.dart';

/// Event representing a matched view hierarchy detection.
@immutable
class ViewInspectionMatch {
  final DateTime timestamp;
  final String packageName;
  final String? resourceId;
  final String? contentDescription;
  final String? className;
  final SurgicalPolicyDecision decision;
  final ViewInterceptionAction resolvedAction;
  final bool wasDebounced;

  const ViewInspectionMatch({
    required this.timestamp,
    required this.packageName,
    this.resourceId,
    this.contentDescription,
    this.className,
    required this.decision,
    required this.resolvedAction,
    this.wasDebounced = false,
  });

  @override
  String toString() {
    return 'ViewInspectionMatch(pkg: $packageName, res: $resourceId, action: ${resolvedAction.name}, debounced: $wasDebounced)';
  }
}

/// Evaluator and anti-flutter controller for native Android Accessibility events.
/// Inspects incoming ViewNode signatures against compiled platform targets.
class AccessibilityViewInspector {
  final SurgicalPolicyEvaluator _policyEvaluator;
  final Duration debounceWindow;

  final StreamController<ViewInspectionMatch> _matchStreamController =
      StreamController<ViewInspectionMatch>.broadcast();

  String? _lastMatchedSignature;
  DateTime? _lastMatchedTimestamp;

  final List<String> _recentViewBreadcrumbs = [];
  static const int _maxBreadcrumbs = 20;

  int _totalViewsInspected = 0;
  int _totalViewsMatched = 0;
  int _totalViewsDebounced = 0;

  AccessibilityViewInspector({
    required SurgicalPolicyEvaluator policyEvaluator,
    this.debounceWindow = const Duration(milliseconds: 1200),
  }) : _policyEvaluator = policyEvaluator;

  /// Broadcast stream of matched view events.
  Stream<ViewInspectionMatch> get matchStream => _matchStreamController.stream;

  /// Total count of accessibility events evaluated.
  int get totalViewsInspected => _totalViewsInspected;

  /// Total count of sub-feature views successfully intercepted.
  int get totalViewsMatched => _totalViewsMatched;

  /// Total count of duplicate view events dropped by the anti-flutter debounce filter.
  int get totalViewsDebounced => _totalViewsDebounced;

  /// Recent view hierarchy traversal history.
  List<String> get recentBreadcrumbs => List.unmodifiable(_recentViewBreadcrumbs);

  /// Evaluates an incoming accessibility node event from the native layer.
  ViewInspectionMatch? inspectNode({
    required String packageName,
    String? resourceId,
    String? contentDescription,
    String? text,
    String? className,
  }) {
    _totalViewsInspected++;

    final decision = _policyEvaluator.evaluateAccessibilityView(
      packageName: packageName,
      resourceId: resourceId,
      contentDescription: contentDescription,
      text: text,
      className: className,
    );

    if (!decision.isBlocked) {
      return null;
    }

    final signature = '${packageName}_${resourceId ?? ""}_${contentDescription ?? ""}';
    final now = DateTime.now();

    // Check anti-flutter debounce
    if (_lastMatchedSignature == signature &&
        _lastMatchedTimestamp != null &&
        now.difference(_lastMatchedTimestamp!) < debounceWindow) {
      _totalViewsDebounced++;
      return ViewInspectionMatch(
        timestamp: now,
        packageName: packageName,
        resourceId: resourceId,
        contentDescription: contentDescription,
        className: className,
        decision: decision,
        resolvedAction: decision.action,
        wasDebounced: true,
      );
    }

    _lastMatchedSignature = signature;
    _lastMatchedTimestamp = now;
    _totalViewsMatched++;

    _recordBreadcrumb('$packageName:${resourceId ?? contentDescription ?? "view"}');

    final match = ViewInspectionMatch(
      timestamp: now,
      packageName: packageName,
      resourceId: resourceId,
      contentDescription: contentDescription,
      className: className,
      decision: decision,
      resolvedAction: decision.action,
      wasDebounced: false,
    );

    _matchStreamController.add(match);
    return match;
  }

  /// Clears anti-flutter debounce cache.
  void resetDebounce() {
    _lastMatchedSignature = null;
    _lastMatchedTimestamp = null;
  }

  /// Clears breadcrumb history.
  void clearBreadcrumbs() {
    _recentViewBreadcrumbs.clear();
  }

  /// Disposes stream controllers.
  void dispose() {
    _matchStreamController.close();
  }

  void _recordBreadcrumb(String tag) {
    if (_recentViewBreadcrumbs.length >= _maxBreadcrumbs) {
      _recentViewBreadcrumbs.removeAt(0);
    }
    _recentViewBreadcrumbs.add('${DateTime.now().toIso8601String().substring(11, 19)} $tag');
  }
}
