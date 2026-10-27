import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:focus_dns/main.dart';
import 'package:focus_dns/repositories/settings_repository.dart';
import 'package:focus_dns/state_management/protection_state.dart';

void main() {
  testWidgets('App smoke test and mode selector display', (WidgetTester tester) async {
    final repo = InMemorySettingsRepository();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          settingsRepoProvider.overrideWithValue(repo),
        ],
        child: const FocusDNSMobileApp(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(FocusDNSMobileApp), findsOneWidget);
    expect(find.byKey(const Key('header_profile_pill')), findsOneWidget);
    expect(find.byKey(const Key('normal_mode_button')), findsOneWidget);
    expect(find.byKey(const Key('strict_mode_button')), findsOneWidget);
    expect(find.text('Normal'), findsOneWidget);
    expect(find.text('Strict'), findsOneWidget);
  });

  testWidgets('Tapping Strict Mode opens Disclaimer Dialog with exact user text and duration options',
      (WidgetTester tester) async {
    final repo = InMemorySettingsRepository();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          settingsRepoProvider.overrideWithValue(repo),
        ],
        child: const FocusDNSMobileApp(),
      ),
    );
    await tester.pumpAndSettle();

    // Tap Strict Mode button
    await tester.tap(find.byKey(const Key('strict_mode_button')));
    await tester.pumpAndSettle();

    // Verify Disclaimer Dialog Header and exact message
    expect(find.text('Activate Strict Mode'), findsOneWidget);
    expect(
      find.text(
        'In Strict Mode you cannot access any blocked apps or categories until or unless the timer runs out so choose wisely.',
      ),
      findsOneWidget,
    );

    // Verify duration selector and preset chips
    expect(find.text('Select Duration'), findsOneWidget);
    expect(find.text('15m'), findsOneWidget);
    expect(find.text('30m'), findsOneWidget);
    expect(find.text('45m'), findsOneWidget);
    expect(find.text('1h'), findsOneWidget);
    expect(find.text('Lock In Strict Mode'), findsOneWidget);
  });

  testWidgets('Locking Strict Mode starts countdown, greys out toggle, and prevents disabling',
      (WidgetTester tester) async {
    final repo = InMemorySettingsRepository();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          settingsRepoProvider.overrideWithValue(repo),
        ],
        child: const FocusDNSMobileApp(),
      ),
    );
    await tester.pumpAndSettle();

    // Open Disclaimer Dialog
    await tester.tap(find.byKey(const Key('strict_mode_button')));
    await tester.pumpAndSettle();

    // Select 15m preset
    await tester.tap(find.text('15m'));
    await tester.pumpAndSettle();

    // Tap Lock In Strict Mode
    await tester.tap(find.text('Lock In Strict Mode'));
    await tester.pumpAndSettle();

    // Verify dialog dismissed and Strict Mode active
    expect(find.text('Protection Locked'), findsOneWidget);
    expect(find.textContaining('Time Remaining:'), findsOneWidget);
    expect(find.text('LOCKED'), findsOneWidget);

    // Tap the big shield toggle button (which should now be greyed out and locked)
    await tester.tap(find.byKey(const Key('main_protection_toggle')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 750));

    // Verify SnackBar appears informing user that protection is locked
    expect(find.textContaining('Protection is locked'), findsOneWidget);
    // Protection remains locked
    expect(find.text('Protection Locked'), findsOneWidget);

    // Tapping Normal Mode also shows locked warning
    await tester.tap(find.byKey(const Key('normal_mode_button')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 750));
    expect(find.textContaining('Cannot switch to Normal Mode until timer expires'), findsOneWidget);
  });

  testWidgets('Bottom nav switches tabs and header profile pill opens profile sheet',
      (WidgetTester tester) async {
    final repo = InMemorySettingsRepository();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [settingsRepoProvider.overrideWithValue(repo)],
        child: const FocusDNSMobileApp(),
      ),
    );
    await tester.pumpAndSettle();

    // Verify 4-tab bottom navigation
    expect(find.byKey(const Key('nav_0')), findsOneWidget);
    expect(find.byKey(const Key('nav_1')), findsOneWidget);
    expect(find.byKey(const Key('nav_2')), findsOneWidget);
    expect(find.byKey(const Key('nav_3')), findsOneWidget);

    // Switch to More tab
    await tester.tap(find.byKey(const Key('nav_3')));
    await tester.pumpAndSettle();
    expect(find.text('Allowlist'), findsOneWidget);
    expect(find.text('Denylist'), findsOneWidget);

    // Switch back to Protection tab
    await tester.tap(find.byKey(const Key('nav_0')));
    await tester.pumpAndSettle();

    // Tap header profile pill to open profile switcher sheet
    await tester.tap(find.byKey(const Key('header_profile_pill')));
    await tester.pumpAndSettle();
    expect(find.text('DNS Profiles'), findsOneWidget);

    // Tap Detailed Profile Settings button to open all tabs sheet
    await tester.tap(find.text('Detailed Profile Settings & Rules'));
    await tester.pumpAndSettle();
    expect(find.text('Setup'), findsWidgets);
    expect(find.text('Security'), findsWidgets);
  });
}
