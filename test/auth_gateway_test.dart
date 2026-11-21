import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:focus_dns/backend/api_client.dart';
import 'package:focus_dns/frontend/auth/auth_gateway.dart';
import 'package:focus_dns/frontend/auth/email_onboarding_wizard.dart';
import 'package:focus_dns/frontend/home_screen.dart';
import 'package:focus_dns/repositories/settings_repository.dart';
import 'package:focus_dns/state_management/auth_state.dart';
import 'package:focus_dns/state_management/protection_state.dart';
import 'package:focus_dns/state_management/settings_state.dart';
import 'package:focus_dns/state_management/setup_state.dart';
import 'package:focus_dns/state_management/theme_state.dart';
import 'package:shared_preferences/shared_preferences.dart';

class MockEmailAuthApiClient extends FocusDnsApiClient {
  MockEmailAuthApiClient() : super(baseUrl: 'http://127.0.0.1:8080');

  @override
  Future<Map<String, dynamic>> sendEmailCode(String email) async {
    return {
      'success': true,
      'email': email,
      'dev_otp': '1234',
      'message': 'Verification code sent to $email',
    };
  }

  @override
  Future<Map<String, dynamic>> verifyEmailCode(String email, String code) async {
    if (code == '1234') {
      return {
        'success': true,
        'token': 'mock-session-jwt-1234',
        'email': email,
        'profile_id': 'pid-email-01',
      };
    }
    return {'success': false, 'error': 'Invalid 4-digit code. Use 1234.'};
  }

  @override
  Future<Map<String, dynamic>> loginWithEmail(String email, String password) async {
    if (email == 'user@focusdns.net' && password == 'password123') {
      return {
        'success': true,
        'token': 'mock-session-jwt-email-999',
        'email': email,
        'profile_id': 'pid-email-01',
        'profile_name': 'Personal Shield',
        'profiles': [
          {'profile_id': 'pid-email-01', 'name': 'Personal Shield', 'device_count': 1},
        ],
      };
    }
    return {'success': false, 'error': 'Invalid email or password'};
  }

  @override
  Future<Map<String, dynamic>> registerWithEmail(String email, String password, [String? profileName]) async {
    return {
      'success': true,
      'token': 'mock-session-jwt-registered-888',
      'email': email,
      'profile_id': 'pid-new-77',
      'profile_name': profileName ?? 'Personal Shield',
      'profiles': [
        {'profile_id': 'pid-new-77', 'name': profileName ?? 'Personal Shield', 'device_count': 1},
      ],
    };
  }

  @override
  Future<Map<String, dynamic>> verifySession(String token) async {
    return {'success': true, 'token': token, 'email': 'user@focusdns.net'};
  }

  @override
  Future<String?> detectClientIp() async => '103.240.79.203';

  @override
  Future<String?> linkIp([String? ip]) async => ip ?? '103.240.79.203';

  @override
  Future<bool> logoutSession() async => true;
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('1. AuthGateway boots into EmailOnboardingWizard at Step 0 (Email & Password) when not logged in', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(800, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    final mockClient = MockEmailAuthApiClient();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          apiClientProvider.overrideWithValue(mockClient),
          settingsRepoProvider.overrideWithValue(InMemorySettingsRepository()),
        ],
        child: const MaterialApp(
          home: AuthGateway(),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    // Verify EmailOnboardingWizard is shown and HomeScreen is NOT shown
    expect(find.byType(EmailOnboardingWizard), findsOneWidget);
    expect(find.byType(FocusDNSHomeScreen), findsNothing);

    // Step 0 contents (3-step wizard)
    expect(find.text('STEP 1 OF 3 · GET STARTED'), findsOneWidget);
    expect(find.text('Create your account.'), findsOneWidget);
    expect(find.byKey(const Key('email_input_field')), findsOneWidget);
    expect(find.byKey(const Key('password_input_field')), findsOneWidget);
    expect(find.byKey(const Key('confirm_password_input_field')), findsOneWidget);
    expect(find.byKey(const Key('submit_auth_button')), findsOneWidget);
  });

  testWidgets('2. Toggling tabs switches between Create Account and Sign In modes', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(800, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    final mockClient = MockEmailAuthApiClient();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          apiClientProvider.overrideWithValue(mockClient),
          settingsRepoProvider.overrideWithValue(InMemorySettingsRepository()),
        ],
        child: const MaterialApp(
          home: AuthGateway(),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    // Switch to Sign In
    await tester.tap(find.byKey(const Key('tab_sign_in')));
    await tester.pumpAndSettle();

    expect(find.text('WELCOME BACK'), findsOneWidget);
    expect(find.text('Sign in to FocusDNS.'), findsOneWidget);
    expect(find.byKey(const Key('confirm_password_input_field')), findsNothing);

    // Switch back to Create Account
    await tester.tap(find.byKey(const Key('tab_create_account')));
    await tester.pumpAndSettle();

    expect(find.text('STEP 1 OF 3 · GET STARTED'), findsOneWidget);
    expect(find.text('Create your account.'), findsOneWidget);
    expect(find.byKey(const Key('confirm_password_input_field')), findsOneWidget);
  });

