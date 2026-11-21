import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:focus_dns/frontend/auth/views/auth_recovery_vault_view.dart';

void main() {
  testWidgets('AuthRecoveryVaultView generates and displays offline emergency keys', (WidgetTester tester) async {
    bool onCompletedFired = false;

    await tester.pumpWidget(
      MaterialApp(
        home: AuthRecoveryVaultView(
          phoneNumber: '+14155552671',
          onCompleted: () {
            onCompletedFired = true;
          },
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('Recovery Vault'), findsOneWidget);
    expect(find.text('EMERGENCY ACCESS KEYS'), findsOneWidget);
    expect(find.text('Store Offline Keys Securely'), findsOneWidget);
    expect(find.text('Copy All Keys'), findsOneWidget);

    // Verify checkbox enables Done button
    final doneButton = find.widgetWithText(ElevatedButton, 'Done');
    final checkbox = find.byType(Checkbox);

    // Tap checkbox to acknowledge saving keys
    await tester.tap(checkbox);
    await tester.pumpAndSettle();

    // Tap Done
    await tester.tap(doneButton);
    await tester.pumpAndSettle();

    expect(onCompletedFired, isTrue);
  });
}
