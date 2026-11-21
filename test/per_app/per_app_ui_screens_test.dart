import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:focus_dns/engine/per_app/catalog/comprehensive_app_catalog.dart';
import 'package:focus_dns/engine/per_app/core/per_app_coordinator.dart';
import 'package:focus_dns/engine/per_app/models/friction_challenge_model.dart';
import 'package:focus_dns/frontend/screens/per_app/app_detail_config_screen.dart';
import 'package:focus_dns/frontend/screens/per_app/batch_lock_studio_screen.dart';
import 'package:focus_dns/frontend/screens/per_app/daily_quota_studio_screen.dart';
import 'package:focus_dns/frontend/screens/per_app/friction_challenge_screen.dart';
import 'package:focus_dns/frontend/screens/per_app/overlay_customizer_screen.dart';
import 'package:focus_dns/frontend/screens/per_app/per_app_main_studio_screen.dart';
import 'package:focus_dns/frontend/screens/per_app/recurring_schedules_screen.dart';
import 'package:focus_dns/frontend/widgets/per_app/dopamine_risk_gauge.dart';
import 'package:focus_dns/frontend/widgets/per_app/duration_wheel_picker.dart';
import 'package:focus_dns/frontend/widgets/per_app/usage_hourly_bar_chart.dart';
import 'package:focus_dns/frontend/widgets/per_app/week_schedule_grid.dart';
import 'package:shared_preferences/shared_preferences.dart';

