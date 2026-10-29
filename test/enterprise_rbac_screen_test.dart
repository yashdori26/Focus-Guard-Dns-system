import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:focus_dns/screens/enterprise_rbac_screen.dart';
import 'package:focus_dns/services/enterprise_service.dart';

void main() {
  testWidgets('EnterpriseRbacScreen renders user directory and cryptographic audit ledger', (tester) async {
    final service = EnterpriseService(mockOnly: true);

    await tester.pumpWidget(
      MaterialApp(
        home: EnterpriseRbacScreen(service: service),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    // Verify Title
    expect(find.text('RBAC & Cryptographic Audit Ledger'), findsOneWidget);

    // Verify Users Directory
    expect(find.text('superadmin'), findsOneWidget);
    expect(find.text('district_superintendent'), findsOneWidget);
    expect(find.text('auditor_maria'), findsOneWidget);

    // Verify Audit Trail Entries
    expect(find.text('LOCK_SESSION'), findsAtLeastNWidgets(1));

    // Verify Refresh button
    expect(find.byIcon(Icons.refresh), findsOneWidget);
  });
}
