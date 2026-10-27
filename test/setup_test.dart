import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:focus_dns/backend/api_client.dart';
import 'package:focus_dns/frontend/tabs/setup_tab.dart';
import 'package:focus_dns/frontend/theme/wabi_sabi_theme.dart';
import 'package:focus_dns/state_management/providers.dart';

class MockFocusDnsApiClient extends FocusDnsApiClient {
  String mockClientIp;
  String mockLinkedIp;

  MockFocusDnsApiClient({
    this.mockClientIp = '198.51.100.99',
    this.mockLinkedIp = 'No IP linked',
  }) : super(baseUrl: 'http://mock.test');

  @override
  Future<void> ensureToken() async {}

  @override
  Future<Map<String, dynamic>> getSetupDetails() async {
    return {
      'profile_id': 'a1b2c3',
      'name': 'Test Profile',
      'linked_ip': mockLinkedIp,
      'client_ip': mockClientIp,
      'ipv4_endpoints': ['45.90.28.140', '45.90.30.140'],
      'ipv6_endpoints': ['2a07:a8c0::a1b2:c3', '2a07:a8c1::a1b2:c3'],
      'doh_endpoint': 'https://dns.focusdns.net/dns-query/a1b2c3',
      'dot_endpoint': 'a1b2c3.dns.focusdns.net',
      'success': true,
    };
  }

  @override
  Future<String?> detectClientIp() async {
    return mockClientIp;
  }

  @override
  Future<String?> linkIp([String? ip]) async {
    mockLinkedIp = ip ?? mockClientIp;
    return mockLinkedIp;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('SetupState & SetupNotifier Unit Tests', () {
    test('Initializes and loads setup details from API client', () async {
      final mockClient = MockFocusDnsApiClient();
      final notifier = SetupNotifier(client: mockClient);

      // Await async init
      await Future.delayed(const Duration(milliseconds: 50));

      final state = notifier.state;
      expect(state.profileId, 'a1b2c3');
      expect(state.currentClientIp, '198.51.100.99');
      expect(state.linkedIp, 'No IP linked');
      expect(state.dohUrl, 'https://dns.focusdns.net/dns-query/a1b2c3');
      expect(state.dotHostname, 'a1b2c3.dns.focusdns.net');
      expect(state.isMatched, false);
    });

    test('updateLinkedIp binds client IP and marks isMatched as true', () async {
      final mockClient = MockFocusDnsApiClient();
      final notifier = SetupNotifier(client: mockClient);

      await Future.delayed(const Duration(milliseconds: 50));

      final success = await notifier.updateLinkedIp();
      expect(success, true);
      expect(notifier.state.linkedIp, '198.51.100.99');
      expect(notifier.state.currentClientIp, '198.51.100.99');
      expect(notifier.state.isMatched, true);
    });
  });

  group('SetupTab Widget Tests', () {
    testWidgets('Renders all DNS endpoints, DoH, DoT and allows IP linking', (tester) async {
      final mockClient = MockFocusDnsApiClient();

      tester.view.physicalSize = const Size(800, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            apiClientProvider.overrideWithValue(mockClient),
          ],
          child: MaterialApp(
            theme: WabiSabiTheme.lightTheme,
            home: const Scaffold(
              body: SingleChildScrollView(
                child: SetupTab(),
              ),
            ),
          ),
        ),
      );

      // Pump through async init
      await tester.pumpAndSettle();

      // Verify Endpoints card
      expect(find.text('Endpoints'), findsOneWidget);
      expect(find.text('Profile ID'), findsOneWidget);
      expect(find.text('DNS-over-HTTPS (DoH)'), findsOneWidget);
      expect(find.text('DNS-over-TLS (DoT) / Private DNS'), findsOneWidget);
      expect(find.text('IPv4 Anycast'), findsOneWidget);
      expect(find.text('IPv6 Anycast'), findsOneWidget);

      // Verify Linked IP card
      expect(find.text('CURRENT NETWORK IP'), findsOneWidget);
      expect(find.text('198.51.100.99'), findsOneWidget);
      expect(find.text('UNLINKED'), findsOneWidget);

      // Find and tap UPDATE IP button
      final updateBtn = find.text('UPDATE IP');
      expect(updateBtn, findsOneWidget);
      await tester.ensureVisible(updateBtn);
      await tester.tap(updateBtn);
      await tester.pumpAndSettle();

      // Verify update completed: badge becomes ACTIVE MATCH
      expect(find.text('ACTIVE MATCH'), findsOneWidget);
      expect(find.text('IP address linked successfully!'), findsOneWidget);
    });
  });
}
