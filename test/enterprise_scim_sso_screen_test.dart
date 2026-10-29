import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:focus_dns/screens/enterprise_scim_sso_screen.dart';
import 'package:focus_dns/services/enterprise_service.dart';

void main() {
  testWidgets('EnterpriseScimSsoScreen renders directory sync status, SAML/OIDC cards, and logs table', (tester) async {
    final service = EnterpriseService(mockOnly: true);

    await tester.pumpWidget(
      MaterialApp(
        home: EnterpriseScimSsoScreen(
          orgId: 'org_springfield',
          service: service,
        ),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    // Verify Title & Header Status
    expect(find.text('Directory Federation & SCIM / SSO'), findsOneWidget);
    expect(find.text('SCIM 2.0 LISTENING'), findsOneWidget);
    expect(find.textContaining('RFC 7643 / RFC 7644'), findsOneWidget);
    expect(find.text('Just-in-Time (JIT) Provisioning'), findsOneWidget);

    // Verify SAML 2.0 Card
    expect(find.text('SAML 2.0 Web Browser SSO'), findsOneWidget);
    expect(find.text('urn:focusdns:enterprise:saml2:sp'), findsOneWidget);
    expect(find.text('https://auth.focusdns.internal/saml/acs'), findsOneWidget);

    // Verify OIDC Card
    expect(find.text('OpenID Connect (OIDC) JWT'), findsOneWidget);
    expect(find.text('fdns-client-98402a7b1c3'), findsOneWidget);
    expect(find.text('RS256 / EdDSA Verified'), findsOneWidget);

    // Verify Session Revocation Law Card
    expect(find.textContaining('Instant Session Revocation Law'), findsOneWidget);

    // Verify SCIM Logs Table
    expect(find.text('SCIM 2.0 Automated Lifecycle Events'), findsOneWidget);
    expect(find.text('PROVISION_USER'), findsOneWidget);
    expect(find.text('john.doe@springfield.k12.us'), findsOneWidget);

    // Test Trigger Directory Sync Button
    final syncBtn = find.text('Trigger Directory Sync');
    expect(syncBtn, findsOneWidget);
    await tester.ensureVisible(syncBtn);
    await tester.tap(syncBtn);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));

    // New reconciliation log entry should appear
    expect(find.text('RECONCILE_DIRECTORY'), findsOneWidget);
  });
}
