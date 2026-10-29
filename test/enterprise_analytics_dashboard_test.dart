import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:focus_dns/screens/enterprise_analytics_dashboard_screen.dart';
import 'package:focus_dns/services/enterprise_service.dart';
import 'package:focus_dns/widgets/columnar_timeseries_chart.dart';
import 'package:focus_dns/widgets/threat_matrix_gauge.dart';

void main() {
  testWidgets('EnterpriseAnalyticsDashboardScreen renders metrics, charts, and top domains', (tester) async {
    final service = EnterpriseService(mockOnly: true);

    await tester.pumpWidget(
      MaterialApp(
        home: EnterpriseAnalyticsDashboardScreen(
          tenantId: 'org_test',
          service: service,
        ),
      ),
    );

    // Initial pump & wait for mock data to resolve
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    // Verify title
    expect(find.text('Enterprise Big Data Analytics'), findsOneWidget);

    // Verify Metric Cards
    expect(find.text('Ingested Telemetry'), findsOneWidget);
    expect(find.text('Zero-Day Threats'), findsAtLeastNWidgets(1));
    expect(find.text('Policy Drops'), findsOneWidget);
    expect(find.text('p99 Resolution Latency'), findsOneWidget);

    // Verify charts
    expect(find.byType(ColumnarTimeseriesChart), findsOneWidget);
    expect(find.byType(ThreatMatrixGauge), findsOneWidget);

    // Verify search field exists
    expect(find.byType(TextField), findsOneWidget);

    // Test searching top domains
    await tester.enterText(find.byType(TextField), 'tiktok');
    await tester.pump();

    // Verify action buttons in AppBar
    expect(find.byIcon(Icons.refresh), findsOneWidget);
    expect(find.byIcon(Icons.hub_outlined), findsOneWidget); // Tenants
    expect(find.byIcon(Icons.devices), findsOneWidget); // Fleet
    expect(find.byIcon(Icons.verified_user_outlined), findsOneWidget); // RBAC
    expect(find.byIcon(Icons.cloud_upload_outlined), findsOneWidget); // SIEM
  });
}
