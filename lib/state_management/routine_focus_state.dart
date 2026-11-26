import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../backend/blocker_service.dart';
import '../services/app_storage_service.dart';

enum RoutinePhase {
  idle,
  focusSession,
  breakSession,
  completed,
}

class RoutineFocusConfig {
  final int sessionMinutes; // e.g. 50
  final int breakMinutes;   // e.g. 10 (max 30)
  final int totalCycles;    // e.g. 4

  const RoutineFocusConfig({
    this.sessionMinutes = 45,
    this.breakMinutes = 10,
    this.totalCycles = 3,
  });

  RoutineFocusConfig copyWith({
    int? sessionMinutes,
    int? breakMinutes,
    int? totalCycles,
  }) {
    return RoutineFocusConfig(
      sessionMinutes: sessionMinutes ?? this.sessionMinutes,
      breakMinutes: (breakMinutes ?? this.breakMinutes).clamp(1, 30),
      totalCycles: totalCycles ?? this.totalCycles,
    );
  }
}

class RoutineFocusState {
  final RoutinePhase phase;
  final RoutineFocusConfig config;
  final int currentCycle; // 1-indexed (e.g. cycle 1 of 4)
  final int remainingSeconds;
  final DateTime? targetEndTime;
  final int totalFocusSecondsCompleted;
  final int totalBreakSecondsCompleted;
  final bool autoSendHomeOnBreakEnd;
  final bool isStrict;
  final bool isPaused;

  const RoutineFocusState({
    this.phase = RoutinePhase.idle,
    this.config = const RoutineFocusConfig(),
    this.currentCycle = 0,
    this.remainingSeconds = 0,
    this.targetEndTime,
    this.totalFocusSecondsCompleted = 0,
    this.totalBreakSecondsCompleted = 0,
    this.autoSendHomeOnBreakEnd = true,
    this.isStrict = false,
    this.isPaused = false,
  });

  bool get isActive => phase == RoutinePhase.focusSession || phase == RoutinePhase.breakSession;
  bool get isFocus => phase == RoutinePhase.focusSession;
  bool get isBreak => phase == RoutinePhase.breakSession;
  bool get isRunning => isActive && !isPaused;

  String get phaseLabel {
    switch (phase) {
      case RoutinePhase.idle:
        return 'Ready to Focus';
      case RoutinePhase.focusSession:
        return isPaused ? 'Focus Session (Paused)' : 'Deep Focus Session';
      case RoutinePhase.breakSession:
        return isPaused ? 'Micro-Break (Paused)' : 'Micro-Break (Restricted)';
      case RoutinePhase.completed:
        return 'Routine Completed';
    }
  }

  RoutineFocusState copyWith({
    RoutinePhase? phase,
    RoutineFocusConfig? config,
    int? currentCycle,
    int? remainingSeconds,
    DateTime? targetEndTime,
    int? totalFocusSecondsCompleted,
    int? totalBreakSecondsCompleted,
    bool? autoSendHomeOnBreakEnd,
    bool? isStrict,
    bool? isPaused,
  }) {
    return RoutineFocusState(
      phase: phase ?? this.phase,
      config: config ?? this.config,
      currentCycle: currentCycle ?? this.currentCycle,
      remainingSeconds: remainingSeconds ?? this.remainingSeconds,
      targetEndTime: targetEndTime ?? this.targetEndTime,
      totalFocusSecondsCompleted: totalFocusSecondsCompleted ?? this.totalFocusSecondsCompleted,
      totalBreakSecondsCompleted: totalBreakSecondsCompleted ?? this.totalBreakSecondsCompleted,
      autoSendHomeOnBreakEnd: autoSendHomeOnBreakEnd ?? this.autoSendHomeOnBreakEnd,
      isStrict: isStrict ?? this.isStrict,
      isPaused: isPaused ?? this.isPaused,
    );
  }
}

class RoutineFocusNotifier extends StateNotifier<RoutineFocusState> {
  Timer? _ticker;
  final bool enableTicker;