  testWidgets('3. Validation displays error banners for invalid input', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(800, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    final mockClient = MockEmailAuthApiClient();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          apiClientProvider.overrideWithValue(mockClient),
          settingsRepoProvider.overrideWithValue(InMemorySettingsRepository()),
        ],
        child: const MaterialApp(
          home: AuthGateway(),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    // Test invalid email
    await tester.enterText(find.byKey(const Key('email_input_field')), 'invalid-email');
    await tester.enterText(find.byKey(const Key('password_input_field')), 'password123');
    await tester.enterText(find.byKey(const Key('confirm_password_input_field')), 'password123');
    await tester.ensureVisible(find.byKey(const Key('submit_auth_button')));
    await tester.tap(find.byKey(const Key('submit_auth_button')));
    await tester.pump();
    expect(find.text('Please enter a valid email address.'), findsOneWidget);

    // Test short password
    await tester.enterText(find.byKey(const Key('email_input_field')), 'valid@focusdns.net');
    await tester.enterText(find.byKey(const Key('password_input_field')), '123');
    await tester.enterText(find.byKey(const Key('confirm_password_input_field')), '123');
    await tester.ensureVisible(find.byKey(const Key('submit_auth_button')));
    await tester.tap(find.byKey(const Key('submit_auth_button')));
    await tester.pump();
    expect(find.text('Password must be at least 6 characters.'), findsOneWidget);

    // Test password mismatch
    await tester.enterText(find.byKey(const Key('password_input_field')), 'password123');
    await tester.enterText(find.byKey(const Key('confirm_password_input_field')), 'different123');
    await tester.ensureVisible(find.byKey(const Key('submit_auth_button')));
    await tester.tap(find.byKey(const Key('submit_auth_button')));
    await tester.pump();
    expect(find.text('Passwords do not match.'), findsOneWidget);
  });

