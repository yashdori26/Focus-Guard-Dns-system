import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:focus_dns/backend/mdm_service.dart';
import 'package:focus_dns/frontend/mdm_shield_card.dart';
import 'package:focus_dns/frontend/split_tunnel_screen.dart';

void main() {
  group('MDM & Split Tunneling Widget Tests', () {
    setUp(() {
      FocusMdmManager.setSimulatedProtection(false);
      FocusMdmManager.setSimulatedTimer(0);
    });

    testWidgets('MdmShieldCard displays UNLOCKED status when idle', (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(child: MdmShieldCard()),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Anti-Uninstall & Device Shield'), findsOneWidget);
      expect(find.text('✓ UNLOCKED'), findsOneWidget);
      expect(find.text('Device Administrator'), findsOneWidget);
      expect(find.text('Per-App Split Tunneling (Bypass Apps)'), findsOneWidget);
    });

    testWidgets('MdmShieldCard displays LOCKED status and countdown when timer is active', (WidgetTester tester) async {
      FocusMdmManager.setSimulatedTimer(1500); // 25:00

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(child: MdmShieldCard()),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('🔒 LOCKED'), findsOneWidget);
      expect(find.text('Time until uninstallation unlocks:'), findsOneWidget);
      expect(find.text('25:00'), findsOneWidget);
    });

    testWidgets('SplitTunnelScreen renders app list and search bar', (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: SplitTunnelScreen(),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Split Tunneling'), findsOneWidget);
      expect(find.text('Exempt Applications from VPN'), findsOneWidget);
      expect(find.byType(TextField), findsOneWidget);
      expect(find.text('Google Pay'), findsOneWidget);
      expect(find.text('YONO SBI'), findsOneWidget);

      // Tap on Google Pay checkbox
      await tester.tap(find.text('Google Pay'));
      await tester.pumpAndSettle();

      // Tap Save
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
    });

    testWidgets('SplitTunnelScreen filter searches by keyword', (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: SplitTunnelScreen(),
        ),
      );
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'Chrome');
      await tester.pumpAndSettle();

      expect(find.widgetWithText(ListTile, 'Chrome'), findsOneWidget);
      expect(find.text('YONO SBI'), findsNothing);
    });
  });
}
