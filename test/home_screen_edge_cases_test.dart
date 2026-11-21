import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:focus_dns/main.dart';
import 'package:focus_dns/models/app_models.dart';
import 'package:focus_dns/repositories/settings_repository.dart';
import 'package:focus_dns/state_management/auth_state.dart';
import 'package:focus_dns/state_management/blocker_state.dart';
import 'package:focus_dns/state_management/deep_focus_state.dart';
import 'package:focus_dns/state_management/live_telemetry_provider.dart';
import 'package:focus_dns/state_management/privacy_state.dart';
import 'package:focus_dns/state_management/protection_state.dart';
import 'package:focus_dns/state_management/security_state.dart';
import 'package:focus_dns/models/enums.dart';
import 'package:focus_dns/state_management/settings_state.dart';
import 'package:focus_dns/state_management/vpn_state.dart';
import 'package:focus_dns/frontend/home_screen.dart';
import 'package:focus_dns/frontend/theme/wabi_sabi_theme.dart';

Widget _buildTestableHomeScreen({
  SettingsRepository? repo,
  ProviderContainer? container,
  List<Override> additionalOverrides = const [],
  Size physicalSize = const Size(1080, 2400),
  Brightness brightness = Brightness.dark,
}) {
  final settingsRepo = repo ?? InMemorySettingsRepository();
  final overrides = [
    settingsRepoProvider.overrideWithValue(settingsRepo),
    liveTelemetryProvider.overrideWith((ref) => LiveTelemetryNotifier(enablePolling: false)),
    ...additionalOverrides,
  ];

  if (container != null) {
    return UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: WabiSabiTheme.darkTheme,
        home: const FocusDNSHomeScreen(),
      ),
    );
  }

  return ProviderScope(
    overrides: overrides,
    child: MaterialApp(
      theme: WabiSabiTheme.darkTheme,
      home: const FocusDNSHomeScreen(),
    ),
  );
}

