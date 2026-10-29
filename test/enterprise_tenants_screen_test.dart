import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:focus_dns/screens/enterprise_tenants_screen.dart';
import 'package:focus_dns/services/enterprise_service.dart';

void main() {
  testWidgets('EnterpriseTenantsScreen renders organization hierarchy and enrollment dialog', (tester) async {
    final service = EnterpriseService(mockOnly: true);

    await tester.pumpWidget(
      MaterialApp(
        home: EnterpriseTenantsScreen(
          orgId: 'org_springfield',
          service: service,
        ),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    // Verify title and organization details
    expect(find.text('Multi-Tenant Organization Hierarchy'), findsOneWidget);
    expect(find.text('Springfield Unified District'), findsOneWidget);

    // Verify Tenant Units
    expect(find.text('Lincoln High School'), findsOneWidget);
    expect(find.text('Springfield Elementary'), findsOneWidget);

    // Test enrollment secret generation dialog
    final enrollButtons = find.text('Generate Enrollment Token');
    expect(enrollButtons, findsAtLeastNWidgets(1));

    await tester.tap(enrollButtons.first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('Device Enrollment Secret'), findsOneWidget);
    expect(find.text('Close'), findsOneWidget);

    // Close dialog
    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();

    expect(find.text('Device Enrollment Secret'), findsNothing);
  });
}
