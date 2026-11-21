import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:focus_dns/frontend/auth/views/security_checkpoint_view.dart';
import 'package:focus_dns/state_management/providers.dart';

void main() {
  testWidgets('SecurityCheckpointView performs integrity inspection and renders diagnostics', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(
          home: SecurityCheckpointView(),
        ),
      ),
    );

    // Initial inspection delay
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();

    expect(find.text('Security & Device Integrity'), findsOneWidget);
    expect(find.text('DEVICE INTEGRITY VERIFIED'), findsOneWidget);
    expect(find.text('NETWORK & SESSION FORENSICS'), findsOneWidget);
    expect(find.text('LOGIN SECURITY CONTROLS'), findsOneWidget);
    expect(find.text('Geo-Velocity Anomaly Shield'), findsOneWidget);
    expect(find.text('SIM-Swap Fraud Guard'), findsOneWidget);
    expect(find.text('Forensic Audit'), findsOneWidget);
    expect(find.text('Recovery Keys'), findsOneWidget);
    expect(find.text('Revoke Everywhere & Panic Sign Out'), findsOneWidget);
  });
}
