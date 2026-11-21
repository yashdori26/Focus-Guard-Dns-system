import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:focus_dns/frontend/tabs/deep_focus_tab.dart';
import 'package:focus_dns/frontend/theme/wabi_sabi_theme.dart';
import 'package:focus_dns/frontend/more_screen.dart';
import 'package:focus_dns/state_management/providers.dart';
import 'package:focus_dns/state_management/protection_state.dart';
import 'package:focus_dns/models/app_models.dart';

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

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });
  testWidgets('DeepFocusTab in normal mode renders delete buttons', (tester) async {
    final container = ProviderContainer(
      overrides: [
        strictModeProvider.overrideWith((ref) => MockStrictModeNotifier(false)),
      ],
    );
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

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: WabiSabiTheme.darkTheme,
          home: const Scaffold(
            body: SingleChildScrollView(
              child: DeepFocusTab(),
            ),
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('Websites, Apps & Games'), findsOneWidget);
    expect(find.text('Reddit'), findsOneWidget);
    expect(find.text('Categories'), findsOneWidget);
    expect(find.text('Piracy & Torrents'), findsOneWidget);

    // In normal mode, delete buttons must be present!
    expect(find.byIcon(Icons.close_rounded), findsWidgets);
    expect(find.byIcon(Icons.lock_outline_rounded), findsNothing);
  });

  testWidgets('DeepFocusTab in strict mode hides delete buttons and displays lock icons', (tester) async {
    final container = ProviderContainer(
      overrides: [
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
    container.read(deepFocusProvider.notifier).addCategory(const BlockedItem(
      id: 'piracy',
      name: 'Piracy & Torrents',
      icon: '🏴‍☠️',
    ));

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: WabiSabiTheme.darkTheme,
          home: const Scaffold(
            body: SingleChildScrollView(
              child: DeepFocusTab(),
            ),
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('Websites, Apps & Games'), findsOneWidget);
    expect(find.text('Reddit'), findsOneWidget);
    expect(find.text('Categories'), findsOneWidget);

    // That option to delete the app should NOT come when strict mode is active!
    expect(find.byIcon(Icons.close_rounded), findsNothing);
    // Lock icons must be shown instead
    expect(find.byIcon(Icons.lock_outline_rounded), findsWidgets);
  });

  testWidgets('MoreTab shows uninstall app option in normal mode', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          strictModeProvider.overrideWith((ref) => MockStrictModeNotifier(false)),
        ],
        child: MaterialApp(
          theme: WabiSabiTheme.darkTheme,
          home: const Scaffold(
            body: MoreTab(palette: WabiSabiPalette.dark),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('more_uninstall_app_tile')), findsOneWidget);
    expect(find.text('Uninstall FocusDNS'), findsOneWidget);
  });

  testWidgets('MoreTab hides uninstall app option in strict mode', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          strictModeProvider.overrideWith((ref) => MockStrictModeNotifier(true)),
        ],
        child: MaterialApp(
          theme: WabiSabiTheme.darkTheme,
          home: const Scaffold(
            body: MoreTab(palette: WabiSabiPalette.dark),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('more_uninstall_app_tile')), findsNothing);
  });

  testWidgets('Tapping ADD A WEBSITE, APP OR GAME opens dynamic device apps picker and blocks selected app', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          strictModeProvider.overrideWith((ref) => MockStrictModeNotifier(false)),
        ],
        child: MaterialApp(
          theme: WabiSabiTheme.darkTheme,
          home: const Scaffold(
            body: SingleChildScrollView(
              child: DeepFocusTab(),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // 1. Verify "ADD A WEBSITE, APP OR GAME" button exists and tap it
    final addBtn = find.text('ADD A WEBSITE, APP OR GAME');
    expect(addBtn, findsOneWidget);
    await tester.tap(addBtn);
    await tester.pumpAndSettle();

    // 2. Dynamic modal is now open!
    expect(find.text('Block App or Website'), findsOneWidget);
    expect(find.textContaining('distracting apps'), findsOneWidget);

    // 3. Verify top distracting apps are displayed dynamically
    expect(find.text('YouTube'), findsOneWidget);

    // 4. Tap BLOCK on first available app (YouTube)
    final blockBtns = find.widgetWithText(ElevatedButton, 'BLOCK');
    expect(blockBtns, findsWidgets);
    await tester.tap(blockBtns.first);
    await tester.pumpAndSettle();

    // 5. Close modal
    await tester.tap(find.byKey(const Key('modal_close_button')));
    await tester.pumpAndSettle();

    // 6. Verify YouTube is now in the blocked items list
    expect(find.text('YouTube'), findsOneWidget);
  });
}

