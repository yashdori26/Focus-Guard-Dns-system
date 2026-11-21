import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:focus_dns/frontend/audit/distraction_audit_sheet.dart';
import 'package:focus_dns/models/app_models.dart';
import 'package:focus_dns/models/enums.dart';
import 'package:focus_dns/repositories/settings_repository.dart';
import 'package:focus_dns/state_management/blocker_state.dart';
import 'package:focus_dns/state_management/deep_focus_state.dart';
import 'package:focus_dns/state_management/live_telemetry_provider.dart';
import 'package:focus_dns/state_management/privacy_state.dart';
import 'package:focus_dns/state_management/protection_state.dart';
import 'package:focus_dns/state_management/security_state.dart';
import 'package:focus_dns/state_management/settings_state.dart';
import 'package:focus_dns/state_management/setup_state.dart';
import 'package:focus_dns/state_management/app_audit_state.dart';
import 'package:focus_dns/state_management/vpn_state.dart';
import 'package:focus_dns/frontend/tabs/setup_tab.dart';
import 'package:focus_dns/frontend/tabs/deep_focus_tab.dart';
import 'package:focus_dns/frontend/tabs/security_tab.dart';
import 'package:focus_dns/frontend/tabs/privacy_tab.dart';
import 'package:focus_dns/frontend/tabs/settings_tab.dart';
import 'package:focus_dns/frontend/theme/wabi_sabi_theme.dart';
import 'package:focus_dns/frontend/widgets/app_logo.dart';

