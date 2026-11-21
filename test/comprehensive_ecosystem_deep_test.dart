import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:focus_dns/engine/routine/routine_state_machine.dart';
import 'package:focus_dns/engine/routine/routine_persistence_journal.dart';
import 'package:focus_dns/engine/routine/routine_audio_alert_manager.dart';
import 'package:focus_dns/engine/per_app/per_app_database.dart';
import 'package:focus_dns/engine/per_app/installed_apps_catalog.dart';
import 'package:focus_dns/engine/per_app/per_app_scheduler.dart';
import 'package:focus_dns/engine/surgical/surgical_domain_definitions.dart';
import 'package:focus_dns/engine/surgical/surgical_pattern_compiler.dart';
import 'package:focus_dns/engine/analytics/longitudinal_database.dart';
import 'package:focus_dns/engine/analytics/habit_psychology_calculator.dart';
import 'package:focus_dns/services/battery_telemetry_service.dart';

import 'package:focus_dns/frontend/screens/routine_focus_studio_screen.dart';
import 'package:focus_dns/frontend/screens/per_app_manager_screen.dart';
import 'package:focus_dns/frontend/screens/battery_shield_screen.dart';
import 'package:focus_dns/frontend/screens/surgical_feed_studio_screen.dart';
import 'package:focus_dns/frontend/screens/longitudinal_analytics_dashboard_screen.dart';
import 'package:focus_dns/frontend/theme/wabi_sabi_theme.dart';