  RoutineFocusNotifier({this.enableTicker = true}) : super(const RoutineFocusState()) {
    _initPersistence();
  }

  @visibleForTesting
  Future<void> initPersistenceForTesting() => _initPersistence();

  Future<void> _initPersistence() async {
    final saved = await AppStorageService.loadRoutineConfig();
    if (!mounted) return;
    if (saved != null) {
      state = state.copyWith(
        config: state.config.copyWith(
          sessionMinutes: saved['sessionMinutes'],
          breakMinutes: saved['breakMinutes'],
          totalCycles: saved['totalCycles'],
        ),
      );
    }

    final activeState = await AppStorageService.loadActiveRoutineState();
    if (!mounted || activeState == null || activeState['isActive'] != true) return;

    final isStrict = activeState['isStrict'] as bool? ?? false;
    final isPaused = activeState['isPaused'] as bool? ?? false;
    final sessionMins = activeState['sessionMinutes'] as int? ?? state.config.sessionMinutes;
    final breakMins = activeState['breakMinutes'] as int? ?? state.config.breakMinutes;
    final totalCycles = activeState['totalCycles'] as int? ?? state.config.totalCycles;
    final savedCycle = activeState['currentCycle'] as int? ?? 1;
    final phaseStr = activeState['phase'] as String? ?? 'focusSession';
    final targetEndTimeMs = activeState['targetEndTime'] as int?;

    // Restore updated config if saved
    state = state.copyWith(
      config: state.config.copyWith(
        sessionMinutes: sessionMins,
        breakMinutes: breakMins,
        totalCycles: totalCycles,
      ),
    );

    if (isPaused) {
      final rem = activeState['remainingSeconds'] as int? ?? 0;
      state = state.copyWith(
        phase: phaseStr == 'breakSession' ? RoutinePhase.breakSession : RoutinePhase.focusSession,
        currentCycle: savedCycle,
        remainingSeconds: rem,
        targetEndTime: null,
        isPaused: true,
        isStrict: isStrict,
      );
      _applyFocusBlocking(false);
      return;
    }

    if (targetEndTimeMs != null) {
      final now = DateTime.now();
      final targetEndTime = DateTime.fromMillisecondsSinceEpoch(targetEndTimeMs);
      final diff = targetEndTime.difference(now).inSeconds;

      if (diff > 0) {
        // Current phase is still actively running!
        final isBreak = phaseStr == 'breakSession';
        state = state.copyWith(
          phase: isBreak ? RoutinePhase.breakSession : RoutinePhase.focusSession,
          currentCycle: savedCycle,
          remainingSeconds: diff,
          targetEndTime: targetEndTime,
          isStrict: isStrict,
          isPaused: false,
        );
        _applyFocusBlocking(!isBreak);
        _armTicker();
      } else {
        // Phase expired while app was in background; calculate how far routine has progressed
        var elapsedAfterTarget = -diff;
        var currentCycle = savedCycle;
        var currentPhase = phaseStr == 'breakSession' ? RoutinePhase.breakSession : RoutinePhase.focusSession;

        bool resolved = false;
        while (!resolved) {
          if (currentPhase == RoutinePhase.focusSession) {
            // Focus session finished while away -> switch to break
            currentPhase = RoutinePhase.breakSession;
            final breakSec = breakMins * 60;
            if (elapsedAfterTarget < breakSec) {
              final rem = breakSec - elapsedAfterTarget;
              state = state.copyWith(
                phase: RoutinePhase.breakSession,
                currentCycle: currentCycle,
                remainingSeconds: rem,
                targetEndTime: now.add(Duration(seconds: rem)),
                isStrict: isStrict,
                isPaused: false,
              );
              _applyFocusBlocking(false);
              _armTicker();
              _persistActiveState();
              resolved = true;
            } else {
              elapsedAfterTarget -= breakSec;
              currentCycle++;
              if (currentCycle > totalCycles) {
                // Completed!
                _applyFocusBlocking(false);
                state = state.copyWith(
                  phase: RoutinePhase.completed,
                  remainingSeconds: 0,
                  targetEndTime: null,
                  isStrict: false,
                  isPaused: false,
                );
                _persistActiveState();
                resolved = true;
              }
            }
          } else {
            // Break finished while away -> switch to next cycle focus session
            currentCycle++;
            if (currentCycle > totalCycles) {
              _applyFocusBlocking(false);
              state = state.copyWith(
                phase: RoutinePhase.completed,
                remainingSeconds: 0,
                targetEndTime: null,
                isStrict: false,
                isPaused: false,
              );
              _persistActiveState();
              resolved = true;
            } else {
              currentPhase = RoutinePhase.focusSession;
              final sessionSec = sessionMins * 60;
              if (elapsedAfterTarget < sessionSec) {
                final rem = sessionSec - elapsedAfterTarget;
                state = state.copyWith(
                  phase: RoutinePhase.focusSession,
                  currentCycle: currentCycle,
                  remainingSeconds: rem,
                  targetEndTime: now.add(Duration(seconds: rem)),
                  isStrict: isStrict,
                  isPaused: false,
                );
                _applyFocusBlocking(true);
                _armTicker();
                _persistActiveState();
                resolved = true;
              } else {
                elapsedAfterTarget -= sessionSec;
              }
            }
          }
        }
      }
    }
  }