Widget _wrap(Widget child) {
  return MaterialApp(
    theme: ThemeData.dark(),
    home: Scaffold(body: child),
  );
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('Per-App UI Screens & Custom Visuals Widget Tests', () {
    testWidgets('1. DopamineRiskGauge renders risk score and level badge', (tester) async {
      await tester.pumpWidget(_wrap(const DopamineRiskGauge(score: 98)));
      expect(find.text('98'), findsOneWidget);
      expect(find.text('EXTREME TRAP'), findsOneWidget);
    });

    testWidgets('2. UsageHourlyBarChart renders without layout overflow', (tester) async {
      final dummy24 = List.generate(24, (i) => i * 100);
      await tester.pumpWidget(_wrap(UsageHourlyBarChart(hourlyUsageSeconds: dummy24)));
      expect(find.text('12 AM'), findsOneWidget);
      expect(find.text('12 PM'), findsOneWidget);
    });

    testWidgets('3. WeekScheduleGrid allows day selection toggling', (tester) async {
      List<int> selected = [1, 3, 5]; // M, W, F
      await tester.pumpWidget(_wrap(StatefulBuilder(
        builder: (context, setState) {
          return WeekScheduleGrid(
            selectedDays: selected,
            onSelectionChanged: (updated) => setState(() => selected = updated),
          );
        },
      )));

      expect(find.text('M'), findsOneWidget);
      expect(find.text('T'), findsNWidgets(2)); // Tuesday and Thursday
      // Tap on 'S' (Saturday, index 6)
      await tester.tap(find.text('S').first);
      await tester.pump();
      expect(selected, contains(6));
    });

    testWidgets('4. DurationWheelPicker selects presets and changes duration', (tester) async {
      int minutes = 120;
      await tester.pumpWidget(_wrap(StatefulBuilder(
        builder: (context, setState) {
          return DurationWheelPicker(
            selectedMinutes: minutes,
            onDurationChanged: (m) => setState(() => minutes = m),
          );
        },
      )));

      expect(find.text('Lock Duration'), findsOneWidget);
      expect(find.text('2 hrs'), findsWidgets);

      // Tap 4 hrs chip
      await tester.tap(find.text('4 hrs'));
      await tester.pump();
      expect(minutes, equals(240));
    });

    testWidgets('5. PerAppMainStudioScreen renders hero stats, category chips, and apps', (tester) async {
      final coordinator = PerAppCoordinator(enableAutomaticTicker: false);
      await tester.pumpWidget(_wrap(PerAppMainStudioScreen(coordinator: coordinator)));
      await tester.pumpAndSettle();

      expect(find.text('Per-App Lockout Studio'), findsOneWidget);
      expect(find.text('MONITORED'), findsOneWidget);
      expect(find.text('ACTIVE LOCKS'), findsOneWidget);
      expect(find.text('All Apps'), findsOneWidget);
      expect(find.text('Short-Form Video'), findsWidgets);
    });

    testWidgets('6. BatchLockStudioScreen renders category action tiles', (tester) async {
      final coordinator = PerAppCoordinator(enableAutomaticTicker: false);
      await tester.pumpWidget(_wrap(BatchLockStudioScreen(coordinator: coordinator)));
      await tester.pumpAndSettle();

      expect(find.text('Batch Category Locks'), findsOneWidget);
      expect(find.text('Lock All Short-Form Video'), findsOneWidget);
      expect(find.text('Lock All Social Networks'), findsOneWidget);
      expect(find.text('Block All Adult & 18+ Content'), findsOneWidget);
    });

    testWidgets('7. DailyQuotaStudioScreen renders rollover countdown and quota cards', (tester) async {
      final coordinator = PerAppCoordinator(enableAutomaticTicker: false);
      await tester.pumpWidget(_wrap(DailyQuotaStudioScreen(coordinator: coordinator)));
      await tester.pumpAndSettle();

      expect(find.text('Daily Quota Allowances'), findsOneWidget);
      expect(find.text('Automatic Midnight Rollover'), findsOneWidget);
    });

    testWidgets('8. RecurringSchedulesScreen renders weekly focus scheduler', (tester) async {
      final coordinator = PerAppCoordinator(enableAutomaticTicker: false);
      await tester.pumpWidget(_wrap(RecurringSchedulesScreen(coordinator: coordinator)));
      await tester.pumpAndSettle();

      expect(find.text('Weekly Focus Schedules'), findsOneWidget);
      expect(find.text('Automated Calendar Blocks'), findsOneWidget);
    });

    testWidgets('9. AppDetailConfigScreen renders app policies, sliders, and productive swaps', (tester) async {
      final coordinator = PerAppCoordinator(enableAutomaticTicker: false);
      final insta = ComprehensiveAppCatalog.allDefinitions.first;

      await tester.pumpWidget(_wrap(AppDetailConfigScreen(
        definition: insta,
        coordinator: coordinator,
      )));
      await tester.pumpAndSettle();

      expect(find.text(insta.name), findsWidgets);
      expect(find.text('Enforcement Policy'), findsOneWidget);
      expect(find.text('Timer Lock'), findsOneWidget);
      expect(find.text('Strictness Level'), findsOneWidget);
      expect(find.text('Recommended Productive Swap'), findsOneWidget);
      expect(find.text('APPLY FOCUS RULES'), findsOneWidget);
    });

    testWidgets('10. FrictionChallengeScreen renders oath textfield and validation', (tester) async {
      final oathChallenge = FrictionChallenge.createOathChallenge();
      bool passed = false;

      await tester.pumpWidget(_wrap(FrictionChallengeScreen(
        challenge: oathChallenge,
        appName: 'TikTok',
        onChallengePassed: () => passed = true,
      )));
      await tester.pumpAndSettle();

      expect(find.text('Unlock Challenge: TikTok'), findsOneWidget);
      expect(find.text(oathChallenge.requiredOathText!), findsOneWidget);
      expect(find.text('CONFIRM & PROCEED'), findsOneWidget);

      // Submit incorrect oath
      await tester.enterText(find.byType(TextField), 'wrong oath text');
      await tester.tap(find.text('CONFIRM & PROCEED'));
      await tester.pumpAndSettle();
      expect(passed, isFalse);

      // Submit correct oath
      await tester.enterText(find.byType(TextField), oathChallenge.requiredOathText!);
      await tester.tap(find.text('CONFIRM & PROCEED'));
      await tester.pumpAndSettle();
      expect(passed, isTrue);
    });

    testWidgets('11. OverlayCustomizerScreen renders live HUD preview and theme options', (tester) async {
      await tester.pumpWidget(_wrap(const OverlayCustomizerScreen()));
      await tester.pumpAndSettle();

      expect(find.text('Lockout Overlay HUD Customizer'), findsOneWidget);
      expect(find.text('Live HUD Preview'), findsOneWidget);
      expect(find.text('Instagram is Strictly Locked'), findsOneWidget);
      expect(find.text('Cyberpunk'), findsOneWidget);
      expect(find.text('Forest Zen'), findsOneWidget);
    });
  });
}
