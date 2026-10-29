// Test Suite: Enterprise SOAR Incident Console & SIEM Ingestion Screen

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:focus_dns/screens/enterprise_soar_incidents_screen.dart';
import 'package:focus_dns/services/enterprise_service.dart';

void main() {
  testWidgets('EnterpriseSoarIncidentsScreen renders incident console, tabs, and quarantine lift dialog', (tester) async {
    tester.view.physicalSize = const Size(1200, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    // Use mock service so test runs hermetically without network
    final service = EnterpriseService(mockOnly: true);

    await tester.pumpWidget(
      MaterialApp(
        home: EnterpriseSoarIncidentsScreen(
          service: service,
          tenantId: 'org_springfield',
        ),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    // 1. Verify App Bar Title
    expect(find.text('SOAR Security & Incident Response'), findsOneWidget);

    // 2. Verify Tab Headers
    expect(find.textContaining('SOAR Incidents'), findsWidgets);
    expect(find.textContaining('SIEM Ingest Alerts'), findsWidgets);

    // 3. Verify Anti-Cascade Circuit Breaker Card
    expect(find.text('SOAR Anti-Cascade Circuit Breaker'), findsOneWidget);
    expect(find.textContaining('Limits automated device isolations to max 5 endpoints'), findsOneWidget);

    // 4. Verify Filter Chips
    expect(find.text('ALL'), findsOneWidget);
    expect(find.text('CONTAINED'), findsWidgets);
    expect(find.text('OPEN'), findsOneWidget);

    // 5. Verify Inviolable Life-Safety Notice
    expect(find.textContaining('Life Safety Guard'), findsOneWidget);
    expect(find.text('ACTIVE (Unconditional)'), findsOneWidget);

    // 6. Verify Incident Cards from mock service
    expect(find.textContaining('chromebook_03'), findsWidgets);
    expect(find.textContaining('login-credential-steal.xyz'), findsWidgets);
    expect(find.textContaining('Risk: 94.5'), findsOneWidget);

    // 7. Test Quarantine Lift Dialog
    final liftBtn = find.text('Lift Quarantine');
    if (liftBtn.evaluate().isNotEmpty) {
      await tester.tap(liftBtn.first);
      await tester.pumpAndSettle();

      // Verify Life Safety reassurance in dialog
      expect(find.text('Lift Device Quarantine'), findsOneWidget);
      expect(find.textContaining('Life Safety exemptions (911.gov, update.microsoft.com) remain active'), findsOneWidget);

      // Dismiss dialog
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
    }

    // 8. Test Forensic Trace Dialog
    final traceBtn = find.text('Forensic Trace');
    if (traceBtn.evaluate().isNotEmpty) {
      await tester.tap(traceBtn.first);
      await tester.pumpAndSettle();

      expect(find.textContaining('Forensic Trace:'), findsOneWidget);
      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();
    }

    // 9. Switch to Inbound SIEM Webhooks Tab
    await tester.tap(find.textContaining('SIEM Ingest Alerts').first);
    await tester.pumpAndSettle();

    // Verify SIEM Gateway Header & Vendor Badges
    expect(find.text('Bidirectional SIEM Ingestion Gateway'), findsOneWidget);
    expect(find.textContaining('Splunk CIM, Datadog Monitors, and Elastic ECS'), findsOneWidget);
    expect(find.text('SPLUNK'), findsWidgets);
    expect(find.text('DATADOG'), findsWidgets);

    // 10. Open Raw Payload Dialog
    final inspectBtn = find.text('Inspect Raw Payload');
    if (inspectBtn.evaluate().isNotEmpty) {
      await tester.tap(inspectBtn.first);
      await tester.pumpAndSettle();

      expect(find.textContaining('Normalized SIEM Ingest Payload'), findsOneWidget);
      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();
    }
  });
}
