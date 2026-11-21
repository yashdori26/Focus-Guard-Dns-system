import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:focus_dns/engine/surgical/catalog/surgical_platform_catalog.dart';
import 'package:focus_dns/engine/surgical/catalog/surgical_platform_presets.dart';
import 'package:focus_dns/engine/surgical/catalog/surgical_subfeature_types.dart';
import 'package:focus_dns/engine/surgical/core/surgical_policy_evaluator.dart';
import 'package:focus_dns/frontend/screens/surgical/surgical_presets_screen.dart';

void main() {
  group('Surgical Platform Presets Tests', () {
    test('All 5 predefined presets are defined with valid metadata', () {
      final presets = SurgicalPlatformPresets.allPresets;
      expect(presets.length, equals(5));

      for (final preset in presets) {
        expect(preset.title.isNotEmpty, isTrue);
        expect(preset.subtitle.isNotEmpty, isTrue);
        expect(preset.description.isNotEmpty, isTrue);
        expect(preset.dopamineProtectionRating, inInclusiveRange(70, 100));
        expect(preset.subfeatureOverrides.isNotEmpty, isTrue);
      }
    });

    test('Ultra Strict Decoupled blocks all addiction traps while keeping DMs intact', () {
      final ultra = SurgicalPlatformPresets.ultraStrict;
      final ig = SurgicalPlatformCatalog.instagram;

      final updated = ultra.applyToRule(ig);
      expect(updated.isSubfeatureBlocked(SurgicalSubfeature.reelsOrShorts), isTrue);
      expect(updated.isSubfeatureBlocked(SurgicalSubfeature.feed), isTrue);
      expect(updated.isSubfeatureBlocked(SurgicalSubfeature.explore), isTrue);
      expect(updated.isSubfeatureBlocked(SurgicalSubfeature.stories), isTrue);
      expect(updated.isSubfeatureBlocked(SurgicalSubfeature.comments), isTrue);

      // Direct Messages remain allowed
      expect(updated.isSubfeatureBlocked(SurgicalSubfeature.directMessages), isFalse);
    });

    test('Pure Communication Only allows ONLY directMessages and severs everything else', () {
      final pureMessenger = SurgicalPlatformPresets.pureCommunicationOnly;
      final yt = SurgicalPlatformCatalog.youtube;

      final updated = pureMessenger.applyToRule(yt);
      expect(updated.isSubfeatureBlocked(SurgicalSubfeature.reelsOrShorts), isTrue);
      expect(updated.isSubfeatureBlocked(SurgicalSubfeature.feed), isTrue);
      expect(updated.isSubfeatureBlocked(SurgicalSubfeature.search), isTrue);
      expect(updated.isSubfeatureBlocked(SurgicalSubfeature.directMessages), isFalse);
    });

    test('Balanced Professional leaves DMs and Search accessible for LinkedIn & Discord', () {
      final professional = SurgicalPlatformPresets.balancedProfessional;
      final linkedin = SurgicalPlatformCatalog.linkedin;

      final updated = professional.applyToRule(linkedin);
      expect(updated.isSubfeatureBlocked(SurgicalSubfeature.reelsOrShorts), isTrue);
      expect(updated.isSubfeatureBlocked(SurgicalSubfeature.feed), isTrue);
      expect(updated.isSubfeatureBlocked(SurgicalSubfeature.search), isFalse);
      expect(updated.isSubfeatureBlocked(SurgicalSubfeature.directMessages), isFalse);
    });

    test('applyPresetToAll applies preset across all platform rules consistently', () {
      final rules = SurgicalPlatformCatalog.allPlatforms;
      final updatedRules = SurgicalPlatformPresets.applyPresetToAll(
        SurgicalPlatformPresets.ultraStrict,
        rules,
      );

      expect(updatedRules.length, equals(rules.length));
      for (final r in updatedRules) {
        expect(r.isSubfeatureBlocked(SurgicalSubfeature.reelsOrShorts), isTrue);
        expect(r.isSubfeatureBlocked(SurgicalSubfeature.directMessages), isFalse);
      }
    });

    testWidgets('SurgicalPresetsScreen renders cards and applies preset to evaluator', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final evaluator = SurgicalPolicyEvaluator();

      await tester.pumpWidget(
        MaterialApp(
          home: SurgicalPresetsScreen(
            evaluator: evaluator,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Surgical Decoupling Presets'), findsOneWidget);
      expect(find.text('Ultra Strict Decoupled'), findsOneWidget);
      expect(find.text('Pure Communication Only'), findsOneWidget);
      expect(find.text('Student & Scholar'), findsOneWidget);
      expect(find.text('Balanced Professional'), findsOneWidget);
      expect(find.text('Mindful Friction Heavy'), findsOneWidget);

      // Tap on Student & Scholar preset
      await tester.tap(find.text('Student & Scholar'));
      await tester.pumpAndSettle();

      // Tap apply button
      final applyBtn = find.text('Apply "Student & Scholar" to All Platforms');
      await tester.ensureVisible(applyBtn);
      await tester.tap(applyBtn);
      await tester.pumpAndSettle();

      // Tap confirm button in dialog
      final confirmBtn = find.text('Apply Preset');
      expect(confirmBtn, findsOneWidget);
      await tester.tap(confirmBtn);
      await tester.pumpAndSettle();

      // Verify evaluator has updated toggles for Student & Scholar
      expect(evaluator.isSubfeatureBlocked('youtube', SurgicalSubfeature.reelsOrShorts), isTrue);
      expect(evaluator.isSubfeatureBlocked('youtube', SurgicalSubfeature.search), isFalse);
    });
  });
}
