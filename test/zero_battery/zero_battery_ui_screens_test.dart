import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:focus_dns/engine/daemon/oem/oem_device_profiles.dart';
import 'package:focus_dns/engine/daemon/telemetry/oem_resilience_auditor.dart';
import 'package:focus_dns/engine/daemon/telemetry/power_historian_recorder.dart';
import 'package:focus_dns/frontend/screens/zero_battery/battery_drain_histogram_screen.dart';
import 'package:focus_dns/frontend/screens/zero_battery/battery_stress_benchmark_screen.dart';
import 'package:focus_dns/frontend/screens/zero_battery/oem_exemption_wizard_screen.dart';
import 'package:focus_dns/frontend/screens/zero_battery/power_profile_config_screen.dart';
import 'package:focus_dns/frontend/screens/zero_battery/wake_lock_audit_screen.dart';
import 'package:focus_dns/frontend/screens/zero_battery/zero_battery_master_studio_screen.dart';
import 'package:focus_dns/frontend/widgets/zero_battery/energy_radial_meter.dart';
import 'package:focus_dns/frontend/widgets/zero_battery/oem_brand_card.dart';
import 'package:focus_dns/frontend/widgets/zero_battery/oem_survival_scorecard.dart';
import 'package:focus_dns/frontend/widgets/zero_battery/power_timeline_chart.dart';

