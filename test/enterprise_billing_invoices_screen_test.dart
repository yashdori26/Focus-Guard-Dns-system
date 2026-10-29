// Test Suite: Enterprise Commercial Billing & Cryptographic Invoicing Screen

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:focus_dns/screens/enterprise_billing_invoices_screen.dart';
import 'package:focus_dns/services/enterprise_service.dart';

void main() {
  testWidgets('EnterpriseBillingInvoicesScreen renders quota meters, invoices, and verifies HMAC certificate', (tester) async {
    tester.view.physicalSize = const Size(1200, 2000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final service = EnterpriseService(mockOnly: true);

    await tester.pumpWidget(
      MaterialApp(
        home: EnterpriseBillingInvoicesScreen(
          service: service,
          orgId: 'org_springfield',
        ),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    // 1. Verify App Bar Title
    expect(find.text('Commercial Billing & Invoicing'), findsOneWidget);

    // 2. Verify Organization Header & Plan Tier
    expect(find.textContaining('ORGANIZATION: ORG_SPRINGFIELD'), findsOneWidget);
    expect(find.text('Springfield Unified District'), findsOneWidget);

    // 3. Verify Active Devices Quota Meter & Warning
    expect(find.text('Active Devices Quota Meter'), findsOneWidget);
    expect(find.textContaining('480 / 500 Devices'), findsOneWidget);
    expect(find.textContaining('Organization active devices at 96% of quota.'), findsOneWidget);

    // 4. Verify Usage KPI Cards
    expect(find.text('Monthly DNS Volume'), findsOneWidget);
    expect(find.textContaining('4.82M queries'), findsWidgets);
    expect(find.text('Peak Measured QPS'), findsOneWidget);
    expect(find.textContaining('1840.5 QPS'), findsOneWidget);
    expect(find.text('Current Accrued Cost'), findsOneWidget);
    expect(find.text('\$580.75'), findsWidgets);

    // 5. Verify Signed Invoice Section & Itemized Table
    expect(find.text('Cryptographically Signed Invoice'), findsOneWidget);
    expect(find.textContaining('inv_org_springfield_2026_10_a9f1'), findsOneWidget);
    expect(find.text('Device Licenses (Active)'), findsOneWidget);
    expect(find.text('DNS Query Volume'), findsOneWidget);
    expect(find.text('Columnar DuckDB Storage'), findsOneWidget);
    expect(find.text('SIEM Gateway Webhook Egress'), findsOneWidget);
    expect(find.text('TOTAL INVOICE CHARGES'), findsOneWidget);

    // 6. Verify Initial Verification Status Badge
    expect(find.text('PENDING VERIFICATION'), findsOneWidget);

    // 7. Verify HMAC-SHA256 Digital Certificate Box
    expect(find.text('HMAC-SHA256 Cryptographic Digital Certificate'), findsOneWidget);

    // 8. Test HMAC Certificate Verification Flow
    final verifyBtn = find.byKey(const Key('verify_hmac_certificate_button'));
    expect(verifyBtn, findsOneWidget);
    await tester.ensureVisible(verifyBtn);
    await tester.tap(verifyBtn);
    await tester.pumpAndSettle();

    // Verify badge updated to verified tamper-proof
    expect(find.text('VERIFIED TAMPER-PROOF'), findsOneWidget);
    expect(find.textContaining('HMAC-SHA256 Signature VALID'), findsOneWidget);

    // 9. Test Deliberate Tampering Detection Flow
    final tamperBtn = find.byKey(const Key('simulate_tamper_button'));
    expect(tamperBtn, findsOneWidget);
    await tester.ensureVisible(tamperBtn);
    await tester.tap(tamperBtn);
    await tester.pumpAndSettle();

    // Verify badge updated to tampering detected
    expect(find.text('TAMPERING DETECTED'), findsOneWidget);
    expect(find.textContaining('TAMPERING DETECTED: Cryptographic digest mismatch!'), findsOneWidget);

    // 10. Verify Life Safety Exemption Guarantee
    expect(find.textContaining('Inviolable Life Safety Exemption'), findsOneWidget);
    expect(find.textContaining('911.gov, 112.gov, emergency.gov'), findsOneWidget);
  });
}
