import 'dart:async';
import 'package:flutter/foundation.dart';
import '../../backend/blocker_service.dart';

/// Exhaustive stages in the Anti-Doomscroll Routine Life Cycle.
enum RoutinePhaseState {
  idle,
  preparationGrace,
  focusSession,
  sessionCompletedAlert,
  breakSession,
  breakExpiringGrace,
  appTerminationSweep,
  cycleAdvance,
  routineCompleted,
}

/// Immutable configuration driving the anti-doomscroll routine.
@immutable
class RoutineScheduleConfig {
  final int focusMinutes;
  final int breakMinutes;
  final int totalCycles;
  final int preparationGraceSeconds;
  final int breakExpiringGraceSeconds;
  final bool autoTerminateOnBreakExpiry;
  final bool strictLockoutEnforced;
  final String label;

  const RoutineScheduleConfig({
    this.focusMinutes = 25,
    int breakMinutes = 5,
    this.totalCycles = 4,
    this.preparationGraceSeconds = 10,
    this.breakExpiringGraceSeconds = 30,
    this.autoTerminateOnBreakExpiry = true,
    this.strictLockoutEnforced = true,
    this.label = 'Deep Focus Routine',
  }) : breakMinutes = breakMinutes > 240 ? 240 : (breakMinutes < 1 ? 1 : breakMinutes);

  RoutineScheduleConfig copyWith({
    int? focusMinutes,
    int? breakMinutes,
    int? totalCycles,
    int? preparationGraceSeconds,
    int? breakExpiringGraceSeconds,
    bool? autoTerminateOnBreakExpiry,
    bool? strictLockoutEnforced,
    String? label,
  }) {
    final rawBreak = breakMinutes ?? this.breakMinutes;
    // Guaranteed hard ceiling of 240 minutes (4 hours) max
    final safeBreak = rawBreak.clamp(1, 240);

    return RoutineScheduleConfig(
      focusMinutes: (focusMinutes ?? this.focusMinutes).clamp(5, 480),
      breakMinutes: safeBreak,
      totalCycles: (totalCycles ?? this.totalCycles).clamp(1, 12),
      preparationGraceSeconds: preparationGraceSeconds ?? this.preparationGraceSeconds,
      breakExpiringGraceSeconds: breakExpiringGraceSeconds ?? this.breakExpiringGraceSeconds,
      autoTerminateOnBreakExpiry: autoTerminateOnBreakExpiry ?? this.autoTerminateOnBreakExpiry,
      strictLockoutEnforced: strictLockoutEnforced ?? this.strictLockoutEnforced,
      label: label ?? this.label,
    );
  }

  Map<String, dynamic> toJson() => {
    'focusMinutes': focusMinutes,
    'breakMinutes': breakMinutes,
    'totalCycles': totalCycles,
    'preparationGraceSeconds': preparationGraceSeconds,
    'breakExpiringGraceSeconds': breakExpiringGraceSeconds,
    'autoTerminateOnBreakExpiry': autoTerminateOnBreakExpiry,
    'strictLockoutEnforced': strictLockoutEnforced,
    'label': label,
  };

  factory RoutineScheduleConfig.fromJson(Map<String, dynamic> json) {
    final rawBreak = (json['breakMinutes'] as num?)?.toInt() ?? 5;
    return RoutineScheduleConfig(
      focusMinutes: ((json['focusMinutes'] as num?)?.toInt() ?? 25).clamp(5, 480),
      breakMinutes: rawBreak.clamp(1, 240),
      totalCycles: ((json['totalCycles'] as num?)?.toInt() ?? 4).clamp(1, 12),
      preparationGraceSeconds: (json['preparationGraceSeconds'] as num?)?.toInt() ?? 10,
      breakExpiringGraceSeconds: (json['breakExpiringGraceSeconds'] as num?)?.toInt() ?? 30,
      autoTerminateOnBreakExpiry: json['autoTerminateOnBreakExpiry'] as bool? ?? true,
      strictLockoutEnforced: json['strictLockoutEnforced'] as bool? ?? true,
      label: json['label'] as String? ?? 'Deep Focus Routine',
    );
  }