void main() {
  Widget wrapWidget(Widget child) {
    return MaterialApp(
      home: Scaffold(
        body: child,
      ),
    );
  }

  group('Zero-Battery Custom Visual Widgets Tests', () {
    testWidgets('1. EnergyRadialMeter renders power draw and percentage text', (tester) async {
      await tester.pumpWidget(wrapWidget(
        const EnergyRadialMeter(
          dailyDrainPercentage: 0.85,
          currentDrawMicroamps: 140.0,
        ),
      ));

      expect(find.text('0.85%'), findsOneWidget);
      expect(find.text('ESTIMATED / 24H'), findsOneWidget);
      expect(find.text('140 µA CURRENT DRAW'), findsOneWidget);
    });

    testWidgets('2. PowerTimelineChart renders without layout overflow', (tester) async {
      final entries = PowerHistorianRecorder().history;
      await tester.pumpWidget(wrapWidget(
        PowerTimelineChart(entries: entries),
      ));

      expect(find.text('24-HOUR POWER PROFILE'), findsOneWidget);
      expect(find.text('FocusDNS (<1%)'), findsOneWidget);
      expect(find.text('Typical VPN (~15%)'), findsOneWidget);
    });

    testWidgets('3. OemSurvivalScorecard renders total score and hardening button', (tester) async {
      const scorecard = OemAuditScorecard(
        totalScore: 85,
        tier: ResilienceTier.hardened,
        autostartScore: 35,
        dozeScore: 30,
        recentsLockScore: 0,
        permissionsScore: 20,
        outstandingVulnerabilities: ['Lock app in recents'],
        verifiedShields: ['Doze active', 'Autostart active'],
      );

      await tester.pumpWidget(wrapWidget(
        OemSurvivalScorecard(
          scorecard: scorecard,
          onFixVulnerabilities: () {},
        ),
      ));

      expect(find.text('85'), findsOneWidget);
      expect(find.text('HARDENED SHIELD'), findsOneWidget);
      expect(find.text('HARDEN DEVICE PROTECTION'), findsOneWidget);
    });

    testWidgets('4. OemBrandCard renders brand information and severity badge', (tester) async {
      await tester.pumpWidget(wrapWidget(
        OemBrandCard(
          profile: OemDeviceProfiles.xiaomi,
          romVersion: 'HyperOS 1.0',
          onLaunchWizard: () {},
        ),
      ));

      expect(find.text('Xiaomi / Redmi / POCO'), findsOneWidget);
      expect(find.text('HyperOS 1.0'), findsOneWidget);
      expect(find.text('Extreme Hostility'), findsOneWidget);
      expect(find.text('OPEN STEP-BY-STEP SETUP WIZARD'), findsOneWidget);
    });
  });

  group('Zero-Battery Flutter Studio Screens Tests', () {
    testWidgets('5. ZeroBatteryMasterStudioScreen renders master dashboard elements', (tester) async {
      tester.view.physicalSize = const Size(1200, 2400);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(const MaterialApp(
        home: ZeroBatteryMasterStudioScreen(),
      ));
      await tester.pumpAndSettle();

      expect(find.text('Zero-Battery Daemon Studio'), findsOneWidget);
      expect(find.text('HARDWARE & KERNEL AUDIT'), findsOneWidget);
      expect(find.text('WAKE-LOCKS'), findsOneWidget);
      expect(find.text('ROUTE ISOLATION'), findsOneWidget);
      expect(find.text('RING BUFFERS'), findsOneWidget);
      expect(find.text('DOZE EXEMPTION'), findsOneWidget);
      expect(find.text('24-Hour Drain Histogram'), findsOneWidget);
      expect(find.text('Zero Wake-Lock Inspector'), findsOneWidget);
    });

    testWidgets('6. OemExemptionWizardScreen renders steps and allows step toggling', (tester) async {
      tester.view.physicalSize = const Size(1200, 2400);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(const MaterialApp(
        home: OemExemptionWizardScreen(),
      ));
      await tester.pumpAndSettle();

      expect(find.text('OEM Hardening Wizard'), findsOneWidget);
      expect(find.text('ACTIONABLE HARDENING STEPS'), findsOneWidget);
      expect(find.byType(Checkbox), findsWidgets);

      // Tap first step checkbox
      await tester.tap(find.byType(Checkbox).first);
      await tester.pumpAndSettle();
    });

    testWidgets('7. BatteryDrainHistogramScreen renders hourly summary', (tester) async {
      await tester.pumpWidget(const MaterialApp(
        home: BatteryDrainHistogramScreen(),
      ));
      await tester.pumpAndSettle();

      expect(find.text('24-Hour Drain Histogram'), findsOneWidget);
      expect(find.text('TOTAL 24-HOUR DRAIN'), findsOneWidget);
      expect(find.text('PEAK HOURLY RATE'), findsOneWidget);
    });

    testWidgets('8. WakeLockAuditScreen renders compliance card and policies', (tester) async {
      await tester.pumpWidget(const MaterialApp(
        home: WakeLockAuditScreen(),
      ));
      await tester.pumpAndSettle();

      expect(find.text('Zero Wake-Lock Inspector'), findsOneWidget);
      expect(find.text('100% ZERO-WAKE COMPLIANT'), findsOneWidget);
      expect(find.text('POLICY GUARANTEES'), findsOneWidget);
      expect(find.text('No CPU Sleep Prevention'), findsOneWidget);
    });

    testWidgets('9. PowerProfileConfigScreen switches power modes and saves', (tester) async {
      await tester.pumpWidget(const MaterialApp(
        home: PowerProfileConfigScreen(),
      ));
      await tester.pumpAndSettle();

      expect(find.text('Power Profile Settings'), findsOneWidget);
      expect(find.text('Ultra-Battery Saver'), findsOneWidget);
      expect(find.text('Balanced (Recommended)'), findsOneWidget);
      expect(find.text('High-Frequency Strict Focus'), findsOneWidget);

      // Tap Ultra-Battery Saver
      await tester.tap(find.text('Ultra-Battery Saver'));
      await tester.pumpAndSettle();

      // Tap save
      await tester.tap(find.text('SAVE POWER PROFILE'));
      await tester.pump();
    });

    testWidgets('10. BatteryStressBenchmarkScreen renders simulation scale chips', (tester) async {
      await tester.pumpWidget(const MaterialApp(
        home: BatteryStressBenchmarkScreen(),
      ));
      await tester.pumpAndSettle();

      expect(find.text('Battery Stress Benchmark'), findsOneWidget);
      expect(find.text('SIMULATION SCALE'), findsOneWidget);
      expect(find.text('5K Packets'), findsOneWidget);
      expect(find.text('10K Packets'), findsOneWidget);
      expect(find.text('50K Packets'), findsOneWidget);
      expect(find.text('START STRESS BENCHMARK'), findsOneWidget);

      // Tap start benchmark
      await tester.tap(find.text('START STRESS BENCHMARK'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();

      expect(find.text('BENCHMARK AUDIT RESULTS'), findsOneWidget);
      expect(find.text('PASSED < 1.0%'), findsOneWidget);
    });
  });
}
