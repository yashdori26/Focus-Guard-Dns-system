import 'dart:async';
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
  });

  bool get isActive => phase == RoutinePhase.focusSession || phase == RoutinePhase.breakSession;
  bool get isFocus => phase == RoutinePhase.focusSession;
  bool get isBreak => phase == RoutinePhase.breakSession;

  String get phaseLabel {
    switch (phase) {
      case RoutinePhase.idle:
        return 'Ready to Focus';
      case RoutinePhase.focusSession:
        return 'Deep Focus Session';
      case RoutinePhase.breakSession:
        return 'Micro-Break (Restricted)';
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
    );
  }
}

class RoutineFocusNotifier extends StateNotifier<RoutineFocusState> {
  Timer? _ticker;
  final bool enableTicker;

  RoutineFocusNotifier({this.enableTicker = true}) : super(const RoutineFocusState()) {
    _initPersistence();
  }

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
  }

  void _persistConfig() {
    AppStorageService.saveRoutineConfig(
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
      }
    }
  }

  void _applyFocusBlocking(bool shouldBlock) {
    try {
      FocusDnsBlockerManager.setStrictMode(shouldBlock);
    } catch (_) {}
  }

  bool cancelRoutine({bool force = false}) {
    if (state.isStrict && !force && state.isActive) {
      return false; // Locked in strict mode!
    }
    _ticker?.cancel();
    _ticker = null;
    _applyFocusBlocking(false);
    state = state.copyWith(
      phase: RoutinePhase.idle,
      remainingSeconds: 0,
      targetEndTime: null,
      isStrict: false,
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
