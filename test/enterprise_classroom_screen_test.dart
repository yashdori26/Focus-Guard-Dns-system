import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:focus_dns/models/enterprise_models.dart';
import 'package:focus_dns/screens/enterprise_classroom_screen.dart';
import 'package:focus_dns/services/enterprise_service.dart';

void main() {
  testWidgets('EnterpriseClassroomScreen renders classroom dashboard, student cards, and safety footer', (tester) async {
    final service = EnterpriseService(mockOnly: true);

    await tester.pumpWidget(
      MaterialApp(
        home: EnterpriseClassroomScreen(
          orgId: 'org_springfield',
          service: service,
        ),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    // Verify Title & Session Header
    expect(find.text('Classroom & Exam Fleet Orchestrator'), findsOneWidget);
    expect(find.text('Biology 101 - Period 3'), findsWidgets);
    expect(find.textContaining('usr_teacher_smith'), findsOneWidget);

    // Verify Focus Mode Chips
    expect(find.text('Normal Protection'), findsWidgets);
    expect(find.text('Restricted Research'), findsOneWidget);
    expect(find.text('Strict Exam Lockdown'), findsOneWidget);

    // Verify Student Presence Cards
    expect(find.text('Alex Johnson'), findsOneWidget);
    expect(find.text('Emma Watson'), findsOneWidget);
    expect(find.text('Liam Miller'), findsOneWidget);

    // Verify Domains and Status
    expect(find.text('khanacademy.org'), findsOneWidget);
    expect(find.text('canvas.instructure.com'), findsOneWidget);
    expect(find.text('roblox.com'), findsOneWidget);

    // Verify Attention Alert Banner
    expect(find.textContaining('Attention Alert: 2 student distraction attempts'), findsOneWidget);

    // Verify Inviolable Life-Safety Exemption Guarantee
    expect(find.textContaining('Inviolable Life Safety Exemption'), findsOneWidget);

    // Test Focus Mode Selection
    final researchChip = find.text('Restricted Research');
    await tester.tap(researchChip);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    // Test Permit Domain Button
    final permitBtn = find.text('Permit Domain');
    expect(permitBtn, findsOneWidget);
    await tester.tap(permitBtn);
    await tester.pumpAndSettle();

    expect(find.text('Add Permitted Exam Domain'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
  });
}