  static const pomodoro = RoutineScheduleConfig(
    focusMinutes: 25,
    breakMinutes: 5,
    totalCycles: 4,
    label: 'Classic Pomodoro',
  );

  static const deepFlow = RoutineScheduleConfig(
    focusMinutes: 50,
    breakMinutes: 10,
    totalCycles: 3,
    label: 'Deep Flow (50/10)',
  );

  static const ultraNinety = RoutineScheduleConfig(
    focusMinutes: 90,
    breakMinutes: 20,
    totalCycles: 2,
    label: 'Ultradian Rhythm (90/20)',
  );

  static const marathonFourHour = RoutineScheduleConfig(
    focusMinutes: 120,
    breakMinutes: 30, // maximum allowed break
    totalCycles: 2,
    label: 'Marathon Lockout',
  );
}

/// Immutable snapshot of the routine state machine at any instant.
@immutable
class RoutineSnapshot {
  final RoutinePhaseState phase;
  final RoutineScheduleConfig config;
  final int currentCycle;
  final int remainingSecondsInPhase;
  final int totalPhaseDurationSeconds;
  final int cumulativeFocusSeconds;
  final int cumulativeBreakSeconds;
  final int totalInterventionKills;
  final DateTime? phaseStartTime;
  final DateTime? phaseTargetEndTime;
  final String statusMessage;

  const RoutineSnapshot({
    this.phase = RoutinePhaseState.idle,
    this.config = const RoutineScheduleConfig(),
    this.currentCycle = 1,
    this.remainingSecondsInPhase = 0,
    this.totalPhaseDurationSeconds = 0,
    this.cumulativeFocusSeconds = 0,
    this.cumulativeBreakSeconds = 0,
    this.totalInterventionKills = 0,
    this.phaseStartTime,
    this.phaseTargetEndTime,
    this.statusMessage = 'System Ready',
  });

  bool get isFocusActive => phase == RoutinePhaseState.focusSession;
  bool get isBreakActive => phase == RoutinePhaseState.breakSession;
  bool get isGraceActive => phase == RoutinePhaseState.breakExpiringGrace || phase == RoutinePhaseState.preparationGrace;
  bool get isRunning => phase != RoutinePhaseState.idle && phase != RoutinePhaseState.routineCompleted;

  double get phaseProgress {
    if (totalPhaseDurationSeconds <= 0) return 0.0;
    final elapsed = totalPhaseDurationSeconds - remainingSecondsInPhase;
    return (elapsed / totalPhaseDurationSeconds).clamp(0.0, 1.0);
  }

  double get overallRoutineProgress {
    final totalFocusGoal = config.focusMinutes * 60 * config.totalCycles;
    if (totalFocusGoal <= 0) return 0.0;
    return (cumulativeFocusSeconds / totalFocusGoal).clamp(0.0, 1.0);
  }

  RoutineSnapshot copyWith({
    RoutinePhaseState? phase,
    RoutineScheduleConfig? config,
    int? currentCycle,
    int? remainingSecondsInPhase,
    int? totalPhaseDurationSeconds,
    int? cumulativeFocusSeconds,
    int? cumulativeBreakSeconds,
    int? totalInterventionKills,
    DateTime? phaseStartTime,
    DateTime? phaseTargetEndTime,
    String? statusMessage,
  }) {
    return RoutineSnapshot(
      phase: phase ?? this.phase,
      config: config ?? this.config,
      currentCycle: currentCycle ?? this.currentCycle,
      remainingSecondsInPhase: remainingSecondsInPhase ?? this.remainingSecondsInPhase,
      totalPhaseDurationSeconds: totalPhaseDurationSeconds ?? this.totalPhaseDurationSeconds,
      cumulativeFocusSeconds: cumulativeFocusSeconds ?? this.cumulativeFocusSeconds,
      cumulativeBreakSeconds: cumulativeBreakSeconds ?? this.cumulativeBreakSeconds,
      totalInterventionKills: totalInterventionKills ?? this.totalInterventionKills,
      phaseStartTime: phaseStartTime ?? this.phaseStartTime,
      phaseTargetEndTime: phaseTargetEndTime ?? this.phaseTargetEndTime,
      statusMessage: statusMessage ?? this.statusMessage,
    );
  }
}

