import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:focus_dns/backend/mdm_service.dart';
import 'package:focus_dns/frontend/device_policy_audit_screen.dart';
import 'package:focus_dns/frontend/mdm_shield_card.dart';

void main() {
  group('Device Policy Audit Screen Widget Tests', () {
    setUp(() {
      FocusMdmManager.setSimulatedProtection(false);
      FocusMdmManager.setSimulatedTimer(0);
    });

    testWidgets('DevicePolicyAuditScreen renders clean uninstallation posture when idle', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(800, 1800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(
        const MaterialApp(
          home: DevicePolicyAuditScreen(),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Security & Policy Audit'), findsOneWidget);
      expect(find.text('Uninstallation Permission Law'), findsOneWidget);
      expect(find.text('UNLOCKED (Normal Uninstallation Permitted)'), findsOneWidget);
      expect(find.text('Cryptographic Protection State'), findsOneWidget);
      expect(find.text('VERIFIED (SHA-256)'), findsOneWidget);
      expect(find.text('Anti-Tamper & Security Integrity'), findsOneWidget);
      expect(find.text('100 / 100 (EXCELLENT)'), findsOneWidget);
    });

    testWidgets('DevicePolicyAuditScreen renders locked countdown when focus timer is active', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(800, 1800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      FocusMdmManager.setSimulatedProtection(true);
      FocusMdmManager.setSimulatedTimer(1200); // 20:00

      await tester.pumpWidget(
        const MaterialApp(
          home: DevicePolicyAuditScreen(),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('LOCKED (Session in Progress: 20:00)'), findsOneWidget);
      expect(find.text('20:00'), findsWidgets);
      expect(find.text('Active Anti-Bypass Restrictions'), findsOneWidget);
      expect(find.text('ENFORCED'), findsWidgets);
    });

    testWidgets('MdmShieldCard navigates to DevicePolicyAuditScreen on tap', (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(child: MdmShieldCard()),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final auditButton = find.text('Device Security & Policy Audit');
      expect(auditButton, findsOneWidget);

      await tester.tap(auditButton);
      await tester.pumpAndSettle();

      // Screen pushed onto navigator
      expect(find.byType(DevicePolicyAuditScreen), findsOneWidget);
      expect(find.text('Uninstallation Permission Law'), findsOneWidget);
    });
  });
}