  void _persistConfig() {
    AppStorageService.saveRoutineConfig(
      sessionMinutes: state.config.sessionMinutes,
      breakMinutes: state.config.breakMinutes,
      totalCycles: state.config.totalCycles,
    );
  }

  void _persistActiveState() {
    AppStorageService.saveActiveRoutineState(
      isActive: state.isActive,
      phase: state.phase.name,
      currentCycle: state.currentCycle,
      isStrict: state.isStrict,
      isPaused: state.isPaused,
      remainingSeconds: state.remainingSeconds,
      targetEndTime: state.targetEndTime,
      sessionMinutes: state.config.sessionMinutes,
      breakMinutes: state.config.breakMinutes,
      totalCycles: state.config.totalCycles,
    );
  }

  void updateConfig({int? sessionMinutes, int? breakMinutes, int? totalCycles}) {
    if (state.isActive) return; // Cannot alter config while routine is live
    state = state.copyWith(
      config: state.config.copyWith(
        sessionMinutes: sessionMinutes,
        breakMinutes: breakMinutes,
        totalCycles: totalCycles,
      ),
    );
    _persistConfig();
  }

  void startRoutine({bool strict = false}) {
    if (state.isActive) return;
    state = state.copyWith(isStrict: strict);
    _startSession(1);
  }

  void _startSession(int cycle) {
    final seconds = state.config.sessionMinutes * 60;
    state = state.copyWith(
      phase: RoutinePhase.focusSession,
      currentCycle: cycle,
      remainingSeconds: seconds,
      targetEndTime: DateTime.now().add(Duration(seconds: seconds)),
    );
    _applyFocusBlocking(true);
    _armTicker();
    _persistActiveState();
  }

  void _startBreak() {
    final seconds = state.config.breakMinutes * 60;
    state = state.copyWith(
      phase: RoutinePhase.breakSession,
      remainingSeconds: seconds,
      targetEndTime: DateTime.now().add(Duration(seconds: seconds)),
    );
    // Allow apps temporarily during break
    _applyFocusBlocking(false);
    _armTicker();
    _persistActiveState();
  }