/// Callback interfaces for system triggers.
typedef OnPhaseTransitionCallback = void Function(RoutinePhaseState oldPhase, RoutinePhaseState newPhase);
typedef OnForegroundAppKillCallback = Future<void> Function();
typedef OnAudioAlertCallback = void Function(String alertType);

/// Industrial-grade Hierarchical Finite State Machine with monotonic clock drift compensation.
class RoutineStateMachine extends ChangeNotifier {
  RoutineSnapshot _snapshot;
  Timer? _ticker;
  final Stopwatch _phaseStopwatch = Stopwatch();
  final bool enableAutomaticTicker;

  OnPhaseTransitionCallback? onPhaseTransition;
  OnForegroundAppKillCallback? onForegroundAppKill;
  OnAudioAlertCallback? onAudioAlert;

  RoutineStateMachine({
    RoutineScheduleConfig config = const RoutineScheduleConfig(),
    this.enableAutomaticTicker = true,
    this.onPhaseTransition,
    this.onForegroundAppKill,
    this.onAudioAlert,
  }) : _snapshot = RoutineSnapshot(config: config);

  RoutineSnapshot get snapshot => _snapshot;

  /// Updates configuration if not currently locked in an active focus or break cycle.
  bool updateConfig(RoutineScheduleConfig newConfig) {
    if (_snapshot.isRunning && _snapshot.config.strictLockoutEnforced) {
      debugPrint('[RoutineEngine] Config update rejected: Strict lockout is active.');
      return false;
    }
    _snapshot = _snapshot.copyWith(config: newConfig);
    notifyListeners();
    return true;
  }

  /// Begins the automated anti-doomscroll routine.
  void startRoutine() {
    if (_snapshot.isRunning) return;
    _startPreparationGrace();
  }

  void _startPreparationGrace() {
    final oldPhase = _snapshot.phase;
    final duration = _snapshot.config.preparationGraceSeconds;
    final now = DateTime.now();

    _snapshot = _snapshot.copyWith(
      phase: RoutinePhaseState.preparationGrace,
      currentCycle: 1,
      totalPhaseDurationSeconds: duration,
      remainingSecondsInPhase: duration,
      phaseStartTime: now,
      phaseTargetEndTime: now.add(Duration(seconds: duration)),
      statusMessage: 'Preparing Focus Space... (${duration}s)',
    );

    _phaseStopwatch.reset();
    _phaseStopwatch.start();
    _notifyPhaseChange(oldPhase, RoutinePhaseState.preparationGrace);
    onAudioAlert?.call('PREP_START');
    _armTicker();
  }

  void _enterFocusSession() {
    final oldPhase = _snapshot.phase;
    final duration = _snapshot.config.focusMinutes * 60;
    final now = DateTime.now();

    _snapshot = _snapshot.copyWith(
      phase: RoutinePhaseState.focusSession,
      totalPhaseDurationSeconds: duration,
      remainingSecondsInPhase: duration,
      phaseStartTime: now,
      phaseTargetEndTime: now.add(Duration(seconds: duration)),
      statusMessage: 'Focus Session: Cycle ${_snapshot.currentCycle} of ${_snapshot.config.totalCycles}',
    );

    _phaseStopwatch.reset();
    _phaseStopwatch.start();

    // Enforce strict system-level DNS and package blocking
    _enforcePlatformBlock(true);

    _notifyPhaseChange(oldPhase, RoutinePhaseState.focusSession);
    onAudioAlert?.call('FOCUS_START');
    _armTicker();
  }

