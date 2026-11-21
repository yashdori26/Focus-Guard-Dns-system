import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:focus_dns/engine/surgical/catalog/surgical_subfeature_types.dart';
import 'package:focus_dns/engine/surgical/core/surgical_policy_evaluator.dart';
import 'package:focus_dns/engine/surgical/models/surgical_rule_model.dart';
import 'package:focus_dns/engine/surgical/telemetry/surgical_telemetry_recorder.dart';
import 'package:focus_dns/frontend/screens/surgical/custom_surgical_rule_builder_screen.dart';
import 'package:focus_dns/frontend/screens/surgical/mindful_interstitial_customizer_screen.dart';
import 'package:focus_dns/frontend/screens/surgical/platform_surgical_detail_screen.dart';
import 'package:focus_dns/frontend/screens/surgical/surgical_live_interception_screen.dart';
import 'package:focus_dns/frontend/screens/surgical/surgical_studio_master_screen.dart';
import 'package:focus_dns/frontend/widgets/surgical/platform_surgical_card.dart';
import 'package:focus_dns/frontend/widgets/surgical/subfeature_toggle_matrix.dart';
import 'package:focus_dns/frontend/widgets/surgical/surgical_dissection_diagram.dart';
import 'package:focus_dns/frontend/widgets/surgical/surgical_interception_radar.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  Widget wrapWithMaterial(Widget widget) {
    return MaterialApp(
      home: Scaffold(body: widget),
    );
  }

  group('1. Surgical Custom Canvas Painters & Widgets Tests', () {
    testWidgets('SurgicalDissectionDiagram renders without error', (tester) async {
      await tester.pumpWidget(
        wrapWithMaterial(
          const SurgicalDissectionDiagram(
            blockedReelsCount: 42,
            allowedChatsCount: 128,
            isAnimated: false,
          ),
        ),
      );

      expect(find.byType(SurgicalDissectionDiagram), findsOneWidget);
      expect(find.byType(CustomPaint), findsWidgets);
    });

    testWidgets('SurgicalInterceptionRadar renders all 8 axes', (tester) async {
      final counts = {
        SurgicalSubfeature.reelsOrShorts: 50,
        SurgicalSubfeature.feed: 25,
        SurgicalSubfeature.explore: 30,
        SurgicalSubfeature.stories: 10,
        SurgicalSubfeature.comments: 5,
        SurgicalSubfeature.directMessages: 0,
        SurgicalSubfeature.search: 2,
        SurgicalSubfeature.creatorStudio: 1,
      };

      await tester.pumpWidget(
        wrapWithMaterial(
          SurgicalInterceptionRadar(subfeatureCounts: counts, size: 200),
        ),
      );

      expect(find.byType(SurgicalInterceptionRadar), findsOneWidget);
      expect(find.byType(CustomPaint), findsWidgets);
    });

    testWidgets('SubfeatureToggleMatrix renders all 8 subfeatures and responds to toggles', (tester) async {
      SurgicalSubfeature? toggledSubfeature;
      bool? toggledValue;

      await tester.pumpWidget(
        wrapWithMaterial(
          SingleChildScrollView(
            child: SubfeatureToggleMatrix(
              toggles: const {
                SurgicalSubfeature.reelsOrShorts: true,
                SurgicalSubfeature.directMessages: false,
              },
              onToggleChanged: (sub, val) {
                toggledSubfeature = sub;
                toggledValue = val;
              },
            ),
          ),
        ),
      );

      expect(find.text('SUB-FEATURE DISSECTION'), findsOneWidget);
      expect(find.text('Reels & Shorts Autoplay'), findsOneWidget);
      expect(find.text('Direct Messages (DMs)'), findsOneWidget);

      // Find the first switch and toggle it
      final firstSwitch = find.byType(Switch).first;
      await tester.tap(firstSwitch);
      await tester.pump();

      expect(toggledSubfeature, isNotNull);
      expect(toggledValue, isNotNull);
    });

    testWidgets('PlatformSurgicalCard displays glyph, status badge and triggers callback', (tester) async {
      bool wasTapped = false;
      const testRule = SurgicalRuleModel(
        platformId: 'instagram',
        displayName: 'Instagram',
        iconGlyph: '📸',
        packageNames: ['com.instagram.android'],
        subfeatureToggles: {
          SurgicalSubfeature.reelsOrShorts: true,
          SurgicalSubfeature.directMessages: false,
        },
        subfeatureDomains: {},
        chatWhitelistDomains: ['edge-chat.instagram.com'],
        searchWhitelistDomains: [],
      );

      await tester.pumpWidget(
        wrapWithMaterial(
          PlatformSurgicalCard(
            rule: testRule,
            blockedCount: 35,
            onTap: () {
              wasTapped = true;
            },
          ),
        ),
      );

      expect(find.text('Instagram'), findsOneWidget);
      expect(find.text('📸'), findsOneWidget);
      expect(find.text('DECOUPLED'), findsOneWidget);
      expect(find.text('Reels Severed'), findsOneWidget);
      expect(find.text('DMs Intact'), findsOneWidget);
      expect(find.text('35 addiction loops severed today'), findsOneWidget);

      await tester.tap(find.byType(PlatformSurgicalCard));
      expect(wasTapped, isTrue);
    });
  });

  group('2. Surgical Flutter Studio Screens Tests', () {
    testWidgets('SurgicalStudioMasterScreen renders master dashboard elements', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final evaluator = SurgicalPolicyEvaluator();
      final recorder = SurgicalTelemetryRecorder();
      recorder.populateSyntheticTestData(count: 5);

      await tester.pumpWidget(
        MaterialApp(
          home: SurgicalStudioMasterScreen(
            evaluator: evaluator,
            telemetryRecorder: recorder,
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('Surgical Decoupling Studio'), findsOneWidget);
      expect(find.byType(SurgicalDissectionDiagram), findsOneWidget);
      expect(find.text('Reels Blocked'), findsOneWidget);
      expect(find.text('DMs Flowing'), findsOneWidget);
      expect(find.text('Surgical Engine Active'), findsOneWidget);
      expect(find.byType(PlatformSurgicalCard), findsWidgets);
      expect(find.text('Add Custom Platform Rule'), findsOneWidget);

      recorder.dispose();
    });

    testWidgets('PlatformSurgicalDetailScreen renders detail configurator', (tester) async {
      final evaluator = SurgicalPolicyEvaluator();

      await tester.pumpWidget(
        MaterialApp(
          home: PlatformSurgicalDetailScreen(
            platformId: 'instagram',
            evaluator: evaluator,
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('Instagram Surgical Settings'), findsOneWidget);
      expect(find.byType(SurgicalInterceptionRadar), findsOneWidget);
      expect(find.byType(SubfeatureToggleMatrix), findsOneWidget);
      expect(find.text('MINDFUL INTERSTITIAL NUDGE'), findsOneWidget);
      expect(find.text('VIEW HIERARCHY SENTINELS'), findsOneWidget);
      expect(find.text('NETWORK & CHAT GATEWAYS'), findsOneWidget);
    });

    testWidgets('CustomSurgicalRuleBuilderScreen validates and tests sandbox pattern', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final evaluator = SurgicalPolicyEvaluator();

      await tester.pumpWidget(
        MaterialApp(
          home: CustomSurgicalRuleBuilderScreen(
            evaluator: evaluator,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('New Custom Surgical Rule'), findsOneWidget);
      expect(find.text('PLATFORM IDENTITY'), findsOneWidget);
      expect(find.text('SUB-FEATURE CLASSIFICATION'), findsOneWidget);
      expect(find.text('NETWORK SINKHOLE & WHITELISTS'), findsOneWidget);
      expect(find.text('INTERACTIVE RULE SANDBOX TESTER'), findsOneWidget);

      final inputField = find.widgetWithText(TextField, 'Enter test domain or URL...');
      await tester.ensureVisible(inputField);
      await tester.enterText(inputField, 'reels.custom.com');

      final testBtn = find.text('Test');
      await tester.ensureVisible(testBtn);
      await tester.tap(testBtn);
      await tester.pump();

      expect(find.textContaining('PASS-THROUGH'), findsOneWidget);
    });

    testWidgets('SurgicalLiveInterceptionScreen renders stream controls and filter chips', (tester) async {
      final recorder = SurgicalTelemetryRecorder();
      recorder.populateSyntheticTestData(count: 6);

      await tester.pumpWidget(
        MaterialApp(
          home: SurgicalLiveInterceptionScreen(
            recorder: recorder,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Live Interception Stream'), findsOneWidget);
      expect(find.text('All'), findsOneWidget);
      expect(find.text('Reels'), findsOneWidget);
      expect(find.text('Feed'), findsOneWidget);
      expect(find.text('Explore'), findsOneWidget);

      recorder.dispose();
    });

    testWidgets('MindfulInterstitialCustomizerScreen renders sliders, themes, and preview button', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(
        const MaterialApp(
          home: MindfulInterstitialCustomizerScreen(),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Mindful Nudge Settings'), findsOneWidget);
      expect(find.text('PAUSE COUNTDOWN DURATION'), findsOneWidget);
      expect(find.text('REFLECTION VISUAL THEME'), findsOneWidget);
      expect(find.text('COGNITIVE FRICTION PLEDGE'), findsOneWidget);
      expect(find.text('DAILY BYPASS QUOTA'), findsOneWidget);

      final previewBtn = find.text('Test & Preview Mindful Nudge Dialog');
      await tester.ensureVisible(previewBtn);
      await tester.tap(previewBtn);
      await tester.pumpAndSettle();

      expect(find.text('Pause for Focus'), findsOneWidget);
      expect(find.text('Protect My Focus & Return'), findsOneWidget);
    });
  });
}
