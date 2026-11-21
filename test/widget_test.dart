import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:focus_dns/main.dart';
import 'package:focus_dns/repositories/settings_repository.dart';
import 'package:focus_dns/state_management/protection_state.dart';
import 'package:focus_dns/frontend/home_screen.dart';

void main() {
  testWidgets('App smoke test and Begin a session display', (WidgetTester tester) async {
    final repo = InMemorySettingsRepository();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          settingsRepoProvider.overrideWithValue(repo),
        ],
        child: const FocusDNSMobileApp(home: FocusDNSHomeScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(FocusDNSMobileApp), findsOneWidget);
    expect(find.byKey(const Key('header_profile_pill')), findsOneWidget);
    expect(find.byKey(const Key('begin_session_button')), findsOneWidget);
    expect(find.text('Begin a session'), findsOneWidget);
  });

  testWidgets('Tapping Begin a session opens bottom sheet with options',
      (WidgetTester tester) async {
    final repo = InMemorySettingsRepository();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          settingsRepoProvider.overrideWithValue(repo),
        ],
        child: const FocusDNSMobileApp(home: FocusDNSHomeScreen()),
      ),
    );
    await tester.pumpAndSettle();

    // Tap Begin a session button
    await tester.tap(find.byKey(const Key('begin_session_button')));
    await tester.pumpAndSettle();

    // Verify session options: Normal Mode, Strict Mode, Routine, Feed Blocker
    expect(find.text('Begin a Focus Session'), findsOneWidget);
    expect(find.byKey(const Key('normal_mode_button')), findsOneWidget);
    expect(find.byKey(const Key('strict_mode_button')), findsOneWidget);
    expect(find.byKey(const Key('routine_mode_button')), findsOneWidget);
    expect(find.byKey(const Key('feed_blocker_mode_button')), findsOneWidget);
  });

  testWidgets('Locking Strict Mode via Begin a session starts countdown and prevents disabling',
      (WidgetTester tester) async {
    final repo = InMemorySettingsRepository();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          settingsRepoProvider.overrideWithValue(repo),
        ],
        child: const FocusDNSMobileApp(home: FocusDNSHomeScreen()),
      ),
    );
    await tester.pumpAndSettle();

    // Open Begin a session sheet
    await tester.tap(find.byKey(const Key('begin_session_button')));
    await tester.pumpAndSettle();

    // Tap Strict Mode
    await tester.tap(find.byKey(const Key('strict_mode_button')));
    await tester.pumpAndSettle();

    // Verify Strict Mode disclaimer and preset chips
    expect(find.text('Activate Strict Mode'), findsOneWidget);
    expect(find.text('15m'), findsOneWidget);
    expect(find.text('30m'), findsOneWidget);

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
    expect(find.text('Protection Locked'), findsOneWidget);
  });

  testWidgets('Bottom nav switches tabs and header profile pill opens profile sheet',
      (WidgetTester tester) async {
    final repo = InMemorySettingsRepository();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [settingsRepoProvider.overrideWithValue(repo)],
        child: const FocusDNSMobileApp(home: FocusDNSHomeScreen()),
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
