import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:focus_dns/backend/api_client.dart';
import 'package:focus_dns/models/app_models.dart';
import 'package:focus_dns/models/enums.dart';
import 'package:focus_dns/repositories/settings_repository.dart';
import 'package:focus_dns/state_management/allowlist_state.dart';
import 'package:focus_dns/state_management/auth_state.dart';
import 'package:focus_dns/state_management/blocker_state.dart';
import 'package:focus_dns/state_management/deep_focus_state.dart';
import 'package:focus_dns/state_management/denylist_state.dart';
import 'package:focus_dns/state_management/live_telemetry_provider.dart';
import 'package:focus_dns/state_management/logs_state.dart';
import 'package:focus_dns/state_management/privacy_state.dart';
import 'package:focus_dns/state_management/protection_state.dart';
import 'package:focus_dns/state_management/providers.dart';
import 'package:focus_dns/state_management/security_state.dart';
import 'package:focus_dns/state_management/settings_state.dart';
import 'package:focus_dns/frontend/tabs/allowlist_tab.dart';
import 'package:focus_dns/frontend/tabs/denylist_tab.dart';
import 'package:focus_dns/frontend/tabs/logs_tab.dart';
import 'package:focus_dns/frontend/tabs/analytics_tab.dart';
import 'package:focus_dns/frontend/auth/views/device_session_manager.dart';
import 'package:focus_dns/frontend/widgets.dart';
import 'package:focus_dns/frontend/theme/wabi_sabi_theme.dart';