  void _armTicker() {
    _ticker?.cancel();
    if (!enableTicker) return;

    _ticker = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (state.targetEndTime == null) {
        timer.cancel();
        return;
      }

      final now = DateTime.now();
      final diff = state.targetEndTime!.difference(now).inSeconds;

      if (diff > 0) {
        state = state.copyWith(
          remainingSeconds: diff,
          totalFocusSecondsCompleted: state.isFocus
              ? state.totalFocusSecondsCompleted + 1
              : state.totalFocusSecondsCompleted,
          totalBreakSecondsCompleted: state.isBreak
              ? state.totalBreakSecondsCompleted + 1
              : state.totalBreakSecondsCompleted,
        );
      } else {
        timer.cancel();
        _ticker = null;
        _onPhaseCompleted();
      }
    });
  }

  void advancePhaseForTesting() => _onPhaseCompleted();

  void _onPhaseCompleted() {
    if (state.isFocus) {
      // Focus session ended -> Switch to break
      _startBreak();
    } else if (state.isBreak) {
      // Break session ended -> Auto-terminate foreground distracting apps & resume block
      if (state.autoSendHomeOnBreakEnd) {
        FocusDnsBlockerManager.closeActiveBlockedApp();
      }
      
      if (state.currentCycle < state.config.totalCycles) {
        // Next cycle
        _startSession(state.currentCycle + 1);
      } else {
        // Complete routine
        _applyFocusBlocking(false);
        state = state.copyWith(
          phase: RoutinePhase.completed,
          remainingSeconds: 0,
          targetEndTime: null,
          isStrict: false,
        );
        _persistActiveState();
      }
    }
  }

  void _applyFocusBlocking(bool shouldBlock) {
    try {
      if (shouldBlock) {
        // Active Focus Session: ALL blocks are fully blocked!
        FocusDnsBlockerManager.setRoutineInBreak(false);
        FocusDnsBlockerManager.setProtectionEnabled(true);
        if (state.isStrict) {
          FocusDnsBlockerManager.setStrictMode(true);
        }
      } else {
        // Break Session: Everything unblocked until break finishes!
        FocusDnsBlockerManager.setRoutineInBreak(true);
        FocusDnsBlockerManager.setProtectionEnabled(false);
      }
    } catch (_) {}
  }

  bool togglePause() {
    if (!state.isActive) return false;
    if (state.isStrict) return false; // Strict mode CANNOT pause!
    return state.isPaused ? resumeRoutine() : pauseRoutine();
  }

  bool pauseRoutine() {
    if (!state.isActive) return false;
    if (state.isStrict) return false; // Strict mode CANNOT pause!
    if (state.isPaused) return true;

    _ticker?.cancel();
    _ticker = null;

    int currentRemaining = state.remainingSeconds;
    if (state.targetEndTime != null) {
      final diff = state.targetEndTime!.difference(DateTime.now()).inSeconds;
      if (diff > 0) currentRemaining = diff;
    }

    state = state.copyWith(
      isPaused: true,
      remainingSeconds: currentRemaining,
      targetEndTime: null,
    );
    // Unblock temporarily during pause in normal mode
    _applyFocusBlocking(false);
    _persistActiveState();
    return true;
  }

  bool resumeRoutine() {
    if (!state.isActive || !state.isPaused) return false;

    final seconds = state.remainingSeconds > 0 ? state.remainingSeconds : 1;
    state = state.copyWith(
      isPaused: false,
      remainingSeconds: seconds,
      targetEndTime: DateTime.now().add(Duration(seconds: seconds)),
    );
    _applyFocusBlocking(state.isFocus);
    _armTicker();
    _persistActiveState();
    return true;
  }

  bool cancelRoutine({bool force = false}) {
    if (state.isStrict && !force && state.isActive) {
      return false; // Locked in strict mode!
    }
    _ticker?.cancel();
    _ticker = null;
    try {
      FocusDnsBlockerManager.setRoutineInBreak(false);
      FocusDnsBlockerManager.setProtectionEnabled(true);
      FocusDnsBlockerManager.setStrictMode(false);
    } catch (_) {}
    AppStorageService.clearActiveRoutineState();
    state = state.copyWith(
      phase: RoutinePhase.idle,
      remainingSeconds: 0,
      targetEndTime: null,
      isStrict: false,
      isPaused: false,
    );
    return true;
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }
}

final routineFocusProvider =
    StateNotifierProvider<RoutineFocusNotifier, RoutineFocusState>((ref) {
  return RoutineFocusNotifier();
});
