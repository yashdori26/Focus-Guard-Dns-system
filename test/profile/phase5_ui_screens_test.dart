import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:focus_dns/engine/profile/user_profile_model.dart';
import 'package:focus_dns/engine/profile/fleet_device_model.dart';
import 'package:focus_dns/engine/profile/cross_device_sync_coordinator.dart';
import 'package:focus_dns/engine/profile/accountability_partner_manager.dart';
import 'package:focus_dns/engine/analytics/attention_heatmap_matrix.dart';
import 'package:focus_dns/engine/analytics/streak_momentum_calculator.dart';
import 'package:focus_dns/engine/analytics/session_lifecycle_metrics.dart';
import 'package:focus_dns/engine/analytics/analytics_persistence_store.dart';
import 'package:focus_dns/frontend/widgets/analytics/attention_heatmap_canvas.dart';
import 'package:focus_dns/frontend/widgets/analytics/streak_momentum_visualizer.dart';
import 'package:focus_dns/frontend/widgets/analytics/dopamine_recovery_curve_chart.dart';
import 'package:focus_dns/frontend/widgets/fleet/fleet_device_card.dart';
import 'package:focus_dns/frontend/screens/fleet/fleet_orchestration_master_screen.dart';
import 'package:focus_dns/frontend/screens/fleet/browser_extension_pairing_screen.dart';
import 'package:focus_dns/frontend/screens/analytics/longitudinal_analytics_master_screen.dart';
import 'package:focus_dns/frontend/screens/profile/accountability_partner_screen.dart';
import 'package:focus_dns/frontend/screens/profile/profile_hub_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('Phase 5 UI Widgets & Screens Tests', () {
    testWidgets('1. AttentionHeatmapCanvas renders without error', (tester) async {
      final matrix = AttentionHeatmapMatrix.empty();
      matrix.recordInterception(DateTime(2026, 11, 6, 22, 0), 5);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AttentionHeatmapCanvas(matrix: matrix),
          ),
        ),
      );

      expect(find.byType(AttentionHeatmapCanvas), findsOneWidget);
      expect(find.byType(CustomPaint), findsWidgets);
    });

    testWidgets('2. StreakMomentumVisualizer renders flame, streak days, and momentum', (tester) async {
      final record = StreakRecord(
        currentStreakDays: 18,
        longestStreakDays: 25,
        freezeTokensRemaining: 1,
        dailyAdherenceScores: {},
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StreakMomentumVisualizer(
              streakRecord: record,
              momentumScore: 84.5,
            ),
          ),
        ),
      );

      expect(find.text('18 Days'), findsOneWidget);
      expect(find.text('84'), findsOneWidget);
      expect(find.text('MOMENTUM'), findsOneWidget);
      expect(find.text('ANNUAL FOCUS HABIT MATRIX'), findsOneWidget);
    });

    testWidgets('3. DopamineRecoveryCurveChart renders clinical stage badge', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: DopamineRecoveryCurveChart(currentDaysClean: 14),
          ),
        ),
      );

      expect(find.text('SYNAPTIC PRUNING'), findsOneWidget);
      expect(find.text('Day 14 of 30'), findsOneWidget);
      expect(find.byType(CustomPaint), findsWidgets);
    });

    testWidgets('4. FleetDeviceCard renders device metadata and lock action', (tester) async {
      final dev = FleetDeviceModel(
        deviceId: 'pixel_8',
        deviceName: 'Pixel 8 Pro',
        platform: FleetPlatformType.android,
        clientVersion: '2.0.0',
        lastHeartbeat: DateTime.now(),
        isOnline: true,
        activeMode: 'focus',
        isStrictLockActive: true,
        sessionRemainingSeconds: 25 * 60,
        distractionsBlockedToday: 42,
        minutesReclaimedToday: 50,
        batteryPercentage: 85,
        isCharging: false,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: FleetDeviceCard(device: dev),
          ),
        ),
      );

      expect(find.text('Pixel 8 Pro'), findsOneWidget);
      expect(find.text('🔒 STRICT LOCK ACTIVE'), findsOneWidget);
      expect(find.text('42'), findsOneWidget);
      expect(find.text('50m'), findsOneWidget);
      expect(find.text('85%'), findsOneWidget);
      expect(find.text('🔒 Lock 30m'), findsOneWidget);
    });

    testWidgets('5. FleetOrchestrationMasterScreen renders header, buttons, and node cards', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      addTearDown(tester.view.resetPhysicalSize);

      final coordinator = CrossDeviceSyncCoordinator(
        userId: 'usr_test',
        localDeviceId: 'dev_local',
      );
      coordinator.start();
      coordinator.stop();

      await tester.pumpWidget(
        MaterialApp(
          home: FleetOrchestrationMasterScreen(coordinator: coordinator),
        ),
      );
      await tester.pump();

      expect(find.text('Fleet Orchestration'), findsOneWidget);
      expect(find.text('FLEET-WIDE BROADCAST DISPATCHER'), findsOneWidget);
      expect(find.text('Online Nodes'), findsOneWidget);
      expect(find.text('Lock All (3 Nodes)'), findsOneWidget);
      coordinator.dispose();
    });

    testWidgets('6. BrowserExtensionPairingScreen renders QR canvas and manual token', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: BrowserExtensionPairingScreen(userId: 'usr_pair_test'),
        ),
      );

      expect(find.text('Extension Pairing Studio'), findsOneWidget);
      expect(find.text('SCAN TO PAIR EXTENSION'), findsOneWidget);
      expect(find.text('MANUAL 6-DIGIT CODE'), findsOneWidget);

      await tester.drag(find.byType(ListView), const Offset(0, -400));
      await tester.pump();
      expect(find.text('INSTALLATION STEPS'), findsOneWidget);
    });

    testWidgets('7. LongitudinalAnalyticsMasterScreen renders KPI tiles and tabs', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      addTearDown(tester.view.resetPhysicalSize);

      final store = await AnalyticsPersistenceStore.create();
      await store.recordDailyMetrics(
        DateTime.now(),
        SessionLifecycleMetrics.empty().copyWith(
          sessionsInitiated: 6,
          sessionsCompleted: 6,
          totalFocusMinutes: 180,
          totalDistractionInterceptions: 50,
        ),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: LongitudinalAnalyticsMasterScreen(store: store),
        ),
      );
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('Longitudinal Analytics'), findsOneWidget);
      expect(find.text('HOURS RECLAIMED'), findsOneWidget);
      expect(find.text('3.0h'), findsOneWidget);
      expect(find.text('ADHERENCE RATE'), findsOneWidget);
      expect(find.text('100.0%'), findsOneWidget);

      await tester.drag(find.byType(ListView), const Offset(0, -1000));
      await tester.pump();
      await tester.drag(find.byType(ListView), const Offset(0, -1000));
      await tester.pump();
      expect(find.text('Export Clinical Focus Audit'), findsOneWidget);
    });

    testWidgets('8. AccountabilityPartnerScreen renders partner profile and trust rating', (tester) async {
      final manager = await AccountabilityPartnerManager.create();
      await manager.assignPartner(name: 'Marcus Aurelius', email: 'marcus@stoic.org');

      await tester.pumpWidget(
        MaterialApp(
          home: AccountabilityPartnerScreen(manager: manager),
        ),
      );

      expect(find.text('Accountability Partner'), findsOneWidget);
      expect(find.text('Marcus Aurelius'), findsOneWidget);
      expect(find.text('marcus@stoic.org'), findsOneWidget);
      expect(find.text('✓ Verified Guardian'), findsOneWidget);
      expect(find.text('Guardian Trust Rating'), findsOneWidget);
    });

    testWidgets('9. ProfileHubScreen renders archetype selector and security policies', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      addTearDown(tester.view.resetPhysicalSize);

      final profile = UserProfileModel.initial(displayName: 'Neo');
      final coordinator = CrossDeviceSyncCoordinator(userId: 'u1', localDeviceId: 'd1');
      coordinator.stop();
      final manager = await AccountabilityPartnerManager.create();
      final store = await AnalyticsPersistenceStore.create();

      await tester.pumpWidget(
        MaterialApp(
          home: ProfileHubScreen(
            initialProfile: profile,
            syncCoordinator: coordinator,
            partnerManager: manager,
            analyticsStore: store,
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('Neo'), findsOneWidget);
      expect(find.text('FOCUS ARCHETYPE'), findsOneWidget);
      expect(find.text('LIFETIME FOCUS SOVEREIGNTY'), findsOneWidget);
      expect(find.text('CROSS-DEVICE ECOSYSTEM'), findsOneWidget);
      expect(find.text('Device Fleet Console'), findsOneWidget);

      await tester.drag(find.byType(ListView), const Offset(0, -500));
      await tester.pump();
      expect(find.text('ANTI-TAMPER SECURITY POLICIES'), findsOneWidget);

      coordinator.dispose();
    });
  });
}
