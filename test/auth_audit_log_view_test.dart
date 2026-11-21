import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:focus_dns/backend/api_client.dart';
import 'package:focus_dns/frontend/auth/views/auth_audit_log_view.dart';

class MockApiClient extends FocusDnsApiClient {
  MockApiClient() : super(baseUrl: 'http://127.0.0.1:8080');

  @override
  Future<Map<String, dynamic>> get(String path) async {
    if (path.startsWith('/api/auth/audit')) {
      return {
        'success': true,
        'audit': [
          {
            'event': 'session_create',
            'phone': '+1 (555) 019-2834',
            'ip': '192.168.1.50',
            'user_agent': 'Mozilla/5.0 (Linux; Android)',
            'timestamp': 1700000000.0,
          },
          {
            'event': 'otp_verified',
            'phone': '+1 (555) 019-2834',
            'ip': '192.168.1.50',
            'user_agent': 'Mozilla/5.0 (Linux; Android)',
            'timestamp': 1699999900.0,
          }
        ],
        'threat_audit': [
          {
            'phone': '+1 (555) 019-2834',
            'ip': '192.168.1.50',
            'country': 'US',
            'device_fingerprint': 'fp_device_alpha_1',
            'timestamp': 1700000000.0,
            'success': true,
            'flags': ['STANDARD_CELLULAR_MNO'],
          }
        ]
      };
    }
    return {'success': false, 'error': 'Unknown route'};
  }
}

void main() {
  testWidgets('AuthAuditLogView displays metrics header and forensic records', (WidgetTester tester) async {
    final mockClient = MockApiClient();

    await tester.pumpWidget(
      MaterialApp(
        home: AuthAuditLogView(
          apiClient: mockClient,
          phoneNumber: '+1 (555) 019-2834',
        ),
      ),
    );

    // Initial loading state
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    await tester.pumpAndSettle();

    // Verify header and metrics
    expect(find.text('Security Audit Trail'), findsOneWidget);
    expect(find.text('Total Events'), findsOneWidget);
    expect(find.text('Verified Sessions'), findsOneWidget);
    expect(find.text('Geo Inspec.'), findsOneWidget);

    // Verify search and filter chips
    expect(find.text('All Events'), findsOneWidget);
    expect(find.text('Verified'), findsOneWidget);
    expect(find.text('Threat / Anomaly'), findsOneWidget);

    // Verify events rendered
    expect(find.text('SESSION CREATE'), findsOneWidget);
    expect(find.text('OTP VERIFIED'), findsOneWidget);
    expect(find.text('192.168.1.50'), findsWidgets);
  });

  testWidgets('AuthAuditLogView search filter filters matching records', (WidgetTester tester) async {
    final mockClient = MockApiClient();

    await tester.pumpWidget(
      MaterialApp(
        home: AuthAuditLogView(
          apiClient: mockClient,
          phoneNumber: '+1 (555) 019-2834',
        ),
      ),
    );

    await tester.pumpAndSettle();

    // Enter query in search box
    final searchField = find.byType(TextField);
    await tester.enterText(searchField, 'SESSION');
    await tester.pumpAndSettle();

    expect(find.text('SESSION CREATE'), findsOneWidget);
    expect(find.text('OTP VERIFIED'), findsNothing);
  });
}