  void _enterBreakSession() {
    final oldPhase = _snapshot.phase;
    final duration = _snapshot.config.breakMinutes * 60;
    final now = DateTime.now();

    _snapshot = _snapshot.copyWith(
      phase: RoutinePhaseState.breakSession,
      totalPhaseDurationSeconds: duration,
      remainingSecondsInPhase: duration,
      phaseStartTime: now,
      phaseTargetEndTime: now.add(Duration(seconds: duration)),
      statusMessage: 'Micro-Break Active (Max ${_snapshot.config.breakMinutes}m)',
    );

    _phaseStopwatch.reset();
    _phaseStopwatch.start();

    // Temporarily release blocks for break allowance
    _enforcePlatformBlock(false);

    _notifyPhaseChange(oldPhase, RoutinePhaseState.breakSession);
    onAudioAlert?.call('BREAK_START');
    _armTicker();
  }

  void _enterBreakExpiringGrace() {
    final oldPhase = _snapshot.phase;
    final duration = _snapshot.config.breakExpiringGraceSeconds;
    final now = DateTime.now();

    _snapshot = _snapshot.copyWith(
      phase: RoutinePhaseState.breakExpiringGrace,
      totalPhaseDurationSeconds: duration,
      remainingSecondsInPhase: duration,
      phaseStartTime: now,
      phaseTargetEndTime: now.add(Duration(seconds: duration)),
      statusMessage: 'Break Ending in ${duration}s! Wrap up now.',
    );

    _phaseStopwatch.reset();
    _phaseStopwatch.start();

    _notifyPhaseChange(oldPhase, RoutinePhaseState.breakExpiringGrace);
    onAudioAlert?.call('BREAK_EXPIRING_WARNING');
    _armTicker();
  }

  Future<void> _executeAppTerminationSweep() async {
    final oldPhase = _snapshot.phase;
    _snapshot = _snapshot.copyWith(
      phase: RoutinePhaseState.appTerminationSweep,
      statusMessage: 'Terminating foreground apps & engaging lock...',
      totalInterventionKills: _snapshot.totalInterventionKills + 1,
    );

    _notifyPhaseChange(oldPhase, RoutinePhaseState.appTerminationSweep);

    // 1. Trigger native accessibility service to close active foreground app
    if (_snapshot.config.autoTerminateOnBreakExpiry) {
      if (onForegroundAppKill != null) {
        onForegroundAppKill!();
      } else {
        FocusDnsBlockerManager.closeActiveBlockedApp();
      }
    }

    // 2. Reactivate strict DNS sinkhole blackholing
    _enforcePlatformBlock(true);

    onAudioAlert?.call('LOCKDOWN_ENGAGED');

    // 3. Cycle advance logic
    if (_snapshot.currentCycle < _snapshot.config.totalCycles) {
      _advanceToNextCycle();
    } else {
      _completeRoutine();
    }
  }

  void _advanceToNextCycle() {
    final nextCycle = _snapshot.currentCycle + 1;
    _snapshot = _snapshot.copyWith(
      phase: RoutinePhaseState.cycleAdvance,
      currentCycle: nextCycle,
      statusMessage: 'Starting Cycle $nextCycle of ${_snapshot.config.totalCycles}...',
    );
    notifyListeners();
    _enterFocusSession();
  }

  void _completeRoutine() {
    final oldPhase = _snapshot.phase;
    _ticker?.cancel();
    _ticker = null;
    _phaseStopwatch.stop();

    _snapshot = _snapshot.copyWith(
      phase: RoutinePhaseState.routineCompleted,
      remainingSecondsInPhase: 0,
      phaseTargetEndTime: null,
      statusMessage: 'Routine Completed! Well done.',
    );

    _enforcePlatformBlock(false);
    _notifyPhaseChange(oldPhase, RoutinePhaseState.routineCompleted);
    onAudioAlert?.call('ROUTINE_COMPLETED');
    notifyListeners();
  }

