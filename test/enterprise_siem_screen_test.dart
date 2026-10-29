import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:focus_dns/screens/enterprise_siem_screen.dart';
import 'package:focus_dns/services/enterprise_service.dart';

void main() {
  testWidgets('EnterpriseSiemScreen renders configuration fields and triggers test probe', (tester) async {
    final service = EnterpriseService(mockOnly: true);

    await tester.pumpWidget(
      MaterialApp(
        home: EnterpriseSiemScreen(service: service),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    // Verify Title
    expect(find.text('Enterprise SIEM Integration (RFC 5424)'), findsOneWidget);

    // Verify TextFields (Host, Port, Index, etc.)
    expect(find.byType(TextField), findsAtLeastNWidgets(2));
    expect(find.text('10.0.0.50'), findsOneWidget);
    expect(find.text('514'), findsOneWidget);

    // Verify Test Probe Button
    final probeButton = find.text('Send Test Probe');
    expect(probeButton, findsOneWidget);

    // Tap Test Probe
    await tester.tap(probeButton);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    // Verify probe result banner
    expect(find.text('SUCCESS: RFC 5424 test probe transmitted successfully.'), findsOneWidget);
  });
}