Widget _wrapScreen(Widget screen) {
  return ProviderScope(
    child: MaterialApp(
      theme: WabiSabiTheme.darkTheme,
      home: screen,
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('Phase 1: Routine State Machine & Anti-Doomscroll Engine', () {
    test('1. RoutineScheduleConfig enforces hard ceiling of 30 minutes on break duration', () {
      const config = RoutineScheduleConfig(breakMinutes: 45); // Attempts 45 mins
      expect(config.breakMinutes, equals(30)); // Clamped to 30

      final updated = config.copyWith(breakMinutes: 60);
      expect(updated.breakMinutes, equals(30));

      final safe = config.copyWith(breakMinutes: 15);
      expect(safe.breakMinutes, equals(15));
    });

    test('2. RoutineScheduleConfig presets verify recommended scientific intervals', () {
      expect(RoutineScheduleConfig.pomodoro.focusMinutes, equals(25));
      expect(RoutineScheduleConfig.pomodoro.breakMinutes, equals(5));

      expect(RoutineScheduleConfig.deepFlow.focusMinutes, equals(50));
      expect(RoutineScheduleConfig.deepFlow.breakMinutes, equals(10));

      expect(RoutineScheduleConfig.ultraNinety.focusMinutes, equals(90));
      expect(RoutineScheduleConfig.ultraNinety.breakMinutes, equals(20));

      expect(RoutineScheduleConfig.marathonFourHour.breakMinutes, equals(30));
    });

    test('3. RoutineScheduleConfig correctly serializes to and from JSON', () {
      const config = RoutineScheduleConfig(focusMinutes: 45, breakMinutes: 10, totalCycles: 3);
      final json = config.toJson();
      final restored = RoutineScheduleConfig.fromJson(json);

      expect(restored.focusMinutes, equals(45));
      expect(restored.breakMinutes, equals(10));
      expect(restored.totalCycles, equals(3));
    });

    test('4. RoutineStateMachine starts in idle state and enters preparation grace on startRoutine', () {
      final fsm = RoutineStateMachine(enableAutomaticTicker: false);
      expect(fsm.snapshot.phase, equals(RoutinePhaseState.idle));
      expect(fsm.snapshot.isRunning, isFalse);

      fsm.startRoutine();
      expect(fsm.snapshot.phase, equals(RoutinePhaseState.preparationGrace));
      expect(fsm.snapshot.isRunning, isTrue);
      expect(fsm.snapshot.remainingSecondsInPhase, equals(fsm.snapshot.config.preparationGraceSeconds));
    });

    test('5. Expiration of preparation grace transitions into focusSession cycle 1', () {
      final fsm = RoutineStateMachine(enableAutomaticTicker: false);
      fsm.startRoutine();

      fsm.advancePhaseForTesting();
      expect(fsm.snapshot.phase, equals(RoutinePhaseState.focusSession));
      expect(fsm.snapshot.isFocusActive, isTrue);
      expect(fsm.snapshot.currentCycle, equals(1));
      expect(fsm.snapshot.remainingSecondsInPhase, equals(25 * 60));
    });

    test('6. Expiration of focusSession transitions into micro-break with max 30m clamp', () {
      final fsm = RoutineStateMachine(
        config: const RoutineScheduleConfig(focusMinutes: 50, breakMinutes: 10),
        enableAutomaticTicker: false,
      );
      fsm.startRoutine();
      fsm.advancePhaseForTesting(); // enters focusSession

      fsm.advancePhaseForTesting(); // focus session expires -> enters breakSession
      expect(fsm.snapshot.phase, equals(RoutinePhaseState.breakSession));
      expect(fsm.snapshot.isBreakActive, isTrue);
      expect(fsm.snapshot.remainingSecondsInPhase, equals(10 * 60));
    });

    test('7. Expiration of break enters 30-second breakExpiringGrace warning period', () {
      final fsm = RoutineStateMachine(enableAutomaticTicker: false);
      fsm.startRoutine();
      fsm.advancePhaseForTesting(); // prep -> focus
      fsm.advancePhaseForTesting(); // focus -> break

      fsm.advancePhaseForTesting(); // break -> breakExpiringGrace
      expect(fsm.snapshot.phase, equals(RoutinePhaseState.breakExpiringGrace));
      expect(fsm.snapshot.remainingSecondsInPhase, equals(30));
    });

    test('8. Expiration of breakExpiringGrace executes app termination sweep and advances cycle', () async {
      bool killExecuted = false;
      final fsm = RoutineStateMachine(
        config: const RoutineScheduleConfig(focusMinutes: 25, breakMinutes: 5, totalCycles: 3),
        enableAutomaticTicker: false,
        onForegroundAppKill: () async {
          killExecuted = true;
        },
      );
      fsm.startRoutine();
      fsm.advancePhaseForTesting(); // prep -> focus (cycle 1)
      fsm.advancePhaseForTesting(); // focus -> break (cycle 1)
      fsm.advancePhaseForTesting(); // break -> grace (cycle 1)

      fsm.advancePhaseForTesting(); // grace -> appTerminationSweep -> cycleAdvance -> focus (cycle 2)

      expect(killExecuted, isTrue);
      expect(fsm.snapshot.currentCycle, equals(2));
      expect(fsm.snapshot.phase, equals(RoutinePhaseState.focusSession));
      expect(fsm.snapshot.totalInterventionKills, equals(1));
    });

    test('9. Full execution of all configured cycles transitions cleanly to routineCompleted', () {
      final fsm = RoutineStateMachine(
        config: const RoutineScheduleConfig(focusMinutes: 25, breakMinutes: 5, totalCycles: 1),
        enableAutomaticTicker: false,
      );
      fsm.startRoutine();
      fsm.advancePhaseForTesting(); // prep -> focus (cycle 1)
      fsm.advancePhaseForTesting(); // focus -> break (cycle 1)
      fsm.advancePhaseForTesting(); // break -> grace (cycle 1)
      fsm.advancePhaseForTesting(); // grace -> completed

      expect(fsm.snapshot.phase, equals(RoutinePhaseState.routineCompleted));
      expect(fsm.snapshot.isRunning, isFalse);
    });

    test('10. Strict lockout mode rejects cancelRoutine while active', () {
      final fsm = RoutineStateMachine(
        config: const RoutineScheduleConfig(strictLockoutEnforced: true),
        enableAutomaticTicker: false,
      );
      fsm.startRoutine();
      fsm.advancePhaseForTesting(); // in focus session

      final success = fsm.cancelRoutine();
      expect(success, isFalse);
      expect(fsm.snapshot.phase, equals(RoutinePhaseState.focusSession)); // Still locked!
    });
  });

  group('Phase 1: Persistence Journal & Audio Alerts', () {
    test('11. RoutinePersistenceJournal computes and validates cryptographic SHA-256 signatures', () {
      final now = DateTime.now();
      final hash = RoutineJournalRecord.computeHash(
        recordId: 'REC_1001',
        timestamp: now,
        phase: RoutinePhaseState.focusSession,
        cycleIndex: 1,
        focusMinutes: 50,
        breakMinutes: 10,
      );

      expect(hash, isNotEmpty);
      expect(hash.length, equals(64)); // SHA-256 produces 64 hex chars
    });

    test('12. RoutinePersistenceJournal appends records and restores without corruption', () async {
      final journal = RoutinePersistenceJournal();
      final record = await journal.appendRecord(
        phase: RoutinePhaseState.focusSession,
        cycleIndex: 1,
        focusMinutes: 25,
        breakMinutes: 5,
        wasInterventionKill: false,
      );

      expect(record.recordId, startsWith('REC_'));
      final all = await journal.getAllVerifiedRecords();
      expect(all.length, equals(1));
      expect(all.first.focusMinutesRecorded, equals(25));
    });

    test('13. RoutineAudioAlertManager triggers alert events safely', () async {
      const alertManager = RoutineAudioAlertManager(soundEnabled: false, hapticsEnabled: false);
      await alertManager.triggerAlertByName('FOCUS_START');
      await alertManager.triggerAlertByName('BREAK_START');
      await alertManager.triggerAlertByName('BREAK_EXPIRING_WARNING');
      await alertManager.triggerAlertByName('LOCKDOWN_ENGAGED');
    });
  });

  group('Phase 2: Per-App Lockout Architecture & Schedulers', () {
    test('14. InstalledAppsCatalog loads comprehensive default apps covering Social, Video and Gaming', () {
      final map = InstalledAppsCatalog.getInitialPresetsMap();
      expect(map.containsKey('instagram'), isTrue);
      expect(map.containsKey('youtube'), isTrue);
      expect(map.containsKey('reddit'), isTrue);
      expect(map.containsKey('tiktok'), isTrue);
      expect(map.containsKey('twitter_x'), isTrue);
      expect(map.containsKey('pubg_mobile'), isTrue);

      expect(map['instagram']!.riskRating, equals(DopamineRiskRating.extremeDopamineTrap));
      expect(map['instagram']!.allocatedLockMinutes, equals(480)); // 8 hours
      expect(map['youtube']!.allocatedLockMinutes, equals(120));   // 2 hours
    });

    test('15. PerAppScheduler locks individual application and sets remaining seconds', () async {
      final scheduler = PerAppScheduler(enableAutomaticTicker: false);
      await Future.delayed(const Duration(milliseconds: 50));

      await scheduler.lockApp('instagram', customMinutes: 480);
      final insta = scheduler.apps['instagram']!;
      expect(insta.isLocked, isTrue);
      expect(insta.remainingLockSeconds, equals(480 * 60));

      // Other apps remain unlocked
      expect(scheduler.apps['youtube']!.isLocked, isFalse);
    });

    test('16. PerAppScheduler expiration unlocks only expired app while others stay locked', () async {
      final scheduler = PerAppScheduler(enableAutomaticTicker: false);
      await Future.delayed(const Duration(milliseconds: 50));

      // Lock YouTube for 2 hours, Instagram for 8 hours
      await scheduler.lockApp('youtube', customMinutes: 120);
      await scheduler.lockApp('instagram', customMinutes: 480);

      expect(scheduler.apps['youtube']!.isLocked, isTrue);
      expect(scheduler.apps['instagram']!.isLocked, isTrue);

      // Simulate 2 hours passing (121 minutes)
      final twoHoursLater = DateTime.now().add(const Duration(minutes: 121));
      scheduler.tickForTesting(twoHoursLater);

      // YouTube should unlock
      expect(scheduler.apps['youtube']!.isLocked, isFalse);
      expect(scheduler.apps['youtube']!.remainingLockSeconds, equals(0));

      // Instagram must STAY LOCKED for remaining ~6 hours!
      expect(scheduler.apps['instagram']!.isLocked, isTrue);
      expect(scheduler.apps['instagram']!.remainingLockSeconds, inInclusiveRange(350 * 60, 360 * 60));
    });

    test('17. PerAppScheduler lockCategory locks all matching category apps simultaneously', () async {
      final scheduler = PerAppScheduler(enableAutomaticTicker: false);
      await Future.delayed(const Duration(milliseconds: 50));

      await scheduler.lockCategory(AppCategory.gaming, durationMinutes: 180);
      expect(scheduler.apps['pubg_mobile']!.isLocked, isTrue);
      expect(scheduler.apps['roblox']!.isLocked, isTrue);
      expect(scheduler.apps['genshin']!.isLocked, isTrue);
    });
  });

  group('Phase 3: Zero-Battery Native Daemon & Audits', () {
    test('18. BatteryTelemetryService calculates daily consumption strictly < 1.20% per day', () {
      final service = BatteryTelemetryService();
      final report = service.report;

      expect(report.estimatedDailyDrainPercentage, lessThanOrEqualTo(1.20));
      expect(report.activeWakeLocks, equals(0));
      expect(report.statusLabel, contains('Zero-Drain'));
    });
  });

  group('Phase 4: Surgical Feed-vs-Chat Filtering', () {
    test('19. SurgicalPatternCompiler evaluates Instagram Reels vs Direct Messages', () {
      final compiler = SurgicalPatternCompiler();
      final reelsDecision = compiler.evaluateDomain('reels.instagram.com');
      expect(reelsDecision, equals(SurgicalDecision.blackholeFeed));

      final dmsDecision = compiler.evaluateDomain('direct.instagram.com');
      expect(dmsDecision, equals(SurgicalDecision.whitelistChat));
    });

    test('20. SurgicalPatternCompiler evaluates YouTube Shorts vs search queries', () {
      final compiler = SurgicalPatternCompiler();
      final shortsDecision = compiler.evaluateUrlPath('https://www.youtube.com/shorts/dQw4w9WgXcQ');
      expect(shortsDecision, equals(SurgicalDecision.blackholeFeed));

      final searchDecision = compiler.evaluateDomain('suggestqueries.google.com');
      expect(searchDecision, equals(SurgicalDecision.whitelistSearch));
    });

    test('21. SurgicalPatternCompiler evaluates Reddit popular vs direct chat', () {
      final compiler = SurgicalPatternCompiler();
      final popularDecision = compiler.evaluateDomain('v.redd.it');
      expect(popularDecision, equals(SurgicalDecision.blackholeFeed));

      final chatDecision = compiler.evaluateDomain('chat.reddit.com');
      expect(chatDecision, equals(SurgicalDecision.whitelistChat));
    });
  });

  group('Phase 5: Longitudinal Analytics Mathematical Models', () {
    test('22. HabitPsychologyCalculator computes total focus and reclaimed hours accurately', () {
      final mockData = [
        HistoricalFocusDataPoint(
          timestamp: DateTime.now().subtract(const Duration(days: 1)),
          focusMinutes: 240,
          breakMinutes: 30,
          blockedAttempts: 12,
          estimatedReclaimedMinutes: 180,
          adherenceScore: 0.95,
        ),
        HistoricalFocusDataPoint(
          timestamp: DateTime.now().subtract(const Duration(days: 2)),
          focusMinutes: 180,
          breakMinutes: 25,
          blockedAttempts: 8,
          estimatedReclaimedMinutes: 120,
          adherenceScore: 0.92,
        ),
      ];

      final metrics = HabitPsychologyCalculator.calculateWindow(mockData, windowDays: 7);
      expect(metrics.totalFocusHours, equals(7)); // (240 + 180) / 60 = 7
      expect(metrics.totalReclaimedDoomscrollHours, equals(5)); // (180 + 120) / 60 = 5
      expect(metrics.totalInterventions, equals(20));
      expect(metrics.averageAdherencePercentage, inInclusiveRange(90.0, 96.0));
      expect(metrics.currentStreakDays, equals(2));
    });
  });

  group('UI Screens Smoke & Rendering Verification', () {
    testWidgets('23. RoutineFocusStudioScreen renders radial display and recommended protocols', (tester) async {
      await tester.pumpWidget(_wrapScreen(const RoutineFocusStudioScreen()));
      await tester.pump();

      expect(find.text('Focus Routine Studio'), findsOneWidget);
      expect(find.text('RECOMMENDED PROTOCOLS'), findsOneWidget);
      expect(find.text('Classic Pomodoro'), findsOneWidget);
      expect(find.text('Deep Flow (50/10)'), findsOneWidget);
      expect(find.text('ENGAGE ANTI-DOOMSCROLL ROUTINE'), findsOneWidget);
    });

    testWidgets('24. PerAppManagerScreen renders search field and category chips', (tester) async {
      await tester.pumpWidget(_wrapScreen(const PerAppManagerScreen()));
      await tester.pump();

      expect(find.text('App Lockout Manager'), findsOneWidget);
      expect(find.text('Search applications or packages...'), findsOneWidget);
      expect(find.text('All Apps'), findsOneWidget);
      expect(find.text('Social'), findsOneWidget);
    });

    testWidgets('25. BatteryShieldScreen renders <1.20%/day hero card and hardware audit metrics', (tester) async {
      await tester.pumpWidget(_wrapScreen(const BatteryShieldScreen()));
      await tester.pump();

      expect(find.text('Zero-Battery Background Shield'), findsOneWidget);
      expect(find.text('Strict Guarantee: <1.20% per 24 Hours'), findsOneWidget);
      expect(find.text('WAKE-LOCKS'), findsOneWidget);
      expect(find.text('ROUTING SCOPE'), findsOneWidget);
      expect(find.text('DOZE EXEMPTION'), findsOneWidget);
    });
  });
}
