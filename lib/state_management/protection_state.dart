import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../backend/blocker_service.dart';
import '../repositories/settings_repository.dart';
import '../repositories/http_settings_repository.dart';
import 'deep_focus_state.dart';
import 'vpn_state.dart';
import 'setup_state.dart';

final settingsRepoProvider = Provider<SettingsRepository>((ref) {
  return HttpSettingsRepository();
});

class ProtectionNotifier extends StateNotifier<bool> {
  final SettingsRepository _repo;
  ProtectionNotifier(this._repo) : super(false) {
    _init();
  }

  /// Restores persistent protection state from repository on startup.
  Future<void> _init() async {
    try {
      final isOn = await _repo.isProtectionOn();
      if (!mounted) return;
      state = isOn;
    } catch (_) {}
  }

  Future<void> toggle() async {
    final newState = !state;
    await _repo.setProtectionOn(newState);
    state = newState;
  }

  Future<void> set(bool value) async {
    await _repo.setProtectionOn(value);
    state = value;
  }
}

final protectionProvider =
    StateNotifierProvider<ProtectionNotifier, bool>((ref) {
  return ProtectionNotifier(ref.watch(settingsRepoProvider));
});

class StrictModeState {
  final bool isStrict;
  final int remainingSeconds;
  final DateTime? strictUntil;

  const StrictModeState({
    required this.isStrict,
    this.remainingSeconds = 0,
    this.strictUntil,
  });

  bool get isLocked => isStrict;

  StrictModeState copyWith({
    bool? isStrict,
    int? remainingSeconds,
    DateTime? strictUntil,
  }) {
    return StrictModeState(
      isStrict: isStrict ?? this.isStrict,
      remainingSeconds: remainingSeconds ?? this.remainingSeconds,
      strictUntil: strictUntil ?? this.strictUntil,
    );
  }
}

class StrictModeNotifier extends StateNotifier<StrictModeState> {
  final SettingsRepository _repo;
  final Future<void> Function()? onActivate;
  final Future<void> Function()? onExpire;
  Timer? _countdownTimer;

  StrictModeNotifier(
    this._repo, {
    this.onActivate,
    this.onExpire,
  }) : super(const StrictModeState(isStrict: false)) {
    _init();
  }

  Future<void> _init() async {
    final isStrict = await _repo.isStrictMode();
    final rem = await _repo.getStrictRemainingSeconds();
    if (!mounted) return;
    // Guard against overwriting state if set() was called while _init was resolving
    if (state.isStrict && (!isStrict || rem <= 0)) {
      return;
    }
    if (isStrict && rem <= 0) {
      await _autoExpire();
      return;
    }
    final until = (isStrict && rem > 0) ? DateTime.now().add(Duration(seconds: rem)) : null;
    state = StrictModeState(isStrict: isStrict, remainingSeconds: rem, strictUntil: until);
    await FocusDnsBlockerManager.setStrictMode(isStrict, durationMinutes: (rem > 0) ? (rem / 60).ceil() : null);
    if (!mounted) return;
    if (state.isLocked && state.remainingSeconds > 0) {
      if (onActivate != null) {
        try {
          await onActivate!();
        } catch (_) {}
      }
      _startCountdown();
    }
  }

  void _startCountdown() {
    _countdownTimer?.cancel();
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (state.strictUntil != null) {
        final now = DateTime.now();
        final diff = state.strictUntil!.difference(now).inSeconds;
        if (diff > 0) {
          state = state.copyWith(remainingSeconds: diff);
        } else {
          timer.cancel();
          _countdownTimer = null;
          _autoExpire();
        }
      } else if (state.remainingSeconds > 1) {
        state = state.copyWith(remainingSeconds: state.remainingSeconds - 1);
      } else {
        timer.cancel();
        _countdownTimer = null;
        _autoExpire();
      }
    });
  }

  Future<void> _autoExpire() async {
    state = const StrictModeState(isStrict: false, remainingSeconds: 0, strictUntil: null);
    try {
      await _repo.setStrictMode(false);
      await _repo.setProtectionOn(false);
      await FocusDnsBlockerManager.syncRules(
        isStrictMode: false,
      );
      if (onExpire != null) {
        await onExpire!();
      }
    } catch (_) {}
  }

  Future<bool> set(bool value, {int? durationMinutes, bool force = false}) async {
    // If strict mode is active and time remains, block early deactivation unless forced
    if (!value && !force && state.isStrict && state.remainingSeconds > 0) {
      return false;
    }

    final rem = (value && durationMinutes != null && durationMinutes > 0) ? durationMinutes * 60 : 0;
    final until = (value && rem > 0) ? DateTime.now().add(Duration(seconds: rem)) : null;

    // 1. Immediately update reactive state for instant UI update!
    state = StrictModeState(isStrict: value, remainingSeconds: rem, strictUntil: until);
    if (value && rem > 0) {
      _startCountdown();
    } else {
      _countdownTimer?.cancel();
      _countdownTimer = null;
    }

    try {
      if (value) {
        if (onActivate != null) {
          await onActivate!();
        }
        await _repo.setStrictMode(value, durationMinutes: durationMinutes);
        await FocusDnsBlockerManager.syncRules(
          isStrictMode: value,
          durationMinutes: durationMinutes,
        );
      } else {
        await _repo.setStrictMode(false);
        await _repo.setProtectionOn(false);
        await FocusDnsBlockerManager.syncRules(
          isStrictMode: false,
        );
        if (onExpire != null) {
          await onExpire!();
        }
      }
    } catch (_) {}
    return true;
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    super.dispose();
  }
}

final strictModeProvider =
    StateNotifierProvider<StrictModeNotifier, StrictModeState>((ref) {
  return StrictModeNotifier(
    ref.watch(settingsRepoProvider),
    onActivate: () async {
      await ref.read(protectionProvider.notifier).set(true);
      try {
        ref.read(deepFocusProvider.notifier).syncWithBlocker();
      } catch (_) {}
      try {
        final vpnState = ref.read(vpnProvider);
        if (!vpnState.isRunning) {
          final profileId = ref.read(setupProvider).profileId;
          await ref.read(vpnProvider.notifier).start(profileId: profileId);
        }
      } catch (_) {}
    },
    onExpire: () async {
      await ref.read(protectionProvider.notifier).set(false);
      try {
        final vpnState = ref.read(vpnProvider);
        if (vpnState.isRunning) {
          await ref.read(vpnProvider.notifier).stop();
        }
      } catch (_) {}
    },
  );
});
