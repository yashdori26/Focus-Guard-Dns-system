import 'package:flutter_test/flutter_test.dart';
import 'package:focus_dns/engine/surgical/catalog/surgical_subfeature_types.dart';
import 'package:focus_dns/engine/surgical/core/accessibility_view_inspector.dart';
import 'package:focus_dns/engine/surgical/core/surgical_policy_evaluator.dart';
import 'package:focus_dns/engine/surgical/models/view_node_target.dart';

void main() {
  group('Accessibility View Inspector Tests', () {
    late SurgicalPolicyEvaluator evaluator;
    late AccessibilityViewInspector inspector;

    setUp(() {
      evaluator = SurgicalPolicyEvaluator();
      inspector = AccessibilityViewInspector(
        policyEvaluator: evaluator,
        debounceWindow: const Duration(milliseconds: 300),
      );
    });

    tearDown(() {
      inspector.dispose();
    });

    test('Inspects matching view node and returns valid ViewInspectionMatch', () {
      final match = inspector.inspectNode(
        packageName: 'com.instagram.android',
        resourceId: 'com.instagram.android:id/clips_viewer',
      );

      expect(match, isNotNull);
      expect(match!.packageName, equals('com.instagram.android'));
      expect(match.decision.isBlocked, isTrue);
      expect(match.wasDebounced, isFalse);
      expect(inspector.totalViewsMatched, equals(1));
      expect(inspector.totalViewsInspected, equals(1));
    });

    test('Non-matching view returns null', () {
      final match = inspector.inspectNode(
        packageName: 'com.instagram.android',
        resourceId: 'com.instagram.android:id/direct_message_inbox',
      );

      expect(match, isNull);
      expect(inspector.totalViewsMatched, equals(0));
      expect(inspector.totalViewsInspected, equals(1));
    });

    test('Anti-flutter debouncing drops rapid duplicate view events', () async {
      // First event -> passes
      final match1 = inspector.inspectNode(
        packageName: 'com.instagram.android',
        resourceId: 'com.instagram.android:id/clips_viewer',
      );
      expect(match1, isNotNull);
      expect(match1!.wasDebounced, isFalse);

      // Immediate duplicate event -> debounced
      final match2 = inspector.inspectNode(
        packageName: 'com.instagram.android',
        resourceId: 'com.instagram.android:id/clips_viewer',
      );
      expect(match2, isNotNull);
      expect(match2!.wasDebounced, isTrue);
      expect(inspector.totalViewsDebounced, equals(1));

      // Wait for debounce window (350ms > 300ms)
      await Future.delayed(const Duration(milliseconds: 350));

      // Third event after window -> passes
      final match3 = inspector.inspectNode(
        packageName: 'com.instagram.android',
        resourceId: 'com.instagram.android:id/clips_viewer',
      );
      expect(match3, isNotNull);
      expect(match3!.wasDebounced, isFalse);
    });

    test('Maintains rolling breadcrumb traversal history', () {
      inspector.inspectNode(
        packageName: 'com.instagram.android',
        resourceId: 'com.instagram.android:id/clips_viewer',
      );
      inspector.inspectNode(
        packageName: 'com.google.android.youtube',
        resourceId: 'com.google.android.youtube:id/reel_recycler',
      );

      expect(inspector.recentBreadcrumbs.length, equals(2));
      expect(inspector.recentBreadcrumbs.first, contains('clips_viewer'));
      expect(inspector.recentBreadcrumbs.last, contains('reel_recycler'));

      inspector.clearBreadcrumbs();
      expect(inspector.recentBreadcrumbs.isEmpty, isTrue);
    });

    test('Stream controller emits matched view events', () async {
      final List<ViewInspectionMatch> streamedMatches = [];
      final sub = inspector.matchStream.listen((m) {
        streamedMatches.add(m);
      });

      inspector.inspectNode(
        packageName: 'com.google.android.youtube',
        resourceId: 'com.google.android.youtube:id/reel_recycler',
      );

      await Future.delayed(const Duration(milliseconds: 50));
      expect(streamedMatches.length, equals(1));
      expect(streamedMatches.first.packageName, equals('com.google.android.youtube'));

      await sub.cancel();
    });

    test('Reset debounce clears cached signature', () {
      inspector.inspectNode(
        packageName: 'com.instagram.android',
        resourceId: 'com.instagram.android:id/clips_viewer',
      );

      inspector.resetDebounce();

      // Immediate subsequent call should now NOT be debounced because cache was cleared
      final match = inspector.inspectNode(
        packageName: 'com.instagram.android',
        resourceId: 'com.instagram.android:id/clips_viewer',
      );
      expect(match!.wasDebounced, isFalse);
    });
  });
}