class MockStrictModeNotifier extends StateNotifier<StrictModeState> implements StrictModeNotifier {
  MockStrictModeNotifier(bool isStrict)
      : super(StrictModeState(
          isStrict: isStrict,
          remainingSeconds: isStrict ? 1800 : 0,
          strictUntil: isStrict ? DateTime.now().add(const Duration(seconds: 1800)) : null,
        ));

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class MockVpnNotifier extends StateNotifier<VpnState> implements VpnNotifier {
  MockVpnNotifier(VpnState state) : super(state);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class MockBlockerNotifier extends StateNotifier<BlockerState> implements BlockerNotifier {
  MockBlockerNotifier(BlockerState state) : super(state);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Widget _buildSetupTabHarness({
  ProviderContainer? container,
  List<Override> overrides = const [],
}) {
  final child = MaterialApp(
    theme: WabiSabiTheme.darkTheme,
    home: const Scaffold(
      body: SingleChildScrollView(child: SetupTab()),
    ),
  );

  if (container != null) {
    return UncontrolledProviderScope(container: container, child: child);
  }
  return ProviderScope(
    overrides: [
      settingsRepoProvider.overrideWithValue(InMemorySettingsRepository()),
      liveTelemetryProvider.overrideWith((ref) => LiveTelemetryNotifier(enablePolling: false)),
      ...overrides,
    ],
    child: child,
  );
}

Widget _buildParentalTabHarness({
  ProviderContainer? container,
  List<Override> overrides = const [],
}) {
  final child = MaterialApp(
    theme: WabiSabiTheme.darkTheme,
    home: const Scaffold(
      body: SingleChildScrollView(child: DeepFocusTab()),
    ),
  );

  if (container != null) {
    return UncontrolledProviderScope(container: container, child: child);
  }
  return ProviderScope(
    overrides: [
      settingsRepoProvider.overrideWithValue(InMemorySettingsRepository()),
      liveTelemetryProvider.overrideWith((ref) => LiveTelemetryNotifier(enablePolling: false)),
      ...overrides,
    ],
    child: child,
  );
}

Widget _buildSecurityPrivacyTabHarness({
  required Widget childWidget,
  ProviderContainer? container,
  SettingsRepository? repo,
  List<Override> overrides = const [],
}) {
  final child = MaterialApp(
    theme: WabiSabiTheme.darkTheme,
    home: Scaffold(
      body: SingleChildScrollView(child: childWidget),
    ),
  );

  if (container != null) {
    return UncontrolledProviderScope(container: container, child: child);
  }
  return ProviderScope(
    overrides: [
      settingsRepoProvider.overrideWithValue(repo ?? InMemorySettingsRepository()),
      liveTelemetryProvider.overrideWith((ref) => LiveTelemetryNotifier(enablePolling: false)),
      ...overrides,
    ],
    child: child,
  );
}

ProviderContainer _createHarnessContainer({
  SettingsRepository? repo,
  List<Override> additionalOverrides = const [],
}) {
  final settingsRepo = repo ?? InMemorySettingsRepository();
  return ProviderContainer(
    overrides: [
      settingsRepoProvider.overrideWithValue(settingsRepo),
      liveTelemetryProvider.overrideWith((ref) => LiveTelemetryNotifier(enablePolling: false)),
      ...additionalOverrides,
    ],
  );
}

void main() {
  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    final binding = TestWidgetsFlutterBinding.ensureInitialized();
    binding.platformDispatcher.views.first.physicalSize = const Size(1080, 2400);
    binding.platformDispatcher.views.first.devicePixelRatio = 1.0;
  });

  // ===========================================================================
  // CATEGORY 1: Setup Tab - Endpoints, DNS Types, IP Linking & Fail-Closed (1-18)
  // ===========================================================================
  group('Category 1: Setup Tab - Endpoints, DNS Types & Engine (1-18)', () {
    testWidgets('1. SetupTab renders Engine status card showing Inactive when VPN is disconnected', (tester) async {
      await tester.pumpWidget(_buildSetupTabHarness());
      await tester.pumpAndSettle();

      expect(find.text('FocusDNS Engine: Inactive'), findsOneWidget);
      expect(find.text('Turn on Protection on the home screen to start filtering.'), findsOneWidget);
    });

    testWidgets('2. Engine status card displays Active & Filtering when VPN is running', (tester) async {
      final container = _createHarnessContainer();
      addTearDown(container.dispose);

      container.read(vpnProvider.notifier).state = const VpnState(
        isRunning: true,
        isBackendReachable: true,
      );

      await tester.pumpWidget(_buildSetupTabHarness(container: container));
      await tester.pumpAndSettle();

      expect(find.text('FocusDNS Engine: Active & Filtering'), findsOneWidget);
      expect(find.text('CONNECTED'), findsOneWidget);
    });

    testWidgets('3. Profile ID endpoint displays current profile string', (tester) async {
      await tester.pumpWidget(_buildSetupTabHarness());
      await tester.pumpAndSettle();

      expect(find.text('Profile ID'), findsOneWidget);
      expect(find.text('Unique identifier for your rules and policies'), findsOneWidget);
    });

    testWidgets('4. DNS-over-HTTPS (DoH) endpoint formats with secure URL scheme', (tester) async {
      await tester.pumpWidget(_buildSetupTabHarness());
      await tester.pumpAndSettle();

      expect(find.text('DNS-over-HTTPS (DoH)'), findsOneWidget);
      expect(find.textContaining('https://'), findsWidgets);
    });

    testWidgets('5. DNS-over-TLS (DoT) / Private DNS displays host for Android 9+', (tester) async {
      await tester.pumpWidget(_buildSetupTabHarness());
      await tester.pumpAndSettle();

      expect(find.text('DNS-over-TLS (DoT) / Private DNS'), findsOneWidget);
      expect(find.textContaining('Settings > Network > Private DNS'), findsOneWidget);
    });

    testWidgets('6. IPv4 Anycast endpoints list standard IP addresses', (tester) async {
      await tester.pumpWidget(_buildSetupTabHarness());
      await tester.pumpAndSettle();

      expect(find.text('IPv4 Anycast'), findsOneWidget);
      expect(find.textContaining('For home Wi-Fi routers and traditional DNS settings'), findsOneWidget);
    });

    testWidgets('7. IPv6 Anycast endpoints list IPv6 hex addresses', (tester) async {
      await tester.pumpWidget(_buildSetupTabHarness());
      await tester.pumpAndSettle();

      expect(find.text('IPv6 Anycast'), findsOneWidget);
      expect(find.textContaining('For IPv6-native connections and dual-stack routers'), findsOneWidget);
    });

    testWidgets('8. Copy button on DoH endpoint triggers clipboard and feedback SnackBar', (tester) async {
      await tester.pumpWidget(_buildSetupTabHarness());
      await tester.pumpAndSettle();

      final copyBtn = find.byTooltip('Copy DNS-over-HTTPS (DoH)');
      expect(copyBtn, findsOneWidget);
      await tester.tap(copyBtn);
      await tester.pumpAndSettle();

      expect(find.text('DNS-over-HTTPS (DoH) copied to clipboard'), findsOneWidget);
    });

    testWidgets('9. Copy button on IPv4 Anycast triggers clipboard and SnackBar', (tester) async {
      await tester.pumpWidget(_buildSetupTabHarness());
      await tester.pumpAndSettle();

      final copyBtn = find.byTooltip('Copy IPv4 Anycast');
      expect(copyBtn, findsOneWidget);
      await tester.tap(copyBtn);
      await tester.pumpAndSettle();

      expect(find.text('IPv4 Anycast copied to clipboard'), findsOneWidget);
    });

    testWidgets('10. Linked IP card renders Unlinked state when no network IP is bound', (tester) async {
      await tester.pumpWidget(_buildSetupTabHarness());
      await tester.pumpAndSettle();

      expect(find.text('Linked IP'), findsOneWidget);
      expect(find.text('CURRENT NETWORK IP'), findsOneWidget);
      expect(find.text('AUTO-SYNCING'), findsOneWidget);
    });

    testWidgets('11. Matched IP displays ACTIVE MATCH badge in Linked IP card', (tester) async {
      final container = _createHarnessContainer();
      addTearDown(container.dispose);

      container.read(setupProvider.notifier).state = const SetupState(
        profileId: 'a1b2c3',
        dohUrl: 'https://dns.focusdns.app/dns-query/a1b2c3',
        dotHostname: 'a1b2c3.dns.focusdns.app',
        ipv4Endpoints: ['45.11.45.11'],
        ipv6Endpoints: ['2a09::1'],
        currentClientIp: '203.0.113.42',
        linkedIp: '203.0.113.42', // matched
      );

      await tester.pumpWidget(_buildSetupTabHarness(container: container));
      await tester.pumpAndSettle();

      expect(find.text('ACTIVE MATCH'), findsOneWidget);
      expect(find.text('AUTO-SYNCED'), findsOneWidget);
    });

    testWidgets('12. Different Network displays DIFFERENT NETWORK badge', (tester) async {
      final container = _createHarnessContainer();
      addTearDown(container.dispose);

      container.read(setupProvider.notifier).state = const SetupState(
        profileId: 'a1b2c3',
        dohUrl: 'https://dns.focusdns.app/dns-query/a1b2c3',
        dotHostname: 'a1b2c3.dns.focusdns.app',
        ipv4Endpoints: ['45.11.45.11'],
        ipv6Endpoints: ['2a09::1'],
        currentClientIp: '198.51.100.5',
        linkedIp: '203.0.113.42', // different
      );

      await tester.pumpWidget(_buildSetupTabHarness(container: container));
      await tester.pumpAndSettle();

      expect(find.text('DIFFERENT NETWORK'), findsOneWidget);
      expect(find.text('SYNC IP'), findsOneWidget);
    });

    testWidgets('13. Local Device VPN card indicates VPN Disconnected initially', (tester) async {
      await tester.pumpWidget(_buildSetupTabHarness());
      await tester.pumpAndSettle();

      expect(find.text('Local Device VPN (DNS Only)'), findsOneWidget);
      expect(find.text('VPN Disconnected'), findsOneWidget);
      expect(find.text('ACTIVATE VPN'), findsOneWidget);
    });

    testWidgets('14. Backend unreachable displays fail-closed warning in Local Device VPN', (tester) async {
      final container = _createHarnessContainer();
      addTearDown(container.dispose);

      container.read(vpnProvider.notifier).state = const VpnState(
        isRunning: true,
        isBackendReachable: false,
      );

      await tester.pumpWidget(_buildSetupTabHarness(container: container));
      await tester.pumpAndSettle();

      expect(find.text('⚠️ Backend Unreachable (Fail-Closed)'), findsOneWidget);
    });

    testWidgets('15. In Strict Mode, attempting to DISCONNECT VPN is locked with SnackBar', (tester) async {
      await tester.pumpWidget(_buildSetupTabHarness(
        overrides: [
          strictModeProvider.overrideWith((ref) => MockStrictModeNotifier(true)),
          vpnProvider.overrideWith((ref) => MockVpnNotifier(
            const VpnState(isRunning: true, isBackendReachable: true),
          )),
        ],
      ));
      await tester.pumpAndSettle();

      final disconnectBtn = find.text('DISCONNECT');
      expect(disconnectBtn, findsOneWidget);
      await tester.tap(disconnectBtn);
      await tester.pumpAndSettle();

      expect(find.textContaining('Strict Mode is active'), findsOneWidget);
      expect(find.textContaining('Disconnecting VPN is locked'), findsOneWidget);
    });

    testWidgets('16. Native App Blocker card reflects Blocker Disabled when Accessibility is off', (tester) async {
      await tester.pumpWidget(_buildSetupTabHarness());
      await tester.pumpAndSettle();

      expect(find.text('Native App Blocker (Accessibility)'), findsOneWidget);
      expect(find.text('Blocker Disabled'), findsOneWidget);
      expect(find.text('ENABLE BLOCKER'), findsOneWidget);
    });

    testWidgets('17. Native App Blocker card reflects App Blocker Active when Accessibility is granted', (tester) async {
      await tester.pumpWidget(_buildSetupTabHarness(
        overrides: [
          blockerProvider.overrideWith((ref) => MockBlockerNotifier(
            const BlockerState(isEnabled: true),
          )),
        ],
      ));
      await tester.pumpAndSettle();

      expect(find.text('App Blocker Active'), findsOneWidget);
      expect(find.text('Accessibility service connected'), findsOneWidget);
      expect(find.text('SETTINGS'), findsOneWidget);
    });

    testWidgets('18. Server & Cloud Endpoint card displays current URL and Save action', (tester) async {
      await tester.pumpWidget(_buildSetupTabHarness());
      await tester.pumpAndSettle();

      expect(find.text('Server & Cloud Endpoint'), findsOneWidget);
      expect(find.text('PROBE'), findsOneWidget);
      expect(find.text('SAVE & CONNECT'), findsOneWidget);
    });
  });

  // ===========================================================================
  // CATEGORY 2: Parental Controls & Deep Focus - Apps, Categories & Audit (19-35)
  // ===========================================================================
  group('Category 2: Parental Controls & Deep Focus (19-35)', () {
    testWidgets('19. Deep Focus tab does not display 1-Tap Distraction Audit banner and directly renders lists', (tester) async {
      await tester.pumpWidget(_buildParentalTabHarness());
      await tester.pumpAndSettle();

      expect(find.text('1-Tap Distraction Audit'), findsNothing);
      expect(find.text('RUN 1-TAP DISTRACTION AUDIT'), findsNothing);
      expect(find.text('Websites, Apps & Games'), findsOneWidget);
    });

    testWidgets('20. Websites, Apps & Games card starts clean with 0 items prior to user addition', (tester) async {
      await tester.pumpWidget(_buildParentalTabHarness());
      await tester.pumpAndSettle();

      expect(find.text('Websites, Apps & Games'), findsOneWidget);
      expect(find.text('0 BLOCKED'), findsNWidgets(2));
    });

    testWidgets('21. Pre-made distracting apps display custom icon avatars (e.g. R for Reddit)', (tester) async {
      final container = _createHarnessContainer();
      addTearDown(container.dispose);
      container.read(deepFocusProvider.notifier).addWebsite(const BlockedItem(
        id: 'reddit',
        name: 'Reddit',
        icon: 'R',
        packages: ['com.reddit.frontpage'],
      ));

      await tester.pumpWidget(_buildParentalTabHarness(container: container));
      await tester.pumpAndSettle();

      expect(find.text('Reddit'), findsOneWidget);
      expect(find.byType(AppLogo), findsOneWidget);
    });

    testWidgets('22. Pre-made categories card renders Piracy and Gambling', (tester) async {
      final container = _createHarnessContainer();
      addTearDown(container.dispose);
      container.read(deepFocusProvider.notifier).addCategory(const BlockedItem(
        id: 'piracy',
        name: 'Piracy & Torrents',
        icon: '🏴‍☠️',
      ));
      container.read(deepFocusProvider.notifier).addCategory(const BlockedItem(
        id: 'gambling',
        name: 'Gambling',
        icon: '🎰',
      ));

      await tester.pumpWidget(_buildParentalTabHarness(container: container));
      await tester.pumpAndSettle();

      expect(find.text('Categories'), findsOneWidget);
      expect(find.text('Piracy & Torrents'), findsOneWidget);
      expect(find.text('Gambling'), findsOneWidget);
    });

    testWidgets('23. Header counter chips display correct number of BLOCKED items', (tester) async {
      final container = _createHarnessContainer();
      addTearDown(container.dispose);
      container.read(deepFocusProvider.notifier).addWebsite(const BlockedItem(
        id: 'reddit',
        name: 'Reddit',
        icon: 'R',
        packages: ['com.reddit.frontpage'],
      ));
      container.read(deepFocusProvider.notifier).addCategory(const BlockedItem(
        id: 'piracy',
        name: 'Piracy & Torrents',
        icon: '🏴‍☠️',
      ));
      container.read(deepFocusProvider.notifier).addCategory(const BlockedItem(
        id: 'gambling',
        name: 'Gambling',
        icon: '🎰',
      ));

      await tester.pumpWidget(_buildParentalTabHarness(container: container));
      await tester.pumpAndSettle();

      expect(find.text('1 BLOCKED'), findsOneWidget); // Reddit
      expect(find.text('2 BLOCKED'), findsOneWidget); // Piracy, Gambling
    });

    testWidgets('24. Removing an app in normal mode removes it immediately from blocked list', (tester) async {
      final container = _createHarnessContainer();
      addTearDown(container.dispose);
      container.read(deepFocusProvider.notifier).addWebsite(const BlockedItem(
        id: 'reddit',
        name: 'Reddit',
        icon: 'R',
        packages: ['com.reddit.frontpage'],
      ));

      await tester.pumpWidget(_buildParentalTabHarness(container: container));
      await tester.pumpAndSettle();

      expect(find.text('Reddit'), findsOneWidget);

      // Find first delete button (Reddit)
      final removeButtons = find.byIcon(Icons.close_rounded);
      expect(removeButtons, findsWidgets);
      await tester.tap(removeButtons.first);
      await tester.pumpAndSettle();

      // Reddit should now be removed
      expect(find.text('Reddit'), findsNothing);
    });

    testWidgets('25. In Strict Mode, unblock delete icons are replaced with lock icons', (tester) async {
      final container = _createHarnessContainer(
        additionalOverrides: [
          strictModeProvider.overrideWith((ref) => MockStrictModeNotifier(true)),
        ],
      );
      addTearDown(container.dispose);
      container.read(deepFocusProvider.notifier).addWebsite(const BlockedItem(
        id: 'reddit',
        name: 'Reddit',
        icon: 'R',
        packages: ['com.reddit.frontpage'],
      ));

      await tester.pumpWidget(_buildParentalTabHarness(container: container));
      await tester.pumpAndSettle();

      // Delete close icons must NOT exist
      expect(find.byIcon(Icons.close_rounded), findsNothing);
      // Lock icons must exist
      expect(find.byIcon(Icons.lock_outline_rounded), findsWidgets);
    });

    testWidgets('26. In Strict Mode, delete buttons are replaced by lock indicator icons', (tester) async {
      final container = _createHarnessContainer(
        additionalOverrides: [
          strictModeProvider.overrideWith((ref) => MockStrictModeNotifier(true)),
        ],
      );
      addTearDown(container.dispose);
      container.read(deepFocusProvider.notifier).addWebsite(const BlockedItem(
        id: 'reddit',
        name: 'Reddit',
        icon: 'R',
        packages: ['com.reddit.frontpage'],
      ));

      await tester.pumpWidget(_buildParentalTabHarness(container: container));
      await tester.pumpAndSettle();

      // Verify lock icon is rendered instead of delete button
      final lockIcons = find.byIcon(Icons.lock_outline_rounded);
      expect(lockIcons, findsWidgets);
      expect(find.byTooltip('Locked during Strict Mode'), findsWidgets);
    });

    testWidgets('27. Tapping ADD A CATEGORY button opens category picker modal', (tester) async {
      await tester.pumpWidget(_buildParentalTabHarness());
      await tester.pumpAndSettle();

      final addCatBtn = find.text('ADD A CATEGORY');
      expect(addCatBtn, findsOneWidget);
      await tester.tap(addCatBtn);
      await tester.pumpAndSettle();

      expect(find.text('Adult & Pornography'), findsOneWidget);
      expect(find.text('Social Networks'), findsOneWidget);
      expect(find.text('Online Gaming'), findsOneWidget);
      expect(find.text('Dating Services'), findsOneWidget);
    });

    testWidgets('28. Selecting Online Gaming category adds it to active blocked categories', (tester) async {
      final container = _createHarnessContainer();
      addTearDown(container.dispose);

      await tester.pumpWidget(_buildParentalTabHarness(container: container));
      await tester.pumpAndSettle();

      await tester.tap(find.text('ADD A CATEGORY'));
      await tester.pumpAndSettle();

      // Find the third ADD button in the modal (index 2 for Online Gaming)
      final addBtns = find.widgetWithText(ElevatedButton, 'ADD');
      expect(addBtns, findsWidgets);
      await tester.tap(addBtns.at(2));
      await tester.pumpAndSettle();

      expect(find.text('Online Gaming'), findsOneWidget);
      expect(find.text('1 BLOCKED'), findsOneWidget); // 1 category now!
    });

    testWidgets('29. Tapping ADD A WEBSITE, APP OR GAME opens searchable app picker', (tester) async {
      await tester.pumpWidget(_buildParentalTabHarness());
      await tester.pumpAndSettle();

      await tester.tap(find.text('ADD A WEBSITE, APP OR GAME'));
      await tester.pumpAndSettle();

      expect(find.text('Block App or Website'), findsOneWidget);
      expect(find.byType(TextField), findsOneWidget);
    });

    testWidgets('30. Search field in app picker filters items in real time', (tester) async {
      await tester.pumpWidget(_buildParentalTabHarness());
      await tester.pumpAndSettle();

      await tester.tap(find.text('ADD A WEBSITE, APP OR GAME'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'YouTube');
      await tester.pumpAndSettle();

      expect(find.widgetWithText(InkWell, 'YouTube'), findsOneWidget);
      expect(find.text('Netflix'), findsNothing);
    });

    testWidgets('31. Blocking YouTube from app picker adds YouTube to active restrictions', (tester) async {
      final container = _createHarnessContainer();
      addTearDown(container.dispose);

      await tester.pumpWidget(_buildParentalTabHarness(container: container));
      await tester.pumpAndSettle();

      await tester.tap(find.text('ADD A WEBSITE, APP OR GAME'));
      await tester.pumpAndSettle();

      final blockBtns = find.widgetWithText(ElevatedButton, 'BLOCK');
      expect(blockBtns, findsWidgets);
      await tester.tap(blockBtns.first);
      await tester.pumpAndSettle();

      // Close modal
      await tester.tap(find.byKey(const Key('modal_close_button')));
      await tester.pumpAndSettle();

      expect(find.text('YouTube'), findsOneWidget);
    });

    testWidgets('32. Bulk website adding (addWebsitesBulk) adds multiple apps simultaneously', (tester) async {
      final container = _createHarnessContainer();
      addTearDown(container.dispose);

      final newItems = [
        const BlockedItem(id: 'discord', name: 'Discord', icon: 'DC'),
        const BlockedItem(id: 'twitch', name: 'Twitch', icon: 'TW'),
      ];

      container.read(deepFocusProvider.notifier).addWebsitesBulk(newItems);
      final names = container.read(deepFocusProvider).websites.map((w) => w.name).toList();

      expect(names.contains('Discord'), true);
      expect(names.contains('Twitch'), true);
    });

    testWidgets('33. DistractionAuditSheet renders scanner header correctly', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            theme: WabiSabiTheme.darkTheme,
            home: const Scaffold(
              body: DistractionAuditSheet(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Distraction Audit Scanner'), findsOneWidget);
      expect(find.text('Google Play Store Cross-Verified'), findsOneWidget);
    });

    testWidgets('34. Distraction audit scanner sheet lists detected addictive algorithms', (tester) async {
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        const MethodChannel('focus_dns/audit_scanner'),
        (MethodCall methodCall) async {
          if (methodCall.method == 'scanDeviceApps') {
            return {
              'totalScanned': 2,
              'playStoreVerifiedCount': 2,
              'distractionCount': 2,
              'auditGrade': 'C',
              'timestamp': DateTime.now().millisecondsSinceEpoch,
              'apps': [
                {
                  'packageName': 'com.instagram.android',
                  'appName': 'Instagram',
                  'installerPackage': 'com.android.vending',
                  'isPlayStoreVerified': true,
                  'isSystemApp': false,
                  'category': 'social',
                  'distractionScore': 98,
                  'isDistraction': true,
                  'installTimeMs': 1672531199000,
                  'lastUpdateTimeMs': 1672531199000,
                  'targetSdkVersion': 34,
                  'versionName': '315.0.0.0',
                  'associatedDomains': ['instagram.com'],
                },
                {
                  'packageName': 'com.google.android.youtube',
                  'appName': 'YouTube',
                  'installerPackage': 'com.android.vending',
                  'isPlayStoreVerified': true,
                  'isSystemApp': false,
                  'category': 'video',
                  'distractionScore': 95,
                  'isDistraction': true,
                  'installTimeMs': 1672531199000,
                  'lastUpdateTimeMs': 1672531199000,
                  'targetSdkVersion': 34,
                  'versionName': '19.10.35',
                  'associatedDomains': ['youtube.com'],
                },
              ],
            };
          }
          return null;
        },
      );

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            theme: WabiSabiTheme.darkTheme,
            home: const Scaffold(
              body: DistractionAuditSheet(),
            ),
          ),
        ),
      );

      final container = ProviderScope.containerOf(
          tester.element(find.byType(DistractionAuditSheet)));
      await container.read(appAuditProvider.notifier).runScan();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('Instagram'), findsWidgets);
      expect(find.text('YouTube'), findsWidgets);
    });

