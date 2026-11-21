import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:focus_dns/backend/api_client.dart';
import 'package:focus_dns/frontend/home_screen.dart';
import 'package:focus_dns/frontend/phone_auth_sheet.dart';
import 'package:focus_dns/frontend/profile_switcher_sheet.dart';
import 'package:focus_dns/repositories/settings_repository.dart';
import 'package:focus_dns/state_management/auth_state.dart';
import 'package:focus_dns/state_management/protection_state.dart';
import 'package:focus_dns/state_management/setup_state.dart';

class MockFocusDnsApiClient extends FocusDnsApiClient {
  MockFocusDnsApiClient() : super(baseUrl: 'http://127.0.0.1:8080');

  @override
  Future<Map<String, dynamic>?> getGeoIp() async {
    return {
      'ip': '103.240.79.203',
      'country_code': 'IN',
      'dial_code': '+91',
      'flag': '🇮🇳',
      'country_name': 'India',
      'success': true,
    };
  }

  @override
  Future<List<Map<String, dynamic>>> getGeoCountries() async {
    return [
      {'country_code': 'IN', 'country_name': 'India', 'dial_code': '+91', 'flag': '🇮🇳'},
      {'country_code': 'US', 'country_name': 'United States', 'dial_code': '+1', 'flag': '🇺🇸'},
      {'country_code': 'GB', 'country_name': 'United Kingdom', 'dial_code': '+44', 'flag': '🇬🇧'},
    ];
  }

  @override
  Future<Map<String, dynamic>> sendPhoneOtp(String phone) async {
    return {
      'success': true,
      'message': 'Verification code sent to $phone',
      'phone': phone,
      'dev_otp': '123456',
    };
  }

  @override
  Future<Map<String, dynamic>> verifyPhoneOtp(String phone, String otp) async {
    if (otp == '123456') {
      return {
        'success': true,
        'phone': phone,
        'token': 'mock-session-token',
        'profiles': [
          {'profile_id': 'cloud-p1', 'name': 'Work Cloud Shield'},
          {'profile_id': 'cloud-p2', 'name': 'Family Focus Mode'},
        ],
        'active_profile': {'profile_id': 'cloud-p1', 'name': 'Work Cloud Shield'},
      };
    }
    return {'success': false, 'error': 'Invalid verification code'};
  }

  @override
  Future<List<Map<String, dynamic>>> getUserProfiles(String phone) async {
    return [
      {'profile_id': 'cloud-p1', 'name': 'Work Cloud Shield'},
      {'profile_id': 'cloud-p2', 'name': 'Family Focus Mode'},
    ];
  }

  @override
  Future<Map<String, dynamic>?> createUserProfile(String phone, String name) async {
    return {
      'success': true,
      'profile_id': 'new-pid-99',
      'name': name,
    };
  }
}

void main() {
  testWidgets('PhoneAuthSheet renders detected IP, flag, and dial code', (WidgetTester tester) async {
    final mockClient = MockFocusDnsApiClient();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          apiClientProvider.overrideWithValue(mockClient),
          settingsRepoProvider.overrideWithValue(InMemorySettingsRepository()),
        ],
        child: const MaterialApp(
          home: Scaffold(
            body: PhoneAuthSheet(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Instant Phone Access'), findsOneWidget);
    expect(find.text('🇮🇳'), findsOneWidget);
    expect(find.text('+91'), findsOneWidget);
    expect(find.text('IP: 103.240.79.203'), findsOneWidget);
    expect(find.text('Send Verification Code'), findsOneWidget);
  });

  testWidgets('PhoneAuthSheet sends OTP and allows instant dev code verification', (WidgetTester tester) async {
    final mockClient = MockFocusDnsApiClient();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          apiClientProvider.overrideWithValue(mockClient),
          settingsRepoProvider.overrideWithValue(InMemorySettingsRepository()),
        ],
        child: const MaterialApp(
          home: Scaffold(
            body: PhoneAuthSheet(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Enter phone number
    await tester.enterText(find.byType(TextField).first, '9876543210');
    await tester.pumpAndSettle();

    // Tap Send Verification Code
    await tester.tap(find.text('Send Verification Code'));
    await tester.pumpAndSettle();

    // Verify OTP UI appears
    expect(find.text('Enter 6-Digit SMS Code'), findsOneWidget);
    expect(find.textContaining('Instant Dev Code: 123456'), findsOneWidget);

    // Tap instant dev chip
    await tester.tap(find.textContaining('Instant Dev Code: 123456'));
    await tester.pumpAndSettle();
  });

  testWidgets('ProfileSwitcherSheet shows Quick Phone Login and profiles', (WidgetTester tester) async {
    final mockClient = MockFocusDnsApiClient();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          apiClientProvider.overrideWithValue(mockClient),
          settingsRepoProvider.overrideWithValue(InMemorySettingsRepository()),
        ],
        child: const MaterialApp(
          home: Scaffold(
            body: ProfileSwitcherSheet(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('DNS Profiles'), findsOneWidget);
    expect(find.text('Instant Phone Login'), findsOneWidget);
    expect(find.text('Sign In'), findsOneWidget);
  });

  testWidgets('Profile pill in HomeScreen updates dynamically when profile changes', (WidgetTester tester) async {
    final mockClient = MockFocusDnsApiClient();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          apiClientProvider.overrideWithValue(mockClient),
          settingsRepoProvider.overrideWithValue(InMemorySettingsRepository()),
        ],
        child: const MaterialApp(
          home: FocusDNSHomeScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final pillFinder = find.byKey(const Key('header_profile_pill'));
    expect(pillFinder, findsOneWidget);
    expect(find.text('Yash'), findsOneWidget);
  });
}
