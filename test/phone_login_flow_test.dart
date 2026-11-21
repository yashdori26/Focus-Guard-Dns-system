import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:focus_dns/backend/api_client.dart';
import 'package:focus_dns/frontend/auth/auth_gateway.dart';
import 'package:focus_dns/frontend/auth/phone_auth_screen.dart';
import 'package:focus_dns/frontend/home_screen.dart';
import 'package:focus_dns/repositories/settings_repository.dart';
import 'package:focus_dns/services/auth_storage_service.dart';
import 'package:focus_dns/state_management/auth_state.dart';
import 'package:focus_dns/state_management/protection_state.dart';
import 'package:focus_dns/state_management/setup_state.dart';
import 'package:shared_preferences/shared_preferences.dart';

class MockPersistentApiClient extends FocusDnsApiClient {
  MockPersistentApiClient() : super(baseUrl: 'http://127.0.0.1:8080');

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
  Future<List<Map<String, dynamic>>> getGeoCountries() async => [];

  @override
  Future<Map<String, dynamic>> verifySession(String token) async {
    if (token == 'valid-persistent-session-token') {
      return {
        'success': true,
        'phone': '+919999888877',
        'active_profile_id': 'cloud-persisted-p1',
        'active_profile_name': 'Executive Shield',
        'profiles': [
          {'profile_id': 'cloud-persisted-p1', 'name': 'Executive Shield'},
        ],
      };
    }
    return {'success': false, 'error': 'Expired session'};
  }

  @override
  Future<bool> logoutSession() async => true;
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('App stays logged in on cold boot if valid persistent session exists', (WidgetTester tester) async {
    final mockClient = MockPersistentApiClient();

    // Pre-populate persistent session in SharedPreferences
    await AuthStorageService.saveSession(
      token: 'valid-persistent-session-token',
      phone: '+919999888877',
      profileId: 'cloud-persisted-p1',
      profileName: 'Executive Shield',
      countryCode: 'IN',
      dialCode: '+91',
      flag: '🇮🇳',
    );

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

    // Must jump directly to FocusDNSHomeScreen with persisted profile!
    expect(find.byType(FocusDNSHomeScreen), findsOneWidget);
    expect(find.byType(PhoneAuthScreen), findsNothing);
    expect(find.text('Executive Shield'), findsOneWidget);
  });

  testWidgets('Explicit logout clears session and locks app back to PhoneAuthScreen', (WidgetTester tester) async {
    final mockClient = MockPersistentApiClient();

    // Pre-populate persistent session
    await AuthStorageService.saveSession(
      token: 'valid-persistent-session-token',
      phone: '+919999888877',
      profileId: 'cloud-persisted-p1',
      profileName: 'Executive Shield',
    );

    late WidgetRef containerRef;

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          apiClientProvider.overrideWithValue(mockClient),
          settingsRepoProvider.overrideWithValue(InMemorySettingsRepository()),
        ],
        child: Consumer(
          builder: (context, ref, _) {
            containerRef = ref;
            return const MaterialApp(
              home: AuthGateway(),
            );
          },
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.byType(FocusDNSHomeScreen), findsOneWidget);

    // Trigger explicit user logout
    await containerRef.read(authProvider.notifier).logout();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    // Must now display PhoneAuthScreen
    expect(find.byType(FocusDNSHomeScreen), findsNothing);
    expect(find.byType(PhoneAuthScreen), findsOneWidget);
    expect(find.text('Enter Mobile Number'), findsOneWidget);

    // Verify storage was cleared
    final storageData = await AuthStorageService.loadSession();
    expect(storageData['is_logged_in'], 'false');
  });
}
