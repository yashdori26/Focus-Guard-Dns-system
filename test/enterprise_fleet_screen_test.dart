import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:focus_dns/screens/enterprise_fleet_screen.dart';
import 'package:focus_dns/services/enterprise_service.dart';

void main() {
  testWidgets('EnterpriseFleetScreen renders WebSocket status, fleet card, and lock toggle', (tester) async {
    final service = EnterpriseService(mockOnly: true);

    await tester.pumpWidget(
      MaterialApp(
        home: EnterpriseFleetScreen(service: service),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    // Verify Title and WebSocket Banner
    expect(find.text('Fleet Push & Remote Control Center'), findsOneWidget);
    expect(find.text('WebSocket Fleet Hub: CONNECTED'), findsOneWidget);
    expect(find.text('Sub-50ms Fanout Active'), findsOneWidget);

    // Verify Fleet Card & Devices
    expect(find.text('Chromebook Cart 4B'), findsOneWidget);
    expect(find.text('chromebook_01'), findsOneWidget);
    expect(find.text('chromebook_02'), findsOneWidget);

    // Verify Lock button in idle state
    final lockButton = find.text('Lock Fleet Focus (1h)');
    expect(lockButton, findsOneWidget);

    // Tap Lock button
    await tester.tap(lockButton);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    // Fleet state should update to locked
    expect(find.text('Unlock Fleet'), findsOneWidget);

    // Tap Unlock button
    await tester.tap(find.text('Unlock Fleet'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    // Fleet state should return to unlocked
    expect(find.text('Lock Fleet Focus (1h)'), findsOneWidget);
  });
}