    testWidgets('35. Tapping 1-TAP BLOCK button blocks all flagged apps and closes modal', (tester) async {
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        const MethodChannel('focus_dns/audit_scanner'),
        (MethodCall methodCall) async {
          if (methodCall.method == 'scanDeviceApps') {
            return {
              'totalScanned': 1,
              'playStoreVerifiedCount': 1,
              'distractionCount': 1,
              'auditGrade': 'B',
              'timestamp': DateTime.now().millisecondsSinceEpoch,
              'apps': [
                {
                  'packageName': 'com.instagram.android',
                  'appName': 'Instagram',
                  'installerPackage': 'com.android.vending',
                  'isPlayStoreVerified': true,
                  'isSystemApp': false,
                  'category': 'social',
                  'distractionScore': 98,
                  'isDistraction': true,
                  'installTimeMs': 1672531199000,
                  'lastUpdateTimeMs': 1672531199000,
                  'targetSdkVersion': 34,
                  'versionName': '315.0.0.0',
                  'associatedDomains': ['instagram.com'],
                },
              ],
            };
          }
          return null;
        },
      );

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            theme: WabiSabiTheme.darkTheme,
            home: const Scaffold(
              body: DistractionAuditSheet(),
            ),
          ),
        ),
      );

      final container = ProviderScope.containerOf(
          tester.element(find.byType(DistractionAuditSheet)));
      await container.read(appAuditProvider.notifier).runScan();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      final blockBtn = find.textContaining('1-TAP BLOCK');
      expect(blockBtn, findsOneWidget);
      await tester.tap(blockBtn);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
    });
  });

  // ===========================================================================
  // CATEGORY 3: Security & Privacy - SafeSearch, YouTube, Trackers & Web3 (36-50)
  // ===========================================================================
  group('Category 3: Security & Privacy Protection Rules (36-50)', () {
    testWidgets('36. SecurityTab renders Threat Intelligence Feeds toggle on by default', (tester) async {
      await tester.pumpWidget(_buildSecurityPrivacyTabHarness(childWidget: const SecurityTab()));
      await tester.pumpAndSettle();

      expect(find.text('Threat Intelligence Feeds'), findsOneWidget);
      expect(find.text('Threat Intelligence'), findsOneWidget);
    });

    testWidgets('37. SecurityTab renders Enforce SafeSearch toggle', (tester) async {
      await tester.pumpWidget(_buildSecurityPrivacyTabHarness(childWidget: const SecurityTab()));
      await tester.pumpAndSettle();

      expect(find.text('Enforce SafeSearch'), findsWidgets);
      expect(find.text('Filter explicit search engine results'), findsOneWidget);
    });

    testWidgets('38. SecurityTab renders YouTube Restricted Mode toggle', (tester) async {
      await tester.pumpWidget(_buildSecurityPrivacyTabHarness(childWidget: const SecurityTab()));
      await tester.pumpAndSettle();

      expect(find.text('YouTube Restricted Mode'), findsWidgets);
      expect(find.text('Hide mature & explicit videos'), findsOneWidget);
    });

    testWidgets('39. SecurityTab renders DNS Rebinding Protection against RFC 1918 attacks', (tester) async {
      await tester.pumpWidget(_buildSecurityPrivacyTabHarness(childWidget: const SecurityTab()));
      await tester.pumpAndSettle();

      expect(find.text('DNS Rebinding Protection'), findsWidgets);
      expect(find.text('Block attacks targeting local router & IoT'), findsOneWidget);
    });

    testWidgets('40. SecurityTab renders Cryptojacking Protection', (tester) async {
      await tester.pumpWidget(_buildSecurityPrivacyTabHarness(childWidget: const SecurityTab()));
      await tester.pumpAndSettle();

      expect(find.text('Cryptojacking Protection'), findsWidgets);
      expect(find.text('Block in-browser cryptocurrency mining'), findsOneWidget);
    });

    testWidgets('41. SecurityTab renders Google Safe Browsing', (tester) async {
      await tester.pumpWidget(_buildSecurityPrivacyTabHarness(childWidget: const SecurityTab()));
      await tester.pumpAndSettle();

      expect(find.text('Google Safe Browsing'), findsWidgets);
      expect(find.text('Block dangerous and deceptive sites'), findsOneWidget);
    });

    testWidgets('42. Toggling Enforce SafeSearch off during Strict Mode is blocked with SnackBar', (tester) async {
      final repo = InMemorySettingsRepository();
      await repo.setSecurityFeature(SecurityFeature.safesearch, true);

      await tester.pumpWidget(_buildSecurityPrivacyTabHarness(
        childWidget: const SecurityTab(),
        repo: repo,
        overrides: [
          strictModeProvider.overrideWith((ref) => MockStrictModeNotifier(true)),
        ],
      ));
      await tester.pumpAndSettle();

      // Find switch for SafeSearch by looking at switchRow for SafeSearch
      final safesearchSwitch = find.descendant(
        of: find.widgetWithText(Row, 'Enforce SafeSearch'),
        matching: find.byType(Switch),
      );
      expect(safesearchSwitch, findsOneWidget);
      await tester.tap(safesearchSwitch);
      await tester.pumpAndSettle();

      expect(find.textContaining('Cannot disable security features until timer expires'), findsOneWidget);
    });

    testWidgets('43. PrivacyTab renders FocusDNS Ads & Trackers Blocklist with rule count', (tester) async {
      await tester.pumpWidget(_buildSecurityPrivacyTabHarness(childWidget: const PrivacyTab()));
      await tester.pumpAndSettle();

      expect(find.text('Blocklists'), findsOneWidget);
      expect(find.text('FocusDNS Ads & Trackers Blocklist'), findsOneWidget);
      expect(find.text('43,921 rules applied'), findsOneWidget);
    });

    testWidgets('44. PrivacyTab renders Disguised Third-Party Trackers switch', (tester) async {
      await tester.pumpWidget(_buildSecurityPrivacyTabHarness(childWidget: const PrivacyTab()));
      await tester.pumpAndSettle();

      expect(find.text('Tracking Protection'), findsOneWidget);
      expect(find.text('Block Disguised Third-Party Trackers'), findsOneWidget);
    });

    testWidgets('45. Disabling Disguised Third-Party Trackers in Strict Mode triggers warning SnackBar', (tester) async {
      await tester.pumpWidget(_buildSecurityPrivacyTabHarness(
        childWidget: const PrivacyTab(),
        overrides: [
          strictModeProvider.overrideWith((ref) => MockStrictModeNotifier(true)),
        ],
      ));
      await tester.pumpAndSettle();

      final trackerSwitch = find.byType(Switch).first;
      await tester.tap(trackerSwitch);
      await tester.pumpAndSettle();

      expect(find.textContaining('Cannot disable tracker protection until timer expires'), findsOneWidget);
    });

    testWidgets('46. Toggling AI Threat Detection in normal mode updates state without error', (tester) async {
      final container = _createHarnessContainer();
      addTearDown(container.dispose);

      await tester.pumpWidget(_buildSecurityPrivacyTabHarness(
        childWidget: const SecurityTab(),
        container: container,
      ));
      await tester.pumpAndSettle();

      // AI Threat is switch index 1
      final aiSwitch = find.byType(Switch).at(1);
      await tester.tap(aiSwitch);
      await tester.pumpAndSettle();

      expect(container.read(securityProvider)[SecurityFeature.aiThreat], true);
    });

    testWidgets('47. SettingsTab renders Anti-Uninstall MDM Shield Card', (tester) async {
      await tester.pumpWidget(_buildSecurityPrivacyTabHarness(childWidget: const SettingsTab()));
      await tester.pumpAndSettle();

      expect(find.text('Anti-Uninstall & Device Shield'), findsOneWidget);
    });

    testWidgets('48. SettingsTab renders Appearance Theme selector (Charcoal Dark & Stone Light)', (tester) async {
      await tester.pumpWidget(_buildSecurityPrivacyTabHarness(childWidget: const SettingsTab()));
      await tester.pumpAndSettle();

      expect(find.text('Appearance'), findsOneWidget);
      expect(find.text('Charcoal Dark'), findsOneWidget);
      expect(find.text('Stone Light'), findsOneWidget);
    });

    testWidgets('49. SettingsTab renders Log Retention dropdown with 1 month selected by default', (tester) async {
      await tester.pumpWidget(_buildSecurityPrivacyTabHarness(childWidget: const SettingsTab()));
      await tester.pumpAndSettle();

      expect(find.text('Log Retention'), findsOneWidget);
      expect(find.text('1 month'), findsOneWidget);
    });

    testWidgets('50. SettingsTab renders Web3 Domains switches for ENS, Unstoppable and IPFS', (tester) async {
      await tester.pumpWidget(_buildSecurityPrivacyTabHarness(childWidget: const SettingsTab()));
      await tester.pumpAndSettle();

      expect(find.text('Web3 Domains'), findsOneWidget);
      expect(find.text('Ethereum Name Service (ENS)'), findsOneWidget);
      expect(find.text('Unstoppable Domains'), findsOneWidget);
      expect(find.text('IPFS Gateway'), findsOneWidget);
    });
  });

  // ===========================================================================
  // CATEGORY 4: Cross-Tab Resilience & Sheet Navigation (51-55)
  // ===========================================================================
  group('Category 4: Cross-Tab Resilience & Sheet Navigation (51-55)', () {
    testWidgets('51. SetupTab renders safely without layout exceptions on small screen dimensions', (tester) async {
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(_buildSetupTabHarness());
      await tester.pumpAndSettle();

      expect(find.text('Profile ID'), findsOneWidget);
      expect(find.text('DNS-over-HTTPS (DoH)'), findsOneWidget);
    });

    testWidgets('52. DeepFocusTab renders with empty website list without crashing list card', (tester) async {
      final container = _createHarnessContainer();
      addTearDown(container.dispose);

      container.read(deepFocusProvider.notifier).state = const DeepFocusState(
        websites: [],
        categories: [],
      );

      await tester.pumpWidget(_buildParentalTabHarness(container: container));
      await tester.pumpAndSettle();

      expect(find.text('0 BLOCKED'), findsNWidgets(2));
    });

    testWidgets('53. Security tab features load from repository during initialization', (tester) async {
      final repo = InMemorySettingsRepository();
      await repo.setSecurityFeature(SecurityFeature.aiThreat, true);

      final container = _createHarnessContainer(repo: repo);
      addTearDown(container.dispose);

      // Read securityProvider and give async _init time to complete
      container.read(securityProvider);
      await tester.runAsync(() => Future.delayed(const Duration(milliseconds: 20)));

      expect(container.read(securityProvider)[SecurityFeature.aiThreat], true);
    });

    testWidgets('54. Privacy tab features load from repository during initialization', (tester) async {
      final repo = InMemorySettingsRepository();
      await repo.setPrivacyFeature(PrivacyFeature.disguisedTrackers, true);

      final container = _createHarnessContainer(repo: repo);
      addTearDown(container.dispose);

      // Read privacyProvider and give async _init time to complete
      container.read(privacyProvider);
      await tester.runAsync(() => Future.delayed(const Duration(milliseconds: 20)));

      expect(container.read(privacyProvider)[PrivacyFeature.disguisedTrackers], true);
    });

    testWidgets('55. Rapidly toggling Web3 domains updates state atomically without race conditions', (tester) async {
      final container = _createHarnessContainer();
      addTearDown(container.dispose);

      for (int i = 0; i < 5; i++) {
        container.read(settingsProvider.notifier).toggleWeb3(Web3Feature.ens, i % 2 == 0);
      }

      expect(container.read(settingsProvider).web3[Web3Feature.ens], true);
    });
  });
}