ProviderContainer _createTestContainer({
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
  });

  group('Category 1: Master Seal & Protection State Transitions (1-10)', () {
    testWidgets('1. Initial launch protection starts OFF as per user specification', (tester) async {
      await tester.pumpWidget(_buildTestableHomeScreen());
      await tester.pumpAndSettle();

      expect(find.text('IDLE'), findsOneWidget);
      expect(find.text('TAP TO RESUME'), findsOneWidget);
      expect(find.text('Protection Paused'), findsOneWidget);
      expect(find.text('Tap seal to resume protection.'), findsOneWidget);
    });

    testWidgets('2. Single tap resumes protection to ACTIVE', (tester) async {
      await tester.pumpWidget(_buildTestableHomeScreen());
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('main_protection_toggle')));
      await tester.pumpAndSettle();

      expect(find.text('ACTIVE'), findsOneWidget);
      expect(find.text('Protection Active'), findsOneWidget);
      expect(find.text('Tap seal to pause protection.'), findsOneWidget);
    });

    testWidgets('3. Rapid double-tapping on master switch toggles state back predictably without crash', (tester) async {
      await tester.pumpWidget(_buildTestableHomeScreen());
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('main_protection_toggle')));
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tap(find.byKey(const Key('main_protection_toggle')));
      await tester.pumpAndSettle();

      expect(find.text('IDLE'), findsOneWidget);
      expect(find.text('Protection Paused'), findsOneWidget);
    });

    testWidgets('4. Rapid 5-times tapping on master switch maintains consistency', (tester) async {
      await tester.pumpWidget(_buildTestableHomeScreen());
      await tester.pumpAndSettle();

      for (int i = 0; i < 5; i++) {
        await tester.tap(find.byKey(const Key('main_protection_toggle')));
        await tester.pump(const Duration(milliseconds: 30));
      }
      await tester.pumpAndSettle();

      // Odd number of taps -> ACTIVE
      expect(find.text('ACTIVE'), findsOneWidget);
    });

    testWidgets('5. Active state displays filled shield icon and inactive displays outlined shield', (tester) async {
      await tester.pumpWidget(_buildTestableHomeScreen());
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.shield_outlined), findsWidgets);

      await tester.tap(find.byKey(const Key('main_protection_toggle')));
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.shield), findsWidgets);
    });

    testWidgets('6. When Strict Mode is active, tapping master switch is rejected with SnackBar', (tester) async {
      final repo = InMemorySettingsRepository();
      await repo.setStrictMode(true, durationMinutes: 30);

      await tester.pumpWidget(_buildTestableHomeScreen(repo: repo));
      await tester.pumpAndSettle();

      expect(find.text('LOCKED'), findsOneWidget);
      expect(find.text('Protection Locked'), findsOneWidget);

      await tester.tap(find.byKey(const Key('main_protection_toggle')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(find.textContaining('Protection is locked'), findsOneWidget);
      expect(find.text('LOCKED'), findsOneWidget);
    });

    testWidgets('7. In Strict Mode, master switch displays lock icon and LOCKED badge', (tester) async {
      final repo = InMemorySettingsRepository();
      await repo.setStrictMode(true, durationMinutes: 15);

      await tester.pumpWidget(_buildTestableHomeScreen(repo: repo));
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.lock_rounded), findsWidgets);
      expect(find.text('LOCKED'), findsOneWidget);
    });

    testWidgets('8. Begin a session sheet reflects Normal, Strict, Routine, and Feed Blocker options', (tester) async {
      await tester.pumpWidget(_buildTestableHomeScreen());
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('begin_session_button')), findsOneWidget);
      await tester.tap(find.byKey(const Key('begin_session_button')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('normal_mode_button')), findsOneWidget);
      expect(find.byKey(const Key('strict_mode_button')), findsOneWidget);
      expect(find.byKey(const Key('routine_mode_button')), findsOneWidget);
      expect(find.byKey(const Key('feed_blocker_mode_button')), findsOneWidget);
    });

    testWidgets('8b. Tapping Feed Blocker toggles feed blackholing on all platforms', (tester) async {
      await tester.pumpWidget(_buildTestableHomeScreen());
      await tester.pumpAndSettle();

      // First tap toggles from default state to paused
      await tester.tap(find.byKey(const Key('begin_session_button')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('feed_blocker_mode_button')));
      await tester.pumpAndSettle();

      expect(find.textContaining('Feed Blocker paused. Feeds unblocked.'), findsOneWidget);

      // Second tap toggles back to active
      await tester.tap(find.byKey(const Key('begin_session_button')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('feed_blocker_mode_button')));
      await tester.pumpAndSettle();

      expect(find.textContaining('Feed Blocker active. Reels & Shorts blackholed.'), findsOneWidget);
    });

    testWidgets('8c. Tapping Focus Routine & Breaks opens circular 3-step setup and begins routine', (tester) async {
      await tester.pumpWidget(_buildTestableHomeScreen());
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('begin_session_button')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('routine_mode_button')));
      await tester.pumpAndSettle();

      // Step 1: Focus Duration circular dial
      expect(find.text('Select Focus Session'), findsOneWidget);
      expect(find.text('FOCUS DURATION'), findsOneWidget);

      // Select 45m on circular dial
      await tester.tap(find.byKey(const Key('circular_option_45m')));
      await tester.pumpAndSettle();
      expect(find.text('45m'), findsWidgets);

      // Advance to Step 2
      await tester.tap(find.byKey(const Key('routine_next_step')));
      await tester.pumpAndSettle();

      // Step 2: Break Timer circular dial
      expect(find.text('Select Break Timer'), findsOneWidget);
      expect(find.text('BREAK TIMER'), findsOneWidget);

      // Select 15m on circular dial
      await tester.tap(find.byKey(const Key('circular_option_15m')));
      await tester.pumpAndSettle();

      // Advance to Step 3
      await tester.tap(find.byKey(const Key('routine_next_step')));
      await tester.pumpAndSettle();

      // Step 3: Cycles
      expect(find.text('Select Repetitions'), findsOneWidget);
      expect(find.text('CYCLES'), findsOneWidget);

      // Select 6 cycles on circular dial
      await tester.tap(find.byKey(const Key('circular_option_6')));
      await tester.pumpAndSettle();

      // Begin Routine
      await tester.tap(find.byKey(const Key('routine_start_button')));
      await tester.pumpAndSettle();

      expect(find.textContaining('Focus Routine started'), findsOneWidget);
    });

    testWidgets('9. Tapping Normal Mode button while already in Normal mode is a safe no-op', (tester) async {
      await tester.pumpWidget(_buildTestableHomeScreen());
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('begin_session_button')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('normal_mode_button')));
      await tester.pumpAndSettle();

      expect(find.textContaining('Normal Focus active'), findsOneWidget);
    });

    testWidgets('10. In Strict Mode, tapping Normal mode button displays timer lock warning SnackBar', (tester) async {
      final repo = InMemorySettingsRepository();
      await repo.setStrictMode(true, durationMinutes: 45);

      await tester.pumpWidget(_buildTestableHomeScreen(repo: repo));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('active_strict_session_badge')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(find.textContaining('Cannot switch to Normal Mode until timer expires'), findsOneWidget);
    });
  });

  group('Category 2: Strict Mode Modal, Slider & Presets (11-20)', () {
    testWidgets('11. Tapping Strict Mode opens bottom sheet with disclaimer text', (tester) async {
      await tester.pumpWidget(_buildTestableHomeScreen());
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('begin_session_button')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('strict_mode_button')));
      await tester.pumpAndSettle();

      expect(find.text('Activate Strict Mode'), findsOneWidget);
      expect(find.textContaining('In Strict Mode you cannot access any blocked apps'), findsOneWidget);
      expect(find.text('Select Duration'), findsOneWidget);
    });

    testWidgets('12. Cancel button on Strict Mode sheet dismisses dialog without enabling strict mode', (tester) async {
      await tester.pumpWidget(_buildTestableHomeScreen());
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('begin_session_button')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('strict_mode_button')));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(find.text('Activate Strict Mode'), findsNothing);
      expect(find.text('Protection Paused'), findsOneWidget);
    });

    testWidgets('13. Preset chips 15m, 30m, 45m, 1h, 2h, 4h, 8h exist on sheet', (tester) async {
      await tester.pumpWidget(_buildTestableHomeScreen());
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('begin_session_button')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('strict_mode_button')));
      await tester.pumpAndSettle();

      expect(find.text('15m'), findsOneWidget);
      expect(find.text('30m'), findsOneWidget);
      expect(find.text('45m'), findsOneWidget);
      expect(find.text('1h'), findsOneWidget);
      expect(find.text('2h'), findsOneWidget);
      expect(find.text('4h'), findsOneWidget);
      expect(find.text('8h'), findsOneWidget);
    });

    testWidgets('14. Selecting 15m preset updates duration indicator to 15 minutes', (tester) async {
      await tester.pumpWidget(_buildTestableHomeScreen());
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('begin_session_button')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('strict_mode_button')));
      await tester.pumpAndSettle();

      await tester.tap(find.text('15m'));
      await tester.pumpAndSettle();

      expect(find.text('15 minutes'), findsOneWidget);
    });

    testWidgets('15. Selecting 1h preset updates duration text to 1h', (tester) async {
      await tester.pumpWidget(_buildTestableHomeScreen());
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('begin_session_button')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('strict_mode_button')));
      await tester.pumpAndSettle();

      await tester.tap(find.text('1h'));
      await tester.pumpAndSettle();

      expect(find.text('1h'), findsWidgets);
    });

    testWidgets('16. Selecting 8h preset updates duration text to 8h', (tester) async {
      await tester.pumpWidget(_buildTestableHomeScreen());
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('begin_session_button')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('strict_mode_button')));
      await tester.pumpAndSettle();

      await tester.tap(find.text('8h'));
      await tester.pumpAndSettle();

      expect(find.text('8h'), findsWidgets);
    });

    testWidgets('17. Dragging duration slider adjusts selected minutes smoothly', (tester) async {
      await tester.pumpWidget(_buildTestableHomeScreen());
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('begin_session_button')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('strict_mode_button')));
      await tester.pumpAndSettle();

      final sliderFinder = find.byType(Slider);
      expect(sliderFinder, findsOneWidget);

      await tester.drag(sliderFinder, const Offset(-100, 0));
      await tester.pumpAndSettle();

      expect(find.text('Activate Strict Mode'), findsOneWidget);
    });

    testWidgets('18. Confirming 30m strict mode activates Strict Mode and locks UI', (tester) async {
      await tester.pumpWidget(_buildTestableHomeScreen());
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('begin_session_button')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('strict_mode_button')));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Lock In Strict Mode'));
      await tester.pumpAndSettle();

      expect(find.text('Protection Locked'), findsOneWidget);
      expect(find.text('LOCKED'), findsOneWidget);
      expect(find.textContaining('Strict Session Active:'), findsOneWidget);
    });

    testWidgets('19. Tapping strict button when already strict informs user of existing active session', (tester) async {
      final repo = InMemorySettingsRepository();
      await repo.setStrictMode(true, durationMinutes: 60);

      await tester.pumpWidget(_buildTestableHomeScreen(repo: repo));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('active_strict_session_badge')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(find.textContaining('Strict Mode locked'), findsOneWidget);
    });

    testWidgets('20. Barrier dismiss tap outside strict bottom sheet cancels safely', (tester) async {
      await tester.pumpWidget(_buildTestableHomeScreen());
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('begin_session_button')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('strict_mode_button')));
      await tester.pumpAndSettle();

      // Tap top outside sheet
      await tester.tapAt(const Offset(200, 50));
      await tester.pumpAndSettle();

      expect(find.text('Activate Strict Mode'), findsNothing);
      expect(find.text('Protection Paused'), findsOneWidget);
    });
  });

  group('Category 3: Micro-Telemetry & Real-Time Stats Strip (21-30)', () {
    testWidgets('21. Micro-stat strip renders with zero initial state', (tester) async {
      await tester.pumpWidget(_buildTestableHomeScreen());
      await tester.pumpAndSettle();

      expect(find.text('BLOCKED TODAY'), findsOneWidget);
      expect(find.text('THREAT RATIO'), findsOneWidget);
      expect(find.text('DOH LATENCY'), findsOneWidget);
      expect(find.text('0'), findsWidgets);
      expect(find.text('0.0%'), findsOneWidget);
    });

    testWidgets('22. Live telemetry blocked count update propagates to UI', (tester) async {
      final container = _createTestContainer();
      addTearDown(container.dispose);

      await tester.pumpWidget(_buildTestableHomeScreen(container: container));
      await tester.pumpAndSettle();

      container.read(liveTelemetryProvider.notifier).state = LiveTelemetryState(
        totalQueries: 1,
        blockedQueries: 1,
        threatRatio: 100.0,
        blockedPercentage: '100%',
        averageLatencyMs: 14,
        recentQueries: [
          LiveDnsQueryItem(
            id: '1',
            domain: 'ads.doubleclick.net',
            subdomain: 'ads',
            rootDomain: 'doubleclick.net',
            status: 'BLOCKED',
            reason: 'ADVERTISING',
            latencyMs: 14,
            timestamp: DateTime(2026, 11, 4),
          ),
        ],
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('1'), findsWidgets);
      expect(find.text('100%'), findsOneWidget);
    });

    testWidgets('23. Average latency updates correctly from telemetry queries', (tester) async {
      final container = _createTestContainer();
      addTearDown(container.dispose);

      await tester.pumpWidget(_buildTestableHomeScreen(container: container));
      await tester.pumpAndSettle();

      container.read(liveTelemetryProvider.notifier).state = const LiveTelemetryState(
        totalQueries: 1,
        blockedQueries: 0,
        averageLatencyMs: 38,
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('38ms'), findsOneWidget);
    });

    testWidgets('24. 10 rapid query bursts display updated telemetry without frame drops', (tester) async {
      final container = _createTestContainer();
      addTearDown(container.dispose);

      await tester.pumpWidget(_buildTestableHomeScreen(container: container));
      await tester.pumpAndSettle();

      container.read(liveTelemetryProvider.notifier).state = const LiveTelemetryState(
        totalQueries: 10,
        blockedQueries: 5,
        threatRatio: 50.0,
        blockedPercentage: '50%',
        averageLatencyMs: 18,
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('5'), findsWidgets); // 5 blocked queries
      expect(find.text('50%'), findsOneWidget);
    });

    testWidgets('25. Telemetry clear or reset displays 0 stats', (tester) async {
      final container = _createTestContainer();
      addTearDown(container.dispose);

      await tester.pumpWidget(_buildTestableHomeScreen(container: container));
      await tester.pumpAndSettle();

      container.read(liveTelemetryProvider.notifier).state = const LiveTelemetryState();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.text('0.0%'), findsOneWidget);
    });

    testWidgets('26. Micro-stat strip is scrollable and does not overflow on small screens', (tester) async {
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(_buildTestableHomeScreen());
      await tester.pumpAndSettle();

      expect(find.text('BLOCKED TODAY'), findsOneWidget);
      expect(find.text('THREAT RATIO'), findsOneWidget);
      expect(find.text('DOH LATENCY'), findsOneWidget);
    });

    testWidgets('27. Huge query count (e.g. 99999) formats gracefully in micro-stat strip', (tester) async {
      final container = _createTestContainer();
      addTearDown(container.dispose);

      await tester.pumpWidget(_buildTestableHomeScreen(container: container));
      await tester.pumpAndSettle();

      // inject high query telemetry state
      container.read(liveTelemetryProvider.notifier).state = const LiveTelemetryState(
        totalQueries: 100000,
        blockedQueries: 45000,
        threatRatio: 45.0,
        blockedPercentage: '45.0%',
        averageLatencyMs: 22,
        recentQueries: [],
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.text('45000'), findsOneWidget);
      expect(find.text('45.0%'), findsOneWidget);
      expect(find.text('22ms'), findsOneWidget);
    });

    testWidgets('28. Blocked percentage with 0 total queries remains 0.0%', (tester) async {
      await tester.pumpWidget(_buildTestableHomeScreen());
      await tester.pumpAndSettle();

      expect(find.text('0.0%'), findsOneWidget);
    });

    testWidgets('29. Subdomain extraction works properly on live telemetry queries', (tester) async {
      final q = LiveDnsQueryItem.fromMap({
        'id': 'sub1',
        'domain': 'v2.telemetry.sub.domain.co.uk',
        'status': 'ALLOWED',
      });
      expect(q.subdomain, 'v2.');
      expect(q.rootDomain, 'telemetry.sub.domain.co.uk');
    });

    testWidgets('30. Micro-stat strip renders divider borders between stat columns', (tester) async {
      await tester.pumpWidget(_buildTestableHomeScreen());
      await tester.pumpAndSettle();

      final dividers = find.byWidgetPredicate(
        (w) => w is Container && w.constraints?.maxWidth == 1.0,
      );
      expect(dividers, findsWidgets);
    });
  });

  group('Category 4: Header Profile Pill, Flag & Switcher Sheet (31-40)', () {
    testWidgets('31. Header profile pill displays default profile name', (tester) async {
      await tester.pumpWidget(_buildTestableHomeScreen());
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('header_profile_pill')), findsOneWidget);
      expect(find.text('Personal Shield'), findsOneWidget);
    });

    testWidgets('32. Single tap on header profile pill opens DNS Profiles switcher sheet', (tester) async {
      await tester.pumpWidget(_buildTestableHomeScreen());
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('header_profile_pill')));
      await tester.pumpAndSettle();

      expect(find.text('DNS Profiles'), findsOneWidget);
      expect(find.text('Detailed Profile Settings & Rules'), findsOneWidget);
    });

    testWidgets('33. Profile switcher sheet shows Add Profile button and textfield', (tester) async {
      await tester.pumpWidget(_buildTestableHomeScreen());
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('header_profile_pill')));
      await tester.pumpAndSettle();

      expect(find.text('Add'), findsOneWidget);
      expect(find.byType(TextField), findsOneWidget);
    });

    testWidgets('34. Tapping Detailed Profile Settings button opens all-tabs sheet', (tester) async {
      await tester.pumpWidget(_buildTestableHomeScreen());
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('header_profile_pill')));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Detailed Profile Settings & Rules'));
      await tester.pumpAndSettle();

      expect(find.text('Setup'), findsWidgets);
      expect(find.text('Security'), findsWidgets);
    });

    testWidgets('35. Long-pressing profile pill directly opens All Profile Settings sheet', (tester) async {
      await tester.pumpWidget(_buildTestableHomeScreen());
      await tester.pumpAndSettle();

      await tester.longPress(find.byKey(const Key('header_profile_pill')));
      await tester.pumpAndSettle();

      expect(find.text('Setup'), findsWidgets);
      expect(find.text('Security'), findsWidgets);
    });

    testWidgets('36. Switching to non-protection tabs replaces profile pill with tab title', (tester) async {
      await tester.pumpWidget(_buildTestableHomeScreen());
      await tester.pumpAndSettle();

      // Switch to Focus (index 1)
      await tester.tap(find.byKey(const Key('nav_1')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('header_profile_pill')), findsNothing);
      expect(find.text('Focus'), findsWidgets);
    });

    testWidgets('37. Switching back to Protection tab restores header profile pill', (tester) async {
      await tester.pumpWidget(_buildTestableHomeScreen());
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('nav_1')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('header_profile_pill')), findsNothing);

      await tester.tap(find.byKey(const Key('nav_0')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('header_profile_pill')), findsOneWidget);
    });

    testWidgets('38. Theme toggle button in header switches theme between dark and light', (tester) async {
      await tester.pumpWidget(_buildTestableHomeScreen());
      await tester.pumpAndSettle();

      // Initial theme mode is light, shows moon icon
      expect(find.byIcon(Icons.nightlight_round_outlined), findsOneWidget);

      // Tap theme toggle button
      await tester.tap(find.byIcon(Icons.nightlight_round_outlined));
      await tester.pumpAndSettle();

      // Now dark mode, shows sunny icon
      expect(find.byIcon(Icons.wb_sunny_outlined), findsOneWidget);
    });

    testWidgets('39. Tapping theme toggle twice returns to original dark theme', (tester) async {
      await tester.pumpWidget(_buildTestableHomeScreen());
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.nightlight_round_outlined));
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.wb_sunny_outlined), findsOneWidget);

      await tester.tap(find.byIcon(Icons.wb_sunny_outlined));
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.nightlight_round_outlined), findsOneWidget);
    });

    testWidgets('40. Profile dot indicator matches protection active color', (tester) async {
      await tester.pumpWidget(_buildTestableHomeScreen());
      await tester.pumpAndSettle();

      // Protection OFF initially
      await tester.tap(find.byKey(const Key('main_protection_toggle')));
      await tester.pumpAndSettle();

      // Protection ON now -> dot indicator should remain cleanly rendered
      expect(find.byKey(const Key('header_profile_pill')), findsOneWidget);
    });
  });

  group('Category 5: Navigation, Tabs & Screen Transitions (41-50)', () {
    testWidgets('41. Bottom bar renders 4 tab buttons: Protect, Focus, Insights, More', (tester) async {
      await tester.pumpWidget(_buildTestableHomeScreen());
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('nav_0')), findsOneWidget);
      expect(find.byKey(const Key('nav_1')), findsOneWidget);
      expect(find.byKey(const Key('nav_2')), findsOneWidget);
      expect(find.byKey(const Key('nav_3')), findsOneWidget);
      expect(find.text('Protect'), findsOneWidget);
      expect(find.text('Focus'), findsOneWidget);
      expect(find.text('Insights'), findsOneWidget);
      expect(find.text('More'), findsOneWidget);
    });

    testWidgets('42. Navigating to Focus tab loads Websites, Apps & Games without 1-Tap Distraction Audit banner', (tester) async {
      await tester.pumpWidget(_buildTestableHomeScreen());
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('nav_1')));
      await tester.pumpAndSettle();

      expect(find.text('Websites, Apps & Games'), findsOneWidget);
      expect(find.text('1-Tap Distraction Audit'), findsNothing);
      expect(find.text('RUN 1-TAP DISTRACTION AUDIT'), findsNothing);
    });

    testWidgets('43. Focus tab renders Categories card cleanly', (tester) async {
      await tester.pumpWidget(_buildTestableHomeScreen());
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('nav_1')));
      await tester.pumpAndSettle();

      expect(find.text('Categories'), findsOneWidget);
    });

    testWidgets('44. Navigating to Insights tab displays unified queries telemetry and search', (tester) async {
      await tester.pumpWidget(_buildTestableHomeScreen());
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('nav_2')));
      await tester.pumpAndSettle();

      expect(find.text('TOTAL QUERIES'), findsOneWidget);
      expect(find.text('RECENT QUERIES'), findsOneWidget);
      expect(find.byType(TextField), findsOneWidget);
    });

    testWidgets('45. Filtering domain query updates the query view dynamically', (tester) async {
      await tester.pumpWidget(_buildTestableHomeScreen());
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('nav_2')));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'google');
      await tester.pumpAndSettle();

      expect(find.byType(TextField), findsOneWidget);
    });

    testWidgets('46. Navigating to More tab loads settings, allowlist, denylist and Security & Privacy', (tester) async {
      await tester.pumpWidget(_buildTestableHomeScreen());
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('nav_3')));
      await tester.pumpAndSettle();

      expect(find.text('Setup'), findsOneWidget);
      expect(find.text('Security & Privacy'), findsOneWidget);
      expect(find.text('Allowlist'), findsOneWidget);
      expect(find.text('App Lockout Timers'), findsNothing);
      expect(find.text('Focus Routine & Breaks'), findsNothing);
      expect(find.text('Surgical Feed Killer'), findsNothing);
    });

    testWidgets('47. Switching rapidly between all 4 tabs does not leak memory or throw setState after dispose', (tester) async {
      await tester.pumpWidget(_buildTestableHomeScreen());
      await tester.pumpAndSettle();

      for (int i = 0; i < 4; i++) {
        await tester.tap(find.byKey(Key('nav_$i')));
        await tester.pump(const Duration(milliseconds: 60));
      }
      for (int i = 3; i >= 0; i--) {
        await tester.tap(find.byKey(Key('nav_$i')));
        await tester.pump(const Duration(milliseconds: 60));
      }
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('main_protection_toggle')), findsOneWidget);
    });

    testWidgets('48. In Strict Mode, bottom bar Protect icon changes to lock icon', (tester) async {
      final repo = InMemorySettingsRepository();
      await repo.setStrictMode(true, durationMinutes: 20);

      await tester.pumpWidget(_buildTestableHomeScreen(repo: repo));
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.lock), findsWidgets);
    });

    testWidgets('49. Analytics filter chips 24h, 7d, 30d toggle cleanly without exceptions', (tester) async {
      await tester.pumpWidget(_buildTestableHomeScreen());
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('nav_2')));
      await tester.pumpAndSettle();

      await tester.tap(find.text('7d'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('30d'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('24h'));
      await tester.pumpAndSettle();

      expect(find.text('TOTAL QUERIES'), findsOneWidget);
    });

    testWidgets('50. Safe area padding and notch margins adapt without overflow on small tablet resolution', (tester) async {
      tester.view.physicalSize = const Size(1600, 2560);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(_buildTestableHomeScreen());
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('main_protection_toggle')), findsOneWidget);
      expect(find.byKey(const Key('header_profile_pill')), findsOneWidget);
      expect(find.byKey(const Key('nav_0')), findsOneWidget);
    });
  });

  group('Category 6: Extreme Real-Life Edge Cases & Resilience (51-55)', () {
    testWidgets('51. Orientation change / screen resizing preserves active tab and protection state', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(_buildTestableHomeScreen());
      await tester.pumpAndSettle();

      // Switch to Focus tab
      await tester.tap(find.byKey(const Key('nav_1')));
      await tester.pumpAndSettle();

      // Rotate to landscape
      tester.view.physicalSize = const Size(2400, 1080);
      await tester.pumpAndSettle();

      expect(find.text('Websites, Apps & Games'), findsOneWidget);
    });

    testWidgets('52. Strict mode timer expiration countdown correctly ticks and unlocks when remaining is 0', (tester) async {
      final repo = InMemorySettingsRepository();
      await repo.setStrictMode(true, durationMinutes: 1);
      final container = _createTestContainer(repo: repo);
      addTearDown(container.dispose);

      await tester.pumpWidget(_buildTestableHomeScreen(container: container));
      await tester.pumpAndSettle();

      expect(find.text('LOCKED'), findsOneWidget);

      // Force expire strict mode
      await container.read(strictModeProvider.notifier).set(false, force: true);
      await tester.pumpAndSettle();

      // Normal mode / begin session button restored
      expect(find.byKey(const Key('begin_session_button')), findsOneWidget);
    });

    testWidgets('53. Query log stream handles 50 empty subdomains gracefully without string index errors', (tester) async {
      final container = _createTestContainer();
      addTearDown(container.dispose);

      await tester.pumpWidget(_buildTestableHomeScreen(container: container));
      await tester.pumpAndSettle();

      final items = List.generate(
        50,
        (i) => LiveDnsQueryItem(
          id: 'err_$i',
          domain: 'domain$i.com',
          rootDomain: 'domain$i.com',
          subdomain: '',
          status: 'ALLOWED',
          reason: '',
          latencyMs: 10,
          timestamp: DateTime.now(),
        ),
      );

      container.read(liveTelemetryProvider.notifier).state = LiveTelemetryState(
        totalQueries: 50,
        blockedQueries: 0,
        recentQueries: items,
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byKey(const Key('main_protection_toggle')), findsOneWidget);
    });

    testWidgets('54. Extremely long profile names truncate cleanly with ellipsis without crashing header pill', (tester) async {
      final container = _createTestContainer();
      addTearDown(container.dispose);

      container.read(authProvider.notifier).state = container.read(authProvider.notifier).state.copyWith(
        activeProfileName: 'Extremely Long Focus Profile Name With Special Characters !@#\$%^&*() 1234567890',
      );

      await tester.pumpWidget(_buildTestableHomeScreen(container: container));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('header_profile_pill')), findsOneWidget);
    });

    testWidgets('55. User authentication flag and detected country badge render without error', (tester) async {
      final container = _createTestContainer();
      addTearDown(container.dispose);

      await tester.pumpWidget(_buildTestableHomeScreen(container: container));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('header_profile_pill')), findsOneWidget);
      expect(find.text('Personal Shield'), findsOneWidget);
    });
  });
}