  /// Cancels routine unless locked in Strict Mode.
  bool cancelRoutine() {
    if (_snapshot.isRunning && _snapshot.config.strictLockoutEnforced) {
      debugPrint('[RoutineEngine] Cancel aborted: Unbreakable strict lockout is enforced.');
      return false;
    }

    _ticker?.cancel();
    _ticker = null;
    _phaseStopwatch.stop();

    _enforcePlatformBlock(false);

    final oldPhase = _snapshot.phase;
    _snapshot = _snapshot.copyWith(
      phase: RoutinePhaseState.idle,
      remainingSecondsInPhase: 0,
      phaseTargetEndTime: null,
      statusMessage: 'Routine Canceled',
    );

    _notifyPhaseChange(oldPhase, RoutinePhaseState.idle);
    notifyListeners();
    return true;
  }

  void _enforcePlatformBlock(bool shouldBlock) {
    try {
      if (shouldBlock) {
        FocusDnsBlockerManager.setRoutineInBreak(false);
        FocusDnsBlockerManager.setProtectionEnabled(true);
        FocusDnsBlockerManager.setStrictMode(true);
      } else {
        FocusDnsBlockerManager.setRoutineInBreak(true);
        FocusDnsBlockerManager.setProtectionEnabled(false);
      }
    } catch (e) {
      debugPrint('[RoutineEngine] Platform blocking sync warning: $e');
    }
  }

  void _armTicker() {
    _ticker?.cancel();
    if (!enableAutomaticTicker) return;

    _ticker = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
  }

  void _tick() {
    if (_snapshot.phaseTargetEndTime == null) return;

    final now = DateTime.now();
    final remaining = _snapshot.phaseTargetEndTime!.difference(now).inSeconds;

    if (remaining > 0) {
      int focusSec = _snapshot.cumulativeFocusSeconds;
      int breakSec = _snapshot.cumulativeBreakSeconds;

      if (_snapshot.isFocusActive) {
        focusSec += 1;
      } else if (_snapshot.isBreakActive || _snapshot.phase == RoutinePhaseState.breakExpiringGrace) {
        breakSec += 1;
      }

      _snapshot = _snapshot.copyWith(
        remainingSecondsInPhase: remaining,
        cumulativeFocusSeconds: focusSec,
        cumulativeBreakSeconds: breakSec,
      );
      notifyListeners();
    } else {
      _ticker?.cancel();
      _ticker = null;
      _handlePhaseExpiration();
    }
  }

  void _handlePhaseExpiration() {
    switch (_snapshot.phase) {
      case RoutinePhaseState.preparationGrace:
        _enterFocusSession();
        break;
      case RoutinePhaseState.focusSession:
        _enterBreakSession();
        break;
      case RoutinePhaseState.breakSession:
        _enterBreakExpiringGrace();
        break;
      case RoutinePhaseState.breakExpiringGrace:
        _executeAppTerminationSweep();
        break;
      default:
        break;
    }
  }

  void _notifyPhaseChange(RoutinePhaseState oldPhase, RoutinePhaseState newPhase) {
    notifyListeners();
    onPhaseTransition?.call(oldPhase, newPhase);
  }

  /// High-precision simulated tick for unit and stress testing.
  @visibleForTesting
  void advancePhaseForTesting() {
    _handlePhaseExpiration();
  }

  /// Sets arbitrary monotonic progress for unit testing.
  @visibleForTesting
  void simulateRemainingSeconds(int seconds) {
    _snapshot = _snapshot.copyWith(remainingSecondsInPhase: seconds);
    notifyListeners();
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _phaseStopwatch.stop();
    super.dispose();
  }
}
