import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:focus_dns/main.dart';
import 'package:focus_dns/frontend/auth/email_auth_screen.dart';
import 'package:focus_dns/frontend/screens/onboarding/onboarding_screen.dart';
import 'package:focus_dns/frontend/tabs/deep_focus_tab.dart';
import 'package:focus_dns/frontend/tabs/logs_tab.dart';
import 'package:focus_dns/frontend/more_screen.dart';
import 'package:focus_dns/frontend/theme/wabi_sabi_theme.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('FocusDNS smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(const ProviderScope(child: FocusDNSMobileApp()));
    expect(find.byType(FocusDNSMobileApp), findsOneWidget);
  });

  group('EmailAuthScreen Tests', () {
    testWidgets('Renders Sign In screen cleanly with all initial elements', (WidgetTester tester) async {
      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: EmailAuthScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Check header and titles
      expect(find.text('FOCUS DNS'), findsOneWidget);
      expect(find.text('100% Local · Sovereign Shield'), findsNothing);
      expect(find.text('Skip'), findsNothing);
      expect(find.text('Sign In'), findsAtLeastNWidgets(1));
      expect(find.byKey(const Key('tab_sign_in')), findsOneWidget);
      expect(find.byKey(const Key('tab_create_account')), findsOneWidget);

      // Check input fields
      expect(find.byKey(const Key('email_input_field')), findsOneWidget);
      expect(find.byKey(const Key('password_input_field')), findsOneWidget);
      expect(find.byKey(const Key('submit_auth_button')), findsOneWidget);

      // Confirm and Profile fields should NOT be shown in Sign In mode
      expect(find.byKey(const Key('confirm_password_input_field')), findsNothing);
      expect(find.byKey(const Key('profile_name_input_field')), findsNothing);
    });

    testWidgets('Switches cleanly between Sign In and Create Account tabs', (WidgetTester tester) async {
      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: EmailAuthScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Tap Create Account Tab
      await tester.tap(find.byKey(const Key('tab_create_account')));
      await tester.pumpAndSettle();

      expect(find.text('Create Account'), findsAtLeastNWidgets(2));
      expect(find.byKey(const Key('confirm_password_input_field')), findsOneWidget);
      expect(find.byKey(const Key('profile_name_input_field')), findsNothing); // completely removed
      expect(find.byKey(const Key('submit_auth_button')), findsOneWidget);

      // Tap back to Sign In
      await tester.tap(find.byKey(const Key('tab_sign_in')));
      await tester.pumpAndSettle();

      expect(find.text('Sign In'), findsAtLeastNWidgets(1));
      expect(find.byKey(const Key('confirm_password_input_field')), findsNothing);
    });

    testWidgets('Validates invalid email and shows inline error banner', (WidgetTester tester) async {
      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: EmailAuthScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Enter invalid email
      await tester.enterText(find.byKey(const Key('email_input_field')), 'invalid-email');
      await tester.enterText(find.byKey(const Key('password_input_field')), '123456');
      await tester.ensureVisible(find.byKey(const Key('submit_auth_button')));
      await tester.tap(find.byKey(const Key('submit_auth_button')));
      await tester.pumpAndSettle();

      expect(find.text('Please enter a valid email address.'), findsOneWidget);
    });

    testWidgets('Validates password mismatch in Create Account mode', (WidgetTester tester) async {
      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: EmailAuthScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Switch to Create Account
      await tester.tap(find.byKey(const Key('tab_create_account')));
      await tester.pumpAndSettle();

      await tester.enterText(find.byKey(const Key('email_input_field')), 'test@example.com');
      await tester.enterText(find.byKey(const Key('password_input_field')), 'password123');
      await tester.enterText(find.byKey(const Key('confirm_password_input_field')), 'mismatched123');
      await tester.ensureVisible(find.byKey(const Key('submit_auth_button')));
      await tester.tap(find.byKey(const Key('submit_auth_button')));
      await tester.pumpAndSettle();

      expect(find.text('Passwords do not match. Please verify.'), findsOneWidget);
    });

    testWidgets('Toggles password visibility on eye button click', (WidgetTester tester) async {
      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: EmailAuthScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final visibilityFinder = find.byKey(const Key('toggle_password_visibility'));
      expect(visibilityFinder, findsOneWidget);

      // Tap eye toggle
      await tester.tap(visibilityFinder);
      await tester.pumpAndSettle();

      // Verify icon changed to visibility_off
      expect(find.byIcon(Icons.visibility_outlined), findsOneWidget);
    });
  });

  group('OnboardingScreen Tests', () {
    testWidgets('Renders Step 1 with Shield Profile Name input', (WidgetTester tester) async {
      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: OnboardingScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Name Your Shield'), findsOneWidget);
      expect(find.text('1 / 3'), findsOneWidget);
      expect(find.text('Continue →'), findsOneWidget);
      expect(find.byType(TextField), findsOneWidget);
    });

    testWidgets('Navigates from Step 1 to Step 2 and toggles categories cleanly', (WidgetTester tester) async {
      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: OnboardingScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Tap Continue to Step 2
      await tester.tap(find.text('Continue →'));
      await tester.pumpAndSettle();

      expect(find.text('Choose What to Sever'), findsOneWidget);
      expect(find.text('2 / 3'), findsOneWidget);
      expect(find.text('Adult Content & NSFW'), findsOneWidget);
      expect(find.text('Social Media (Reels & Feeds)'), findsOneWidget);
      expect(find.text('Surveillance & Ad Trackers'), findsOneWidget);
      expect(find.text('Gambling & Betting'), findsOneWidget);
      expect(find.text('← Back'), findsOneWidget);

      // Toggle a category
      await tester.tap(find.text('Gambling & Betting'));
      await tester.pumpAndSettle();

      // Tap Back to return to Step 1
      await tester.tap(find.text('← Back'));
      await tester.pumpAndSettle();

      expect(find.text('Name Your Shield'), findsOneWidget);
      expect(find.text('1 / 3'), findsOneWidget);
    });

    testWidgets('Navigates through all 3 steps to Security & Trust', (WidgetTester tester) async {
      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: OnboardingScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Step 1 -> Step 2
      await tester.tap(find.text('Continue →'));
      await tester.pumpAndSettle();

      // Step 2 -> Step 3
      await tester.tap(find.text('Continue →'));
      await tester.pumpAndSettle();

      expect(find.text('Local Security & Trust'), findsOneWidget);
      expect(find.text('3 / 3'), findsOneWidget);
      expect(find.text('100% LOCAL SQLITE ASSURANCE'), findsOneWidget);
      expect(find.text('Local DNS VPN Tunnel'), findsOneWidget);
      expect(find.text('Doomscroll Accessibility'), findsOneWidget);
      expect(find.text('Doze Battery Immunity'), findsOneWidget);
      expect(find.text('Activate Shield & Launch →'), findsOneWidget);
    });
  });

  group('DeepFocusTab Tests', () {
    testWidgets('Renders Focus Tab with hero title, categories, and restrictions button', (WidgetTester tester) async {
      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(
                child: DeepFocusTab(),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('FOCUSDNS · FOCUS'), findsOneWidget);
      expect(find.text('Quiet the noise.'), findsOneWidget);
      expect(find.text('ACTIVE RESTRICTIONS'), findsOneWidget);
      expect(find.byKey(const Key('add_restriction_button')), findsOneWidget);
      expect(find.text('Websites, Apps & Games'), findsOneWidget);
      expect(find.text('Categories'), findsOneWidget);
    });

    testWidgets('Tapping add restriction button opens bottom sheet modal', (WidgetTester tester) async {
      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(
                child: DeepFocusTab(),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('add_restriction_button')));
      await tester.pumpAndSettle();

      expect(find.text('Add Restriction'), findsOneWidget);
      expect(find.text('App or Website'), findsOneWidget);
      expect(find.text('Category'), findsOneWidget);
    });
  });

  group('LogsTab Tests', () {
    testWidgets('Renders Live Query Activity header, search field, and filter chips', (WidgetTester tester) async {
      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(
                child: LogsTab(),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('LIVE QUERY ACTIVITY'), findsOneWidget);
      expect(find.text('Refresh'), findsOneWidget);
      expect(find.text('Local SQLite'), findsOneWidget);
      expect(find.byType(TextField), findsOneWidget);
      expect(find.text('All'), findsOneWidget);
      expect(find.text('Blocked'), findsOneWidget);
      expect(find.text('Allowed'), findsOneWidget);
    });

    testWidgets('Toggles filter chips between All, Blocked, and Allowed', (WidgetTester tester) async {
      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(
                child: LogsTab(),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Blocked'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Allowed'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('All'));
      await tester.pumpAndSettle();
    });
  });

  group('MoreTab Tests', () {
    testWidgets('Renders top profile card and all 5 management sections cleanly', (WidgetTester tester) async {
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            theme: WabiSabiTheme.lightTheme,
            home: Builder(
              builder: (context) {
                final palette = WabiSabiPalette.of(context);
                return Scaffold(
                  body: MoreTab(palette: palette),
                );
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Check Top Profile Pill
      expect(find.byKey(const Key('header_profile_pill')), findsOneWidget);

      // Section 1
      expect(find.text('NETWORK & FILTERING'), findsOneWidget);
      expect(find.text('Threat Shield'), findsOneWidget);
      expect(find.text('SafeSearch Filter'), findsOneWidget);
      expect(find.text('Ad & Tracker Blocker'), findsOneWidget);
      expect(find.text('Anti-VPN Bypass'), findsOneWidget);

      // Section 2
      expect(find.text('DISTRACTIONS & SOCIAL FEEDS'), findsOneWidget);
      expect(find.text('Block YouTube Shorts'), findsOneWidget);
      expect(find.text('Block Instagram Reels'), findsOneWidget);

      // Section 3
      expect(find.text('DEVICE INTEGRITY & PERMISSIONS'), findsOneWidget);
      expect(find.text('Accessibility Service'), findsOneWidget);
      expect(find.text('Anti-Uninstall Shield'), findsOneWidget);
      expect(find.text('Dark Theme'), findsOneWidget);
      expect(find.text('Battery Saver Immunity'), findsOneWidget);

      // Section 4
      expect(find.text('DATA & SYSTEM MANAGEMENT'), findsOneWidget);
      expect(find.text('Custom Domain Rules'), findsOneWidget);
      expect(find.text('Clear Query Logs'), findsOneWidget);
      expect(find.text('Re-run Setup Walkthrough'), findsOneWidget);

      // Section 5: Hinge-style Account Actions
      expect(find.text('ACCOUNT ACTIONS'), findsOneWidget);
      expect(find.text('Log Out'), findsOneWidget);
      expect(find.text('Delete Account'), findsOneWidget);
    });

    testWidgets('Tapping Log Out opens Hinge-style log out confirmation modal', (WidgetTester tester) async {
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            theme: WabiSabiTheme.lightTheme,
            home: Builder(
              builder: (context) {
                final palette = WabiSabiPalette.of(context);
                return Scaffold(
                  body: MoreTab(palette: palette),
                );
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.ensureVisible(find.text('Log Out'));
      await tester.tap(find.text('Log Out'));
      await tester.pumpAndSettle();

      expect(find.text('Log out of FocusDNS?'), findsOneWidget);
      expect(find.byKey(const Key('confirm_logout_button')), findsOneWidget);
      expect(find.text('Cancel'), findsOneWidget);
    });

    testWidgets('Tapping Delete Account opens destructive warning modal', (WidgetTester tester) async {
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            theme: WabiSabiTheme.lightTheme,
            home: Builder(
              builder: (context) {
                final palette = WabiSabiPalette.of(context);
                return Scaffold(
                  body: MoreTab(palette: palette),
                );
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.ensureVisible(find.text('Delete Account'));
      await tester.tap(find.text('Delete Account'));
      await tester.pumpAndSettle();

      expect(find.text('Delete Account?'), findsOneWidget);
      expect(find.byKey(const Key('confirm_delete_account_button')), findsOneWidget);
      expect(find.text('Keep My Account'), findsOneWidget);
    });
  });
}
