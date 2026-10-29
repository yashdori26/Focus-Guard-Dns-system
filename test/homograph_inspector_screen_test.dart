import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:focus_dns/models/ai_threat_models.dart';
import 'package:focus_dns/screens/homograph_inspector_screen.dart';
import 'package:focus_dns/services/ai_threat_service.dart';

class FakeHomographService extends AiThreatService {
  FakeHomographService() : super(client: MockClient((_) async => throw UnimplementedError()));

  @override
  Future<HomographAnalysis> checkHomograph(String domain) async {
    if (domain.contains('\u0430') || domain.contains('а')) {
      return HomographAnalysis(
        originalDomain: domain,
        unicodeDomain: 'аpple.com',
        skeleton: 'apple.com',
        isThreat: true,
        attackType: 'MIXED_SCRIPT',
        spoofedBrand: 'Apple',
        riskScore: 94.5,
        explanation: 'Mixed Latin-Cyrillic script homograph targeting Apple.',
        confusables: [
          HomographCharacter(
            character: 'а',
            codepoint: 'U+0430',
            confusableWith: 'a',
            script: 'CYRILLIC',
          ),
        ],
      );
    }

    return HomographAnalysis(
      originalDomain: domain,
      unicodeDomain: domain,
      skeleton: domain,
      isThreat: false,
      attackType: 'NONE',
      spoofedBrand: null,
      riskScore: 0.0,
      explanation: 'No confusable characters or typosquatting patterns detected.',
      confusables: [],
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Widget buildTestableWidget(AiThreatService service) {
    return MaterialApp(
      theme: ThemeData.dark(),
      home: HomographInspectorScreen(threatService: service),
    );
  }

  group('HomographInspectorScreen Widget Tests', () {
    testWidgets('Renders header, input field, and default analysis', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final service = FakeHomographService();
      await tester.pumpWidget(buildTestableWidget(service));
      await tester.pump();
      await tester.pump();

      // Verify title & search button
      expect(find.text('TR39 Homograph Inspector'), findsOneWidget);
      expect(find.text('Analyze'), findsOneWidget);

      // Verify initial threat analysis output
      expect(find.text('SPOOFING THREAT DETECTED'), findsOneWidget);
      expect(find.text('Visual Skeleton:'), findsOneWidget);
      expect(find.text('apple.com'), findsOneWidget);
      expect(find.text('Targeted Brand:'), findsOneWidget);
      expect(find.text('APPLE'), findsOneWidget);

      // Verify confusable breakdown
      expect(find.text('Confusable Character Breakdown:'), findsOneWidget);
      expect(find.text('(U+0430) in CYRILLIC'), findsOneWidget);
      expect(find.text('mimics Latin '), findsOneWidget);
    });

    testWidgets('Tapping clean sample chip triggers clean analysis', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final service = FakeHomographService();
      await tester.pumpWidget(buildTestableWidget(service));
      await tester.pump();
      await tester.pump();

      // Find and tap the 'microsoft.com' ActionChip
      final chipFinder = find.widgetWithText(ActionChip, 'microsoft.com');
      expect(chipFinder, findsOneWidget);
      await tester.tap(chipFinder);
      await tester.pump();
      await tester.pump();

      // Verify clean domain output
      expect(find.text('CLEAN DOMAIN'), findsOneWidget);
      expect(find.text('No confusable characters or typosquatting patterns detected.'), findsOneWidget);
    });
  });
}