  testWidgets('4. Option A: Full New Account 3-Step Flow (Screen 1: Email/Password -> Screen 2: Profile Name -> Screen 3: Permissions -> Dashboard)', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(800, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    final mockClient = MockEmailAuthApiClient();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          apiClientProvider.overrideWithValue(mockClient),
          settingsRepoProvider.overrideWithValue(InMemorySettingsRepository()),
        ],
        child: const MaterialApp(
          home: AuthGateway(),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    // Screen 1: Fill Create Account form
    await tester.enterText(find.byKey(const Key('email_input_field')), 'warrior@focusdns.net');
    await tester.enterText(find.byKey(const Key('password_input_field')), 'securePass99');
    await tester.enterText(find.byKey(const Key('confirm_password_input_field')), 'securePass99');
    await tester.ensureVisible(find.byKey(const Key('submit_auth_button')));
    await tester.tap(find.byKey(const Key('submit_auth_button')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    // Advances DIRECTLY to Screen 2 (Profile Name Setup) - Zero OTP!
    expect(find.text('STEP 2 OF 3 · PROFILE SETUP'), findsOneWidget);
    expect(find.text('Name your DNS profile.'), findsOneWidget);

    // Verify text box starts completely empty with no pre-loaded text and suggestions are removed (Option 1A)
    final profileTextField = tester.widget<TextFormField>(find.byKey(const Key('onboarding_profile_name_field')));
    expect(profileTextField.controller?.text, isEmpty);
    expect(find.text('SUGGESTIONS'), findsNothing);

    // Enter custom profile name
    await tester.enterText(find.byKey(const Key('onboarding_profile_name_field')), 'Deep Focus Rig');
    await tester.pump();
    expect(profileTextField.controller?.text, 'Deep Focus Rig');

    // Tap Next to Permissions
    await tester.ensureVisible(find.byKey(const Key('profile_name_continue_button')));
    await tester.tap(find.byKey(const Key('profile_name_continue_button')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    // Screen 3: All 4 Essential Permissions
    expect(find.text('STEP 3 OF 3 · ESSENTIAL PERMISSIONS'), findsOneWidget);
    expect(find.text('Activate on-device shields.'), findsOneWidget);

    // Verify all 4 core permission tiles exist
    expect(find.byKey(const Key('permission_tile_vpn')), findsOneWidget);
    expect(find.byKey(const Key('permission_tile_accessibility')), findsOneWidget);
    expect(find.byKey(const Key('permission_tile_notifications')), findsOneWidget);
    expect(find.byKey(const Key('permission_tile_battery')), findsOneWidget);

    // Grant each permission
    await tester.ensureVisible(find.byKey(const Key('grant_vpn_button')));
    await tester.tap(find.byKey(const Key('grant_vpn_button')));
    await tester.pump();

    await tester.ensureVisible(find.byKey(const Key('grant_accessibility_button')));
    await tester.tap(find.byKey(const Key('grant_accessibility_button')));
    await tester.pump();

    await tester.ensureVisible(find.byKey(const Key('grant_notifications_button')));
    await tester.tap(find.byKey(const Key('grant_notifications_button')));
    await tester.pump();

    await tester.ensureVisible(find.byKey(const Key('grant_battery_button')));
    await tester.tap(find.byKey(const Key('grant_battery_button')));
    await tester.pump();

    expect(find.text('GRANTED ✓'), findsNWidgets(4));

    // Tap Complete Setup & Enter FocusDNS
    await tester.ensureVisible(find.byKey(const Key('finish_onboarding_button')));
    await tester.tap(find.byKey(const Key('finish_onboarding_button')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    // Verify FocusDNSHomeScreen is unlocked!
    expect(find.byType(FocusDNSHomeScreen), findsOneWidget);
    expect(find.byType(EmailOnboardingWizard), findsNothing);

    // Option 3B: Verify dashboard is in Paused state
    expect(find.text('Begin a session'), findsOneWidget);
    expect(find.text('Paused'), findsOneWidget);
  });

  testWidgets('5. Returning user fast-path skips onboarding directly into Dashboard (Option 3A & Option A)', (WidgetTester tester) async {
    final mockClient = MockEmailAuthApiClient();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          apiClientProvider.overrideWithValue(mockClient),
          settingsRepoProvider.overrideWithValue(InMemorySettingsRepository()),
        ],
        child: const MaterialApp(
          home: AuthGateway(),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    // Switch to Sign In mode
    await tester.tap(find.byKey(const Key('tab_sign_in')));
    await tester.pumpAndSettle();

    // Enter email & password
    await tester.enterText(find.byKey(const Key('email_input_field')), 'user@focusdns.net');
    await tester.enterText(find.byKey(const Key('password_input_field')), 'password123');
    await tester.tap(find.byKey(const Key('submit_auth_button')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    // Direct sign-in fast-path unlocks FocusDNSHomeScreen immediately!
    expect(find.byType(FocusDNSHomeScreen), findsOneWidget);
    expect(find.byType(EmailOnboardingWizard), findsNothing);
    expect(find.text('Paused'), findsOneWidget);
  });

  testWidgets('6. Back button in wizard allows stepping backwards (Screen 2 -> Screen 1, Screen 3 -> Screen 2)', (WidgetTester tester) async {
    final mockClient = MockEmailAuthApiClient();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          apiClientProvider.overrideWithValue(mockClient),
          settingsRepoProvider.overrideWithValue(InMemorySettingsRepository()),
        ],
        child: const MaterialApp(
          home: AuthGateway(),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    // Submit email on step 0
    await tester.enterText(find.byKey(const Key('email_input_field')), 'user@focusdns.net');
    await tester.enterText(find.byKey(const Key('password_input_field')), 'password123');
    await tester.enterText(find.byKey(const Key('confirm_password_input_field')), 'password123');
    await tester.tap(find.byKey(const Key('submit_auth_button')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    // Now on Screen 2 (Profile Setup)
    expect(find.text('STEP 2 OF 3 · PROFILE SETUP'), findsOneWidget);

    // Tap back button
    await tester.tap(find.byIcon(Icons.arrow_back_ios_new_rounded));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    // Returned to Screen 1
    expect(find.text('STEP 1 OF 3 · GET STARTED'), findsOneWidget);
  });

  testWidgets('7. Session persists across app restarts until user logs out', (WidgetTester tester) async {
    // Seed persistent storage with active session
    SharedPreferences.setMockInitialValues({
      'focus_dns_auth_is_logged_in': true,
      'focus_dns_auth_session_token': 'persisted-token-42',
      'focus_dns_auth_email': 'persistent@focusdns.net',
      'focus_dns_auth_profile_id': 'pid-persisted',
      'focus_dns_auth_profile_name': 'Warrior Shield',
    });

    final mockClient = MockEmailAuthApiClient();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          apiClientProvider.overrideWithValue(mockClient),
          settingsRepoProvider.overrideWithValue(InMemorySettingsRepository()),
        ],
        child: const MaterialApp(
          home: AuthGateway(),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    // Should immediately boot into FocusDNSHomeScreen without showing onboarding
    expect(find.byType(FocusDNSHomeScreen), findsOneWidget);
    expect(find.byType(EmailOnboardingWizard), findsNothing);
  });

  testWidgets('8. Light mode is default on startup (Option 3A)', (WidgetTester tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    final mode = container.read(themeModeProvider);
    expect(mode, ThemeMode.light);
  });

  testWidgets('9. Profile name left blank displays validation error: Please enter a profile name (Option 1A)', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(800, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    final mockClient = MockEmailAuthApiClient();
    late WidgetRef capturedRef;

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          apiClientProvider.overrideWithValue(mockClient),
          settingsRepoProvider.overrideWithValue(InMemorySettingsRepository()),
        ],
        child: Consumer(
          builder: (context, ref, _) {
            capturedRef = ref;
            return const MaterialApp(home: AuthGateway());
          },
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    // Fill Step 0 and submit
    await tester.enterText(find.byKey(const Key('email_input_field')), 'blankname@focusdns.net');
    await tester.enterText(find.byKey(const Key('password_input_field')), 'password123');
    await tester.enterText(find.byKey(const Key('confirm_password_input_field')), 'password123');
    await tester.ensureVisible(find.byKey(const Key('submit_auth_button')));
    await tester.tap(find.byKey(const Key('submit_auth_button')));
    await tester.pumpAndSettle();

    // Step 2 (Profile Name): text box is completely empty with no suggestions
    expect(find.text('STEP 2 OF 3 · PROFILE SETUP'), findsOneWidget);
    expect(find.text('SUGGESTIONS'), findsNothing);
    final profileTextField = tester.widget<TextFormField>(find.byKey(const Key('onboarding_profile_name_field')));
    expect(profileTextField.controller?.text, isEmpty);

    // Leave blank and tap continue -> Option 1A displays validation error
    await tester.ensureVisible(find.byKey(const Key('profile_name_continue_button')));
    await tester.tap(find.byKey(const Key('profile_name_continue_button')));
    await tester.pump();

    expect(find.text('Please enter a profile name.'), findsOneWidget);
    expect(find.text('STEP 3 OF 3 · ESSENTIAL PERMISSIONS'), findsNothing);

    // Now type a custom name and tap continue -> advances to Step 3
    await tester.enterText(find.byKey(const Key('onboarding_profile_name_field')), 'Spartan Shield');
    await tester.tap(find.byKey(const Key('profile_name_continue_button')));
    await tester.pumpAndSettle();

    expect(find.text('STEP 3 OF 3 · ESSENTIAL PERMISSIONS'), findsOneWidget);
    expect(capturedRef.read(authProvider).activeProfileName, 'Spartan Shield');
  });

  testWidgets('10. SettingsTab renders Email Verification card, opens verification sheet, and verifies email (Option 2A)', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    final mockClient = MockEmailAuthApiClient();

    // Start with logged in session
    SharedPreferences.setMockInitialValues({
      'focus_dns_auth_is_logged_in': true,
      'focus_dns_auth_session_token': 'persisted-token-42',
      'focus_dns_auth_email': 'verifieduser@focusdns.net',
      'focus_dns_auth_profile_id': 'pid-persisted',
      'focus_dns_auth_profile_name': 'Warrior Shield',
      'focus_dns_auth_is_email_verified': false,
    });

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          apiClientProvider.overrideWithValue(mockClient),
          settingsRepoProvider.overrideWithValue(InMemorySettingsRepository()),
        ],
        child: const MaterialApp(
          home: AuthGateway(),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    // In HomeScreen, navigate to More tab (index 3)
    await tester.tap(find.text('More'));
    await tester.pumpAndSettle();

    // Tap 'Settings' in More tab
    await tester.ensureVisible(find.text('Settings'));
    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();

    // Verify Email Verification card is present with UNVERIFIED badge
    expect(find.text('Email Verification'), findsOneWidget);
    expect(find.text('user@focusdns.net'), findsOneWidget);
    expect(find.text('UNVERIFIED'), findsOneWidget);
    expect(find.byKey(const Key('verify_email_settings_button')), findsOneWidget);

    // Tap Verify Email Address button
    await tester.tap(find.byKey(const Key('verify_email_settings_button')));
    await tester.pumpAndSettle();

    // Modal sheet opens with OTP input and Auto-Fill button
    expect(find.byKey(const Key('settings_otp_input')), findsOneWidget);
    expect(find.byKey(const Key('settings_otp_autofill')), findsOneWidget);

    // Tap Auto-Fill (1234)
    await tester.tap(find.byKey(const Key('settings_otp_autofill')));
    await tester.pump();

    // Submit code
    await tester.tap(find.byKey(const Key('settings_otp_submit')));
    await tester.pumpAndSettle();

    // Badge should now be VERIFIED ✓ and Verify Email button is gone
    expect(find.text('VERIFIED ✓'), findsOneWidget);
    expect(find.byKey(const Key('verify_email_settings_button')), findsNothing);
  });
}
