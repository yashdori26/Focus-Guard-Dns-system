import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:focus_dns/models/ai_threat_models.dart';
import 'package:focus_dns/screens/dga_neural_screen.dart';
import 'package:focus_dns/services/ai_threat_service.dart';

class FakeDgaNeuralService extends AiThreatService {
  FakeDgaNeuralService() : super(client: MockClient((_) async => throw UnimplementedError()));

  @override
  Future<DgaAnalysis> classifyDga(String domain) async {
    if (domain.contains('bcdfghjklmnpqrstvwxyz') || domain.contains('dga')) {
      return DgaAnalysis(
        domain: domain,
        isDga: true,
        probability: 0.985,
        confidenceScore: 98.5,
        predictedFamily: 'Conficker',
        entropy: 3.92,
        vowelRatio: 0.0,
        explanation: 'High Shannon entropy (3.92) with zero vowels. Classified as DGA C2.',
      );
    }

    return DgaAnalysis(
      domain: domain,
      isDga: false,
      probability: 0.045,
      confidenceScore: 4.5,
      predictedFamily: null,
      entropy: 2.15,
      vowelRatio: 0.42,
      explanation: 'Typical human natural language bigram distribution.',
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Widget buildTestableWidget(AiThreatService service) {
    return MaterialApp(
      theme: ThemeData.dark(),
      home: DgaNeuralScreen(threatService: service),
    );
  }

  group('DgaNeuralScreen Widget Tests', () {
    testWidgets('Renders MLP architecture visualizer, input, and default DGA classification', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final service = FakeDgaNeuralService();
      await tester.pumpWidget(buildTestableWidget(service));
      await tester.pump();
      await tester.pump();

      // Verify title & architecture card
      expect(find.text('DGA Neural Classifier'), findsOneWidget);
      expect(find.text('3-Layer MLP Neural Network (1,057 Parameters)'), findsOneWidget);

      // Verify layer flow diagram
      expect(find.text('Input'), findsOneWidget);
      expect(find.text('16 Features'), findsOneWidget);
      expect(find.text('Hidden 1'), findsOneWidget);
      expect(find.text('32 Neurons (ReLU)'), findsOneWidget);
      expect(find.text('Hidden 2'), findsOneWidget);
      expect(find.text('16 Neurons (ReLU)'), findsOneWidget);
      expect(find.text('Output'), findsOneWidget);
      expect(find.text('1 (Sigmoid)'), findsOneWidget);

      // Verify classification result output
      expect(find.text('MALWARE C2 DGA DETECTED'), findsOneWidget);
      expect(find.text('Conficker'), findsOneWidget);

      // Verify lexical feature tiles
      expect(find.text('Shannon Entropy'), findsOneWidget);
      expect(find.text('3.920 bits'), findsOneWidget);
      expect(find.text('Vowel Ratio'), findsOneWidget);
      expect(find.text('0.0%'), findsOneWidget);
      expect(find.text('Sigmoid Probability'), findsOneWidget);
      expect(find.text('0.9850'), findsOneWidget);
    });

    testWidgets('Tapping benign domain chip triggers clean human classification', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final service = FakeDgaNeuralService();
      await tester.pumpWidget(buildTestableWidget(service));
      await tester.pump();
      await tester.pump();

      // Find and tap 'google.com' or 'wikipedia.org' ActionChip
      final chipFinder = find.widgetWithText(ActionChip, 'wikipedia.org');
      expect(chipFinder, findsOneWidget);
      await tester.tap(chipFinder);
      await tester.pump();
      await tester.pump();

      // Verify benign classification output
      expect(find.text('BENIGN HUMAN DOMAIN'), findsOneWidget);
      expect(find.text('Typical human natural language bigram distribution.'), findsOneWidget);
      expect(find.text('42.0%'), findsOneWidget); // Vowel ratio
    });
  });
}
