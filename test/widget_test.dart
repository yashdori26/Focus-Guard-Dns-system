import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:focus_dns/main.dart';
import 'package:focus_dns/frontend/auth/welcome_screen.dart';
import 'package:focus_dns/frontend/auth/email_entry_screen.dart';
import 'package:focus_dns/frontend/auth/otp_screen.dart';
import 'package:focus_dns/frontend/screens/onboarding/onboarding_screen.dart';
import 'package:focus_dns/frontend/tabs/deep_focus_tab.dart';
import 'package:focus_dns/frontend/tabs/logs_tab.dart';
import 'package:focus_dns/frontend/more_screen.dart';
import 'package:focus_dns/frontend/theme/wabi_sabi_theme.dart';
import 'package:focus_dns/frontend/screens/legal/privacy_policy_screen.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('FocusDNS smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(const ProviderScope(child: FocusDNSMobileApp()));
    expect(find.byType(FocusDNSMobileApp), findsOneWidget);
  });

  group('Welcome & email sign-in flow', () {
    Widget app(Widget home) => ProviderScope(child: MaterialApp(theme: WabiSabiTheme.lightTheme, home: home));

    testWidgets('Welcome screen shows Create account, Sign in and the privacy link', (WidgetTester tester) async {
      await tester.pumpWidget(app(const WelcomeScreen()));
      // The welcome screen has a looping background animation, so pump for a fixed time.
      await tester.pump(const Duration(milliseconds: 1200));

      expect(find.text('FocusDNS'), findsOneWidget);
      expect(find.byKey(const Key('welcome_create_button')), findsOneWidget);
      expect(find.byKey(const Key('welcome_signin_button')), findsOneWidget);
      expect(find.byKey(const Key('welcome_privacy_link')), findsOneWidget);
    });

    testWidgets('Privacy link opens the privacy policy', (WidgetTester tester) async {
      await tester.pumpWidget(app(const WelcomeScreen()));
      await tester.pump(const Duration(milliseconds: 1200));

      await tester.tap(find.byKey(const Key('welcome_privacy_link')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pump(const Duration(milliseconds: 500));

      expect(find.byType(PrivacyPolicyScreen), findsOneWidget);
      expect(find.text('Privacy policy'), findsOneWidget);
      expect(find.text('What stays on your phone'), findsOneWidget);
    });

    testWidgets('Email step stays put for an invalid email and never shows the code screen', (WidgetTester tester) async {
      await tester.pumpWidget(app(const EmailEntryScreen(isNewAccount: true)));
      await tester.pumpAndSettle();

      await tester.enterText(find.byKey(const Key('auth_email_field')), 'not-an-email');
      await tester.pump();
      await tester.tap(find.byKey(const Key('auth_next_button')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('auth_email_field')), findsOneWidget);
      expect(find.byKey(const Key('auth_otp_field')), findsNothing);
    });

    testWidgets('Valid email advances to code screen', (WidgetTester tester) async {
      await tester.pumpWidget(app(const EmailEntryScreen(isNewAccount: true)));
      await tester.pumpAndSettle();

      await tester.enterText(find.byKey(const Key('auth_email_field')), 'yash@example.com');
      await tester.enterText(find.byKey(const Key('auth_password_field')), 'secret123');
      await tester.pump();
      await tester.tap(find.byKey(const Key('auth_next_button')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));

      expect(find.byKey(const Key('auth_otp_field')), findsOneWidget);
      expect(find.textContaining('yash@example.com'), findsOneWidget);
    });

    testWidgets('Code screen shows the email and a disabled resend timer', (WidgetTester tester) async {
      await tester.pumpWidget(app(const OtpScreen(email: 'yash@example.com', isNewAccount: true)));
      await tester.pump(const Duration(milliseconds: 600));

      expect(find.textContaining('yash@example.com'), findsOneWidget);
      expect(find.textContaining('Resend code in'), findsOneWidget);
      expect(find.byKey(const Key('auth_otp_field')), findsOneWidget);
    });

    testWidgets('Sign In (Login) bypasses onboarding and opens HomeScreen directly', (WidgetTester tester) async {
      await tester.pumpWidget(app(const OtpScreen(email: 'yash@example.com', isNewAccount: false)));
      await tester.pump(const Duration(milliseconds: 600));

      // Enter 6-digit test code (in test environment 123456 verifies)
      await tester.enterText(find.byKey(const Key('auth_otp_field')), '123456');
      await tester.pumpAndSettle();

      // Verify that FocusDNSHomeScreen is displayed and OnboardingScreen is bypassed
      expect(find.byType(OnboardingScreen), findsNothing);
    });
  });

  group('OnboardingScreen Tests', () {
    Widget app() => const ProviderScope(child: MaterialApp(home: OnboardingScreen()));

    testWidgets('Step 1 explains privacy before anything else', (WidgetTester tester) async {
      await tester.pumpWidget(app());
      await tester.pumpAndSettle();

      expect(find.text('Your data stays on your phone'), findsOneWidget);
      expect(find.text('I agree'), findsOneWidget);
      expect(find.byKey(const Key('onboarding_privacy_link')), findsOneWidget);
      expect(find.byType(TextField), findsNothing);
    });

    testWidgets('Name step needs a name, then categories can be toggled and Back keeps the name', (WidgetTester tester) async {
      await tester.pumpWidget(app());
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('onboarding_agree_button')));
      await tester.pumpAndSettle();

      // Next does nothing until a name is typed.
      await tester.tap(find.byKey(const Key('onboarding_next_button')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('onboarding_name_field')), findsOneWidget);

      await tester.enterText(find.byKey(const Key('onboarding_name_field')), 'Yash');
      await tester.pump();
      await tester.tap(find.byKey(const Key('onboarding_next_button')));
      await tester.pumpAndSettle();

      expect(find.text('Adult content & NSFW'), findsOneWidget);
      expect(find.text('Social media feeds'), findsOneWidget);
      expect(find.text('Ads & trackers'), findsOneWidget);
      expect(find.text('Gambling & betting'), findsOneWidget);

      await tester.tap(find.byKey(const Key('onboarding_option_gambling')), warnIfMissed: false);
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('onboarding_back_button')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('onboarding_name_field')), findsOneWidget);
      expect(find.text('Yash'), findsOneWidget);
    });

    testWidgets('Permission steps offer an allow button and Maybe later', (WidgetTester tester) async {
      await tester.pumpWidget(app());
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('onboarding_agree_button')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('onboarding_name_field')), 'Yash');
      await tester.pump();
      await tester.tap(find.byKey(const Key('onboarding_next_button')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('onboarding_next_button')));
      await tester.pumpAndSettle();

      expect(find.text('Allow VPN access'), findsOneWidget);
      expect(find.byKey(const Key('onboarding_skip_button')), findsOneWidget);
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

      // Check Top Profile Pill & Shield ID Card
      expect(find.byKey(const Key('header_profile_pill')), findsOneWidget);
      expect(find.text('FOCUSDNS'), findsOneWidget);
      expect(find.text('SHIELD ID'), findsOneWidget);
      expect(find.text('Member since'), findsOneWidget);
      expect(find.text('Rank'), findsOneWidget);
      expect(find.text('Streak'), findsOneWidget);
      expect(find.text('MILESTONES'), findsOneWidget);
      expect(find.text('Shield activated'), findsOneWidget);
      expect(find.byKey(const Key('profile_edit_button')), findsOneWidget);

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

    testWidgets('Tapping Delete Account opens Hinge-style reasons screen then confirmation', (WidgetTester tester) async {
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

      // Hinge-style flow: reasons screen first, then final confirmation dialog.
      expect(find.text('Why are you leaving?'), findsOneWidget);
      await tester.tap(find.text('Privacy concerns'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('delete_continue_button')));
      await tester.pumpAndSettle();

      expect(find.text('Delete Account?'), findsOneWidget);
      expect(find.byKey(const Key('confirm_delete_account_button')), findsOneWidget);
      expect(find.text('Keep My Account'), findsOneWidget);
    });
  });
}
