import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:focus_dns/models/ai_threat_models.dart';
import 'package:focus_dns/screens/ai_threat_radar_screen.dart';
import 'package:focus_dns/services/ai_threat_service.dart';
import 'package:focus_dns/widgets/radar_scan_widget.dart';

class FakeAiThreatService extends AiThreatService {
  FakeAiThreatService() : super(client: MockClient((_) async => throw UnimplementedError()));

  @override
  Future<AiTelemetrySnapshot> fetchTelemetry() async {
    return AiTelemetrySnapshot(
      totalQueries: 12500,
      totalThreatsBlocked: 420,
      homographsBlocked: 110,
      dgaBlocked: 210,
      phishingBlocked: 100,
      exemptionsPassed: 34,
      avgLatencyUs: 18.5,
      isLocked: false,
    );
  }

  @override
  Future<List<EdgeThreatEvent>> fetchRecentRouterThreats() async {
    return [
      EdgeThreatEvent(
        timestamp: 1730000000,
        clientIp: '192.168.1.140',
        clientMac: 'AA:BB:CC:11:22:33',
        deviceName: 'Smart TV',
        domain: 'bcdfghjklmnpqrstvwxyz.org',
        threatType: 'DGA_MALWARE',
        riskScore: 95.0,
        action: 'BLOCK',
        reason: 'High entropy malware C2',
      ),
    ];
  }

  @override
  Future<AiThreatVerdict> huntDomain(String domain) async {
    return AiThreatVerdict(
      domain: domain,
      isThreat: true,
      action: 'BLOCK',
      riskScore: 95.0,
      reason: 'Cyrillic homograph impersonating Apple',
      threatType: 'HOMOGRAPH_TYPOSQUAT',
      detectedBrand: 'Apple',
      category: 'PHISHING',
      latencyUs: 14.2,
      cached: false,
    );
  }

  @override
  Future<Map<String, dynamic>> requestWhitelist(String domain) async {
    return {'status': 'whitelisted', 'domain': domain};
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Widget buildTestableWidget(AiThreatService service) {
    return MaterialApp(
      theme: ThemeData.dark(),
      home: AiThreatRadarScreen(threatService: service),
    );
  }

  group('AiThreatRadarScreen Widget Tests', () {
    testWidgets('Renders radar dashboard, telemetry metrics, and radar animation', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final service = FakeAiThreatService();
      await tester.pumpWidget(buildTestableWidget(service));
      await tester.pump();
      await tester.pump();
      await tester.pump();

      // Verify title & banner
      expect(find.text('AI Threat Radar'), findsOneWidget);
      expect(find.text('REAL-TIME AI HUNTING ACTIVE'), findsOneWidget);
      expect(find.text('Zero-Day Threat Shield'), findsOneWidget);

      // Verify RadarScanWidget is present
      expect(find.byType(RadarScanWidget), findsOneWidget);

      // Verify metric labels
      expect(find.text('Threats Neutralized'), findsOneWidget);
      expect(find.text('Inference Latency'), findsOneWidget);
      expect(find.text('Total Analyzed'), findsOneWidget);
      expect(find.text('Focus Lockdown'), findsOneWidget);

      // Verify Deep Scan Navigation buttons
      expect(find.text('TR39 Homographs'), findsOneWidget);
      expect(find.text('DGA Neural MLP'), findsOneWidget);

      // Verify Edge Router Live Threat Feed
      expect(find.text('LAN Edge Threat Feed'), findsOneWidget);
      expect(find.textContaining('Smart TV'), findsOneWidget);
    });

    testWidgets('Domain Hunt interactive input triggers threat scan', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final service = FakeAiThreatService();
      await tester.pumpWidget(buildTestableWidget(service));
      await tester.pump();
      await tester.pump();
      await tester.pump();

      // Find the domain hunt text field
      final inputFinder = find.byType(TextField);
      expect(inputFinder, findsOneWidget);

      // Enter a test threat domain
      await tester.enterText(inputFinder, 'аpple.com');
      await tester.pump();

      // Find and tap the 'Hunt' button
      final huntBtn = find.text('Hunt');
      expect(huntBtn, findsOneWidget);
      await tester.tap(huntBtn);
      await tester.pump();
      await tester.pump();
      await tester.pump();

      // Verify verdict result card appears
      expect(find.text('аpple.com'), findsAtLeastNWidgets(1));
      expect(find.text('BLOCK'), findsAtLeastNWidgets(1));
      expect(find.text('Reason: Cyrillic homograph impersonating Apple'), findsOneWidget);
    });

    testWidgets('Whitelisting action invokes service and shows snackbar', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final service = FakeAiThreatService();
      await tester.pumpWidget(buildTestableWidget(service));
      await tester.pump();
      await tester.pump();
      await tester.pump();

      // Enter domain and scan
      await tester.enterText(find.byType(TextField), 'test-domain.com');
      await tester.tap(find.text('Hunt'));
      await tester.pump();
      await tester.pump();
      await tester.pump();

      // Tap Whitelist button
      final whitelistBtn = find.text('Add to Whitelist');
      expect(whitelistBtn, findsOneWidget);
      await tester.tap(whitelistBtn);
      await tester.pump();
      await tester.pump();

      // Verify SnackBar feedback
      expect(find.byType(SnackBar), findsOneWidget);
    });
  });
}