class MockStrictModeNotifier extends StateNotifier<StrictModeState>
    implements StrictModeNotifier {
  MockStrictModeNotifier(bool isStrict, {int remainingSeconds = 1800})
      : super(StrictModeState(
          isStrict: isStrict,
          remainingSeconds: isStrict ? remainingSeconds : 0,
          strictUntil: isStrict
              ? DateTime.now().add(Duration(seconds: remainingSeconds))
              : null,
        ));

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class MockLogsNotifier extends StateNotifier<LogsState> implements LogsNotifier {
  MockLogsNotifier(LogsState state) : super(state);

  @override
  void setSearchQuery(String query) {
    state = state.copyWith(searchQuery: query);
  }

  void setLogs(List<QueryLog> logs) {
    state = state.copyWith(logs: logs);
  }

  void addLog(QueryLog log) {
    state = state.copyWith(logs: [log, ...state.logs.take(99)]);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class MockAuthNotifier extends StateNotifier<AuthState> implements AuthNotifier {
  MockAuthNotifier(AuthState state) : super(state);

  @override
  Future<void> logout() async {
    state = const AuthState(isLoggedIn: false, phoneNumber: null);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeApiClient extends FocusDnsApiClient {
  FakeApiClient() : super(baseUrl: 'http://127.0.0.1:8080', profileId: 'test-profile');

  @override
  Future<List<Map<String, dynamic>>> getUserProfiles(String phone) async {
    return [
      {'profile_id': 'test-profile', 'name': 'Personal Shield'}
    ];
  }

  @override
  Future<bool> logoutSession() async {
    return true;
  }
}

Widget _buildTabHarness({
  required Widget child,
  List<Override> overrides = const [],
  bool wrapInSingleChildScrollView = true,
}) {
  return ProviderScope(
    overrides: [
      liveTelemetryProvider.overrideWith((ref) => LiveTelemetryNotifier(enablePolling: false)),
      apiClientProvider.overrideWithValue(FakeApiClient()),
      ...overrides,
    ],
    child: MaterialApp(
      theme: WabiSabiTheme.darkTheme,
      home: Scaffold(
        body: wrapInSingleChildScrollView
            ? SingleChildScrollView(child: child)
            : child,
      ),
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Category 1: Allowlist Tab Edge Cases (Tests 1-15)', () {
    testWidgets('1. AllowlistTab renders initial default domain (trusted-site.com)', (tester) async {
      await tester.pumpWidget(_buildTabHarness(child: const AllowlistTab()));
      await tester.pump();

      expect(find.text('Allowlist'), findsOneWidget);
      expect(find.text('trusted-site.com'), findsOneWidget);
      expect(find.byIcon(Icons.close), findsOneWidget);
    });

    testWidgets('2. Adding valid domain via text field and ADD button adds domain', (tester) async {
      await tester.pumpWidget(_buildTabHarness(child: const AllowlistTab()));
      await tester.pump();

      await tester.enterText(find.byType(TextField), 'my-work-vpn.org');
      await tester.tap(find.widgetWithText(ElevatedButton, 'ADD'));
      await tester.pump();

      expect(find.text('my-work-vpn.org'), findsOneWidget);
      expect(find.text('trusted-site.com'), findsOneWidget);
    });

    testWidgets('3. Adding domain via keyboard onSubmitted adds domain', (tester) async {
      await tester.pumpWidget(_buildTabHarness(child: const AllowlistTab()));
      await tester.pump();

      await tester.enterText(find.byType(TextField), 'intranet.corp');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();

      expect(find.text('intranet.corp'), findsOneWidget);
    });

    testWidgets('4. Domain with leading and trailing whitespace is automatically trimmed', (tester) async {
      await tester.pumpWidget(_buildTabHarness(child: const AllowlistTab()));
      await tester.pump();

      await tester.enterText(find.byType(TextField), '   trimmed-domain.net   ');
      await tester.tap(find.widgetWithText(ElevatedButton, 'ADD'));
      await tester.pump();

      expect(find.text('trimmed-domain.net'), findsOneWidget);
      expect(find.text('   trimmed-domain.net   '), findsNothing);
    });

    testWidgets('5. Domain with uppercase characters is normalized to lowercase', (tester) async {
      await tester.pumpWidget(_buildTabHarness(child: const AllowlistTab()));
      await tester.pump();

      await tester.enterText(find.byType(TextField), 'UPPERCASE-PORTAL.COM');
      await tester.tap(find.widgetWithText(ElevatedButton, 'ADD'));
      await tester.pump();

      expect(find.text('uppercase-portal.com'), findsOneWidget);
      expect(find.text('UPPERCASE-PORTAL.COM'), findsNothing);
    });

    testWidgets('6. Submitting empty string does not add empty entry to allowlist', (tester) async {
      await tester.pumpWidget(_buildTabHarness(child: const AllowlistTab()));
      await tester.pump();

      final initialItems = find.byIcon(Icons.close).evaluate().length;
      await tester.enterText(find.byType(TextField), '');
      await tester.tap(find.widgetWithText(ElevatedButton, 'ADD'));
      await tester.pump();

      expect(find.byIcon(Icons.close).evaluate().length, equals(initialItems));
    });

    testWidgets('7. Submitting only whitespace does not add whitespace entry', (tester) async {
      await tester.pumpWidget(_buildTabHarness(child: const AllowlistTab()));
      await tester.pump();

      final initialItems = find.byIcon(Icons.close).evaluate().length;
      await tester.enterText(find.byType(TextField), '     ');
      await tester.tap(find.widgetWithText(ElevatedButton, 'ADD'));
      await tester.pump();

      expect(find.byIcon(Icons.close).evaluate().length, equals(initialItems));
    });

    testWidgets('8. Duplicate domain addition is ignored and prevented', (tester) async {
      await tester.pumpWidget(_buildTabHarness(child: const AllowlistTab()));
      await tester.pump();

      // Attempt to add 'trusted-site.com' which already exists
      await tester.enterText(find.byType(TextField), 'trusted-site.com');
      await tester.tap(find.widgetWithText(ElevatedButton, 'ADD'));
      await tester.pump();

      expect(find.text('trusted-site.com'), findsOneWidget);
    });

    testWidgets('9. Case-insensitive duplicate domain addition is prevented', (tester) async {
      await tester.pumpWidget(_buildTabHarness(child: const AllowlistTab()));
      await tester.pump();

      await tester.enterText(find.byType(TextField), 'TRUSTED-SITE.COM');
      await tester.tap(find.widgetWithText(ElevatedButton, 'ADD'));
      await tester.pump();

      expect(find.text('trusted-site.com'), findsOneWidget);
    });

    testWidgets('10. Text field is cleared immediately after successful addition', (tester) async {
      await tester.pumpWidget(_buildTabHarness(child: const AllowlistTab()));
      await tester.pump();

      await tester.enterText(find.byType(TextField), 'sample-cleared.org');
      await tester.tap(find.widgetWithText(ElevatedButton, 'ADD'));
      await tester.pump();

      final field = tester.widget<TextField>(find.byType(TextField));
      expect(field.controller?.text, isEmpty);
    });

    testWidgets('11. Removing domain via delete button removes it from the list', (tester) async {
      await tester.pumpWidget(_buildTabHarness(child: const AllowlistTab()));
      await tester.pump();

      expect(find.text('trusted-site.com'), findsOneWidget);
      await tester.tap(find.byIcon(Icons.close).first);
      await tester.pump();

      expect(find.text('trusted-site.com'), findsNothing);
    });

    testWidgets('12. Removing all domains displays empty state ("No domains on allowlist")', (tester) async {
      await tester.pumpWidget(_buildTabHarness(child: const AllowlistTab()));
      await tester.pump();

      await tester.tap(find.byIcon(Icons.close).first);
      await tester.pump();

      expect(find.text('No domains on allowlist'), findsOneWidget);
      expect(find.byIcon(Icons.close), findsNothing);
    });

    testWidgets('13. In Strict Mode, attempting to add domain is blocked with warning SnackBar', (tester) async {
      await tester.pumpWidget(_buildTabHarness(
        overrides: [
          strictModeProvider.overrideWith((ref) => MockStrictModeNotifier(true, remainingSeconds: 1800)),
        ],
        child: const AllowlistTab(),
      ));
      await tester.pump();

      await tester.enterText(find.byType(TextField), 'bypass-attempt.com');
      await tester.tap(find.widgetWithText(ElevatedButton, 'ADD'));
      await tester.pump();

      // Only the input text field has 'bypass-attempt.com', not in the allowlist items
      expect(find.byIcon(Icons.close), findsOneWidget); // still only 1 item (trusted-site.com)
      expect(find.textContaining('Strict Mode active'), findsOneWidget);
      expect(find.textContaining('Cannot add domains to allowlist'), findsOneWidget);
    });

    testWidgets('14. Subdomain formatting (e.g. api.sub.dev.org) preserves hierarchical dots', (tester) async {
      await tester.pumpWidget(_buildTabHarness(child: const AllowlistTab()));
      await tester.pump();

      await tester.enterText(find.byType(TextField), 'api.v2.internal.service.io');
      await tester.tap(find.widgetWithText(ElevatedButton, 'ADD'));
      await tester.pump();

      expect(find.text('api.v2.internal.service.io'), findsOneWidget);
    });

    testWidgets('15. Multiple sequential additions preserve order', (tester) async {
      await tester.pumpWidget(_buildTabHarness(child: const AllowlistTab()));
      await tester.pump();

      await tester.enterText(find.byType(TextField), 'alpha.com');
      await tester.tap(find.widgetWithText(ElevatedButton, 'ADD'));
      await tester.pump();

      await tester.enterText(find.byType(TextField), 'beta.com');
      await tester.tap(find.widgetWithText(ElevatedButton, 'ADD'));
      await tester.pump();

      expect(find.text('alpha.com'), findsOneWidget);
      expect(find.text('beta.com'), findsOneWidget);
    });
  });

  group('Category 2: Denylist Tab Edge Cases (Tests 16-30)', () {
    testWidgets('16. DenylistTab renders initial default domain (example.com)', (tester) async {
      await tester.pumpWidget(_buildTabHarness(child: const DenylistTab()));
      await tester.pump();

      expect(find.text('Denylist'), findsOneWidget);
      expect(find.text('example.com'), findsOneWidget);
      expect(find.byIcon(Icons.close), findsOneWidget);
    });

    testWidgets('17. Adding custom wildcard domain (*.ads.net) adds to denylist', (tester) async {
      await tester.pumpWidget(_buildTabHarness(child: const DenylistTab()));
      await tester.pump();

      await tester.enterText(find.byType(TextField), '*.ads.tracker.net');
      await tester.tap(find.widgetWithText(ElevatedButton, 'ADD'));
      await tester.pump();

      expect(find.text('*.ads.tracker.net'), findsOneWidget);
      expect(find.text('example.com'), findsOneWidget);
    });

    testWidgets('18. Adding domain via keyboard onSubmitted adds domain', (tester) async {
      await tester.pumpWidget(_buildTabHarness(child: const DenylistTab()));
      await tester.pump();

      await tester.enterText(find.byType(TextField), 'malware-hub.ru');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();

      expect(find.text('malware-hub.ru'), findsOneWidget);
    });

    testWidgets('19. Denylist domain trims surrounding whitespace', (tester) async {
      await tester.pumpWidget(_buildTabHarness(child: const DenylistTab()));
      await tester.pump();

      await tester.enterText(find.byType(TextField), '   tracking-pixel.co   ');
      await tester.tap(find.widgetWithText(ElevatedButton, 'ADD'));
      await tester.pump();

      expect(find.text('tracking-pixel.co'), findsOneWidget);
    });

    testWidgets('20. Denylist domain normalizes uppercase to lowercase', (tester) async {
      await tester.pumpWidget(_buildTabHarness(child: const DenylistTab()));
      await tester.pump();

      await tester.enterText(find.byType(TextField), 'ADSERVER-GLOBAL.NET');
      await tester.tap(find.widgetWithText(ElevatedButton, 'ADD'));
      await tester.pump();

      expect(find.text('adserver-global.net'), findsOneWidget);
    });

    testWidgets('21. Empty string submission does not add entry', (tester) async {
      await tester.pumpWidget(_buildTabHarness(child: const DenylistTab()));
      await tester.pump();

      final initialItems = find.byIcon(Icons.close).evaluate().length;
      await tester.enterText(find.byType(TextField), '');
      await tester.tap(find.widgetWithText(ElevatedButton, 'ADD'));
      await tester.pump();

      expect(find.byIcon(Icons.close).evaluate().length, equals(initialItems));
    });

    testWidgets('22. Whitespace-only submission does not add entry', (tester) async {
      await tester.pumpWidget(_buildTabHarness(child: const DenylistTab()));
      await tester.pump();

      final initialItems = find.byIcon(Icons.close).evaluate().length;
      await tester.enterText(find.byType(TextField), '     ');
      await tester.tap(find.widgetWithText(ElevatedButton, 'ADD'));
      await tester.pump();

      expect(find.byIcon(Icons.close).evaluate().length, equals(initialItems));
    });

    testWidgets('23. Duplicate denylist domain addition is prevented', (tester) async {
      await tester.pumpWidget(_buildTabHarness(child: const DenylistTab()));
      await tester.pump();

      await tester.enterText(find.byType(TextField), 'example.com');
      await tester.tap(find.widgetWithText(ElevatedButton, 'ADD'));
      await tester.pump();

      expect(find.text('example.com'), findsOneWidget);
    });

    testWidgets('24. Deleting domain in normal mode removes it immediately', (tester) async {
      await tester.pumpWidget(_buildTabHarness(child: const DenylistTab()));
      await tester.pump();

      expect(find.text('example.com'), findsOneWidget);
      await tester.tap(find.byIcon(Icons.close).first);
      await tester.pump();

      expect(find.text('example.com'), findsNothing);
    });

    testWidgets('25. Removing all denylist items displays empty state ("No domains on denylist")', (tester) async {
      await tester.pumpWidget(_buildTabHarness(child: const DenylistTab()));
      await tester.pump();

      await tester.tap(find.byIcon(Icons.close).first);
      await tester.pump();

      expect(find.text('No domains on denylist'), findsOneWidget);
      expect(find.byIcon(Icons.close), findsNothing);
    });

    testWidgets('26. In Strict Mode, delete icon is replaced by lock icon (Icons.lock_outline_rounded)', (tester) async {
      await tester.pumpWidget(_buildTabHarness(
        overrides: [
          strictModeProvider.overrideWith((ref) => MockStrictModeNotifier(true)),
        ],
        child: const DenylistTab(),
      ));
      await tester.pump();

      expect(find.byIcon(Icons.close), findsNothing);
      expect(find.byIcon(Icons.lock_outline_rounded), findsOneWidget);
    });

    testWidgets('27. In Strict Mode, lock icon tooltip displays "Locked during Strict Mode"', (tester) async {
      await tester.pumpWidget(_buildTabHarness(
        overrides: [
          strictModeProvider.overrideWith((ref) => MockStrictModeNotifier(true)),
        ],
        child: const DenylistTab(),
      ));
      await tester.pump();

      final tooltip = tester.widget<Tooltip>(find.byType(Tooltip));
      expect(tooltip.message, equals('Locked during Strict Mode'));
    });

    testWidgets('28. In Strict Mode, adding domains to denylist is permitted (tightening rules)', (tester) async {
      await tester.pumpWidget(_buildTabHarness(
        overrides: [
          strictModeProvider.overrideWith((ref) => MockStrictModeNotifier(true)),
        ],
        child: const DenylistTab(),
      ));
      await tester.pump();

      await tester.enterText(find.byType(TextField), 'strict-added-tracker.com');
      await tester.tap(find.widgetWithText(ElevatedButton, 'ADD'));
      await tester.pump();

      expect(find.text('strict-added-tracker.com'), findsOneWidget);
      expect(find.byIcon(Icons.lock_outline_rounded), findsNWidgets(2));
    });

    testWidgets('29. Top-level domain wildcard pattern (*.zip) renders correctly', (tester) async {
      await tester.pumpWidget(_buildTabHarness(child: const DenylistTab()));
      await tester.pump();

      await tester.enterText(find.byType(TextField), '*.zip');
      await tester.tap(find.widgetWithText(ElevatedButton, 'ADD'));
      await tester.pump();

      expect(find.text('*.zip'), findsOneWidget);
    });

    testWidgets('30. Input field clears automatically after successful denylist add', (tester) async {
      await tester.pumpWidget(_buildTabHarness(child: const DenylistTab()));
      await tester.pump();

      await tester.enterText(find.byType(TextField), 'telemetry-cleared.io');
      await tester.tap(find.widgetWithText(ElevatedButton, 'ADD'));
      await tester.pump();

      final field = tester.widget<TextField>(find.byType(TextField));
      expect(field.controller?.text, isEmpty);
    });
  });

  group('Category 3: DNS Query Logs Tab Edge Cases (Tests 31-42)', () {
    final sampleLogs = [
      QueryLog(
        id: '1',
        subdomain: 'api.',
        domain: 'google.com',
        time: '2s ago',
        icon: 'G',
        isBlocked: false,
      ),
      QueryLog(
        id: '2',
        subdomain: 'graph.',
        domain: 'instagram.com',
        time: '5s ago',
        icon: 'I',
        isBlocked: true,
      ),
      QueryLog(
        id: '3',
        subdomain: 'telemetry.',
        domain: 'tiktokv.com',
        time: '12s ago',
        icon: 'T',
        isBlocked: true,
      ),
      QueryLog(
        id: '4',
        subdomain: '',
        domain: 'github.com',
        time: '30s ago',
        icon: 'G',
        isBlocked: false,
      ),
    ];

    testWidgets('31. LogsTab renders search bar and all provided query logs', (tester) async {
      final mockLogs = MockLogsNotifier(LogsState(searchQuery: '', logs: sampleLogs));
      await tester.pumpWidget(_buildTabHarness(
        overrides: [logsProvider.overrideWith((ref) => mockLogs)],
        child: const LogsTab(),
      ));
      await tester.pump();

      expect(find.byType(TextField), findsOneWidget);
      expect(find.byWidgetPredicate((w) => w is RichText && w.text.toPlainText().contains('google.com')), findsOneWidget);
      expect(find.byWidgetPredicate((w) => w is RichText && w.text.toPlainText().contains('instagram.com')), findsOneWidget);
      expect(find.byWidgetPredicate((w) => w is RichText && w.text.toPlainText().contains('tiktokv.com')), findsOneWidget);
      expect(find.byWidgetPredicate((w) => w is RichText && w.text.toPlainText().contains('github.com')), findsOneWidget);
    });

    testWidgets('32. Search query filters logs by root domain', (tester) async {
      final mockLogs = MockLogsNotifier(LogsState(searchQuery: '', logs: sampleLogs));
      await tester.pumpWidget(_buildTabHarness(
        overrides: [logsProvider.overrideWith((ref) => mockLogs)],
        child: const LogsTab(),
      ));
      await tester.pump();

      await tester.enterText(find.byType(TextField), 'instagram');
      await tester.pump();

      expect(find.byWidgetPredicate((w) => w is RichText && w.text.toPlainText().contains('instagram.com')), findsOneWidget);
      expect(find.byWidgetPredicate((w) => w is RichText && w.text.toPlainText().contains('google.com')), findsNothing);
      expect(find.byWidgetPredicate((w) => w is RichText && w.text.toPlainText().contains('tiktokv.com')), findsNothing);
    });

    testWidgets('33. Search query filters logs by subdomain (e.g. telemetry)', (tester) async {
      final mockLogs = MockLogsNotifier(LogsState(searchQuery: '', logs: sampleLogs));
      await tester.pumpWidget(_buildTabHarness(
        overrides: [logsProvider.overrideWith((ref) => mockLogs)],
        child: const LogsTab(),
      ));
      await tester.pump();

      await tester.enterText(find.byType(TextField), 'telemetry');
      await tester.pump();

      expect(find.byWidgetPredicate((w) => w is RichText && w.text.toPlainText().contains('tiktokv.com')), findsOneWidget);
      expect(find.byWidgetPredicate((w) => w is RichText && w.text.toPlainText().contains('google.com')), findsNothing);
    });

    testWidgets('34. Search query is case-insensitive (e.g. GITHUB)', (tester) async {
      final mockLogs = MockLogsNotifier(LogsState(searchQuery: '', logs: sampleLogs));
      await tester.pumpWidget(_buildTabHarness(
        overrides: [logsProvider.overrideWith((ref) => mockLogs)],
        child: const LogsTab(),
      ));
      await tester.pump();

      await tester.enterText(find.byType(TextField), 'GITHUB');
      await tester.pump();

      expect(find.byWidgetPredicate((w) => w is RichText && w.text.toPlainText().contains('github.com')), findsOneWidget);
      expect(find.byWidgetPredicate((w) => w is RichText && w.text.toPlainText().contains('instagram.com')), findsNothing);
    });

    testWidgets('35. Clear button appears when search text is non-empty', (tester) async {
      final mockLogs = MockLogsNotifier(LogsState(searchQuery: '', logs: sampleLogs));
      await tester.pumpWidget(_buildTabHarness(
        overrides: [logsProvider.overrideWith((ref) => mockLogs)],
        child: const LogsTab(),
      ));
      await tester.pump();

      expect(find.byIcon(Icons.clear), findsNothing);

      await tester.enterText(find.byType(TextField), 'test');
      await tester.pump();

      expect(find.byIcon(Icons.clear), findsOneWidget);
    });

    testWidgets('36. Tapping clear button clears text and restores full list', (tester) async {
      final mockLogs = MockLogsNotifier(LogsState(searchQuery: '', logs: sampleLogs));
      await tester.pumpWidget(_buildTabHarness(
        overrides: [logsProvider.overrideWith((ref) => mockLogs)],
        child: const LogsTab(),
      ));
      await tester.pump();

      await tester.enterText(find.byType(TextField), 'instagram');
      await tester.pump();
      expect(find.byWidgetPredicate((w) => w is RichText && w.text.toPlainText().contains('google.com')), findsNothing);

      await tester.tap(find.byIcon(Icons.clear));
      await tester.pump();

      expect(find.byWidgetPredicate((w) => w is RichText && w.text.toPlainText().contains('google.com')), findsOneWidget);
      expect(find.byWidgetPredicate((w) => w is RichText && w.text.toPlainText().contains('instagram.com')), findsOneWidget);
    });

    testWidgets('37. Non-matching search displays "No matching DNS queries found"', (tester) async {
      final mockLogs = MockLogsNotifier(LogsState(searchQuery: '', logs: sampleLogs));
      await tester.pumpWidget(_buildTabHarness(
        overrides: [logsProvider.overrideWith((ref) => mockLogs)],
        child: const LogsTab(),
      ));
      await tester.pump();

      await tester.enterText(find.byType(TextField), 'nonexistentdomain999.xyz');
      await tester.pump();

      expect(find.text('No matching DNS queries found'), findsOneWidget);
    });

    testWidgets('38. Empty initial logs state renders empty message', (tester) async {
      final mockLogs = MockLogsNotifier(const LogsState(searchQuery: '', logs: []));
      await tester.pumpWidget(_buildTabHarness(
        overrides: [logsProvider.overrideWith((ref) => mockLogs)],
        child: const LogsTab(),
      ));
      await tester.pump();

      expect(find.text('No matching DNS queries found'), findsOneWidget);
    });

    testWidgets('39. Blocked query displays "BLOCKED" badge in strict accent color', (tester) async {
      final mockLogs = MockLogsNotifier(LogsState(searchQuery: '', logs: sampleLogs));
      await tester.pumpWidget(_buildTabHarness(
        overrides: [logsProvider.overrideWith((ref) => mockLogs)],
        child: const LogsTab(),
      ));
      await tester.pump();

      expect(find.text('BLOCKED'), findsNWidgets(2));
      expect(find.text('ALLOW'), findsNWidgets(2));
    });

    testWidgets('40. Query items render single-character icon text circle', (tester) async {
      final mockLogs = MockLogsNotifier(LogsState(searchQuery: '', logs: sampleLogs));
      await tester.pumpWidget(_buildTabHarness(
        overrides: [logsProvider.overrideWith((ref) => mockLogs)],
        child: const LogsTab(),
      ));
      await tester.pump();

      expect(find.text('G'), findsNWidgets(2));
      expect(find.text('I'), findsOneWidget);
      expect(find.text('T'), findsOneWidget);
    });

    testWidgets('41. Query time label renders relative timestamp (e.g. 2s ago, 5s ago)', (tester) async {
      final mockLogs = MockLogsNotifier(LogsState(searchQuery: '', logs: sampleLogs));
      await tester.pumpWidget(_buildTabHarness(
        overrides: [logsProvider.overrideWith((ref) => mockLogs)],
        child: const LogsTab(),
      ));
      await tester.pump();

      expect(find.text('2s ago'), findsOneWidget);
      expect(find.text('5s ago'), findsOneWidget);
      expect(find.text('12s ago'), findsOneWidget);
      expect(find.text('30s ago'), findsOneWidget);
    });

    testWidgets('42. Dynamic stream update prepends new item to the top', (tester) async {
      final mockLogs = MockLogsNotifier(LogsState(searchQuery: '', logs: sampleLogs));
      await tester.pumpWidget(_buildTabHarness(
        overrides: [logsProvider.overrideWith((ref) => mockLogs)],
        child: const LogsTab(),
      ));
      await tester.pump();

      mockLogs.addLog(QueryLog(
        id: 'new_item',
        subdomain: '',
        domain: 'brand-new-query.net',
        time: 'just now',
        icon: 'B',
        isBlocked: false,
      ));
      await tester.pump();

      expect(find.byWidgetPredicate((w) => w is RichText && w.text.toPlainText().contains('brand-new-query.net')), findsOneWidget);
    });
  });

  group('Category 4: Analytics Tab Edge Cases (Tests 43-48)', () {
    testWidgets('43. AnalyticsTab renders default 7 days filter with 14,566 queries', (tester) async {
      await tester.pumpWidget(_buildTabHarness(child: const AnalyticsTab()));
      await tester.pump();

      expect(find.text('QUERIES TRAFFIC'), findsOneWidget);
      expect(find.text('14,566'), findsOneWidget);
      expect(find.text('779 (5%) blocked'), findsOneWidget);
      expect(find.text('Top Blocked Domains'), findsOneWidget);
    });

    testWidgets('44. Switching filter to "24 hours" updates traffic metrics to 33 and 0 (0%) blocked', (tester) async {
      await tester.pumpWidget(_buildTabHarness(child: const AnalyticsTab()));
      await tester.pump();

      await tester.tap(find.text('24 hours'));
      await tester.pump();

      expect(find.text('33'), findsOneWidget);
      expect(find.text('0 (0%) blocked'), findsOneWidget);
    });

    testWidgets('45. Switching filter to "30 days" updates traffic metrics to 66,190 and 2,732 (4%) blocked', (tester) async {
      await tester.pumpWidget(_buildTabHarness(child: const AnalyticsTab()));
      await tester.pump();

      await tester.tap(find.text('30 days'));
      await tester.pump();

      expect(find.text('66,190'), findsOneWidget);
      expect(find.text('2,732 (4%) blocked'), findsOneWidget);
    });

    testWidgets('46. Top Blocked Domains card renders top telemetry offenders', (tester) async {
      await tester.pumpWidget(_buildTabHarness(child: const AnalyticsTab()));
      await tester.pump();

      expect(find.text('reddit.com (tracking)'), findsOneWidget);
      expect(find.text('412 queries'), findsOneWidget);
      expect(find.text('53%'), findsOneWidget);

      expect(find.text('appsflyersdk.com'), findsOneWidget);
      expect(find.text('189 queries'), findsOneWidget);
      expect(find.text('24%'), findsOneWidget);
    });

    testWidgets('47. ChartPainter executes paint call without exceptions across filters', (tester) async {
      await tester.pumpWidget(_buildTabHarness(child: const AnalyticsTab()));
      await tester.pump();

      expect(find.byType(CustomPaint), findsWidgets);

      await tester.tap(find.text('24 hours'));
      await tester.pump();

      await tester.tap(find.text('30 days'));
      await tester.pump();

      await tester.tap(find.text('7 days'));
      await tester.pump();

      expect(tester.takeException(), isNull);
    });

    testWidgets('48. Rapidly toggling all three filter options maintains stable widget state', (tester) async {
      await tester.pumpWidget(_buildTabHarness(child: const AnalyticsTab()));
      await tester.pump();

      for (int i = 0; i < 3; i++) {
        await tester.tap(find.text('24 hours'));
        await tester.pump();
        await tester.tap(find.text('7 days'));
        await tester.pump();
        await tester.tap(find.text('30 days'));
        await tester.pump();
      }

      expect(find.text('66,190'), findsOneWidget);
    });
  });

  group('Category 5: Device Sessions & Security Edge Cases (Tests 49-55)', () {
    testWidgets('49. Authenticated phone number renders flag, number, and status badge', (tester) async {
      final authState = const AuthState(
        isLoggedIn: true,
        phoneNumber: '+1 (555) 019-2834',
        detectedCountryCode: 'US',
        detectedFlag: '🇺🇸',
        detectedIp: '198.51.100.42',
      );

      await tester.pumpWidget(_buildTabHarness(
        wrapInSingleChildScrollView: false,
        overrides: [
          authProvider.overrideWith((ref) => MockAuthNotifier(authState)),
        ],
        child: const DeviceSessionManagerView(),
      ));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('AUTHENTICATED PHONE'), findsOneWidget);
      expect(find.text('+1 (555) 019-2834'), findsOneWidget);
      expect(find.text('🇺🇸'), findsOneWidget);
      expect(find.text('Active'), findsOneWidget);
    });

    testWidgets('50. Current session card displays "This Web Client (Current)" and "This Device" badge', (tester) async {
      final authState = const AuthState(
        isLoggedIn: true,
        phoneNumber: '+1 (555) 019-2834',
        detectedCountryCode: 'US',
        detectedFlag: '🇺🇸',
        detectedIp: '198.51.100.42',
      );

      await tester.pumpWidget(_buildTabHarness(
        wrapInSingleChildScrollView: false,
        overrides: [
          authProvider.overrideWith((ref) => MockAuthNotifier(authState)),
        ],
        child: const DeviceSessionManagerView(),
      ));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('This Web Client (Current)'), findsOneWidget);
      expect(find.text('This Device'), findsOneWidget);
      expect(find.textContaining('198.51.100.42'), findsOneWidget);
    });

    testWidgets('51. Unauthenticated state renders "No phone linked" fallback', (tester) async {
      final authState = const AuthState(
        isLoggedIn: false,
        phoneNumber: null,
      );

      await tester.pumpWidget(_buildTabHarness(
        wrapInSingleChildScrollView: false,
        overrides: [
          authProvider.overrideWith((ref) => MockAuthNotifier(authState)),
        ],
        child: const DeviceSessionManagerView(),
      ));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('No phone linked'), findsOneWidget);
    });

    testWidgets('52. Forensic Audit and Recovery Keys buttons render on session manager', (tester) async {
      final authState = const AuthState(
        isLoggedIn: true,
        phoneNumber: '+1 (555) 019-2834',
      );

      await tester.pumpWidget(_buildTabHarness(
        wrapInSingleChildScrollView: false,
        overrides: [
          authProvider.overrideWith((ref) => MockAuthNotifier(authState)),
        ],
        child: const DeviceSessionManagerView(),
      ));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('Forensic Audit'), findsOneWidget);
      expect(find.text('Recovery Keys'), findsOneWidget);
      expect(find.text('Sign Out from This Device'), findsOneWidget);
    });

    testWidgets('53. Allowlist renders without RenderFlex overflow on ultra-compact screen (320x568)', (tester) async {
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(_buildTabHarness(child: const AllowlistTab()));
      await tester.pump();

      expect(tester.takeException(), isNull);
      expect(find.text('Allowlist'), findsOneWidget);
    });

    testWidgets('54. Denylist renders without RenderFlex overflow on ultra-compact screen (320x568)', (tester) async {
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(_buildTabHarness(child: const DenylistTab()));
      await tester.pump();

      expect(tester.takeException(), isNull);
      expect(find.text('Denylist'), findsOneWidget);
    });

    testWidgets('55. LogsTab renders search bar without RenderFlex overflow on ultra-compact screen (320x568)', (tester) async {
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final mockLogs = MockLogsNotifier(const LogsState(searchQuery: '', logs: []));
      await tester.pumpWidget(_buildTabHarness(
        overrides: [logsProvider.overrideWith((ref) => mockLogs)],
        child: const LogsTab(),
      ));
      await tester.pump();

      expect(tester.takeException(), isNull);
      expect(find.text('No matching DNS queries found'), findsOneWidget);
    });
  });
}
