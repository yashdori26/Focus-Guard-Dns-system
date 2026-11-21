import 'dart:async';
import 'package:flutter/foundation.dart';
import '../catalog/surgical_subfeature_types.dart';
import '../models/surgical_interception_event.dart';

/// State of the active mindful interstitial nudge overlay.
enum MindfulNudgeState {
  /// No active interstitial pause.
  idle,

  /// Active countdown timer forcing the user to pause.
  countdownActive,

  /// Countdown completed; user presented with reflection question or pledge challenge.
  reflectionActive,

  /// User successfully completed pause and chose to continue (bypass token spent).
  bypassGranted,

  /// User chose to protect their focus, triggering redirection to DMs or back.
  redirectEnforced,
}

/// Active session data for a mindful pause.
@immutable
class MindfulNudgeSession {
  final String sessionId;
  final String platformId;
  final String platformName;
  final SurgicalSubfeature subfeature;
  final int totalDurationSeconds;
  final int remainingSeconds;
  final String motivationalPrompt;
  final String requiredPledgePhrase;
  final MindfulNudgeState state;
  final DateTime startedAt;

  const MindfulNudgeSession({
    required this.sessionId,
    required this.platformId,
    required this.platformName,
    required this.subfeature,
    required this.totalDurationSeconds,
    required this.remainingSeconds,
    required this.motivationalPrompt,
    required this.requiredPledgePhrase,
    required this.state,
    required this.startedAt,
  });

  double get progress => totalDurationSeconds > 0
      ? (totalDurationSeconds - remainingSeconds) / totalDurationSeconds
      : 1.0;

  MindfulNudgeSession copyWith({
    int? remainingSeconds,
    MindfulNudgeState? state,
  }) {
    return MindfulNudgeSession(
      sessionId: sessionId,
      platformId: platformId,
      platformName: platformName,
      subfeature: subfeature,
      totalDurationSeconds: totalDurationSeconds,
      remainingSeconds: remainingSeconds ?? this.remainingSeconds,
      motivationalPrompt: motivationalPrompt,
      requiredPledgePhrase: requiredPledgePhrase,
      state: state ?? this.state,
      startedAt: startedAt,
    );
  }
}

/// Coordinates mindful pause delays, cognitive friction challenges,
/// daily skip token limits, and focus reflection prompts.
class MindfulNudgeCoordinator {
  final int defaultPauseSeconds;
  final bool requirePledgeToBypass;
  final int maxDailyBypassTokens;

  Timer? _countdownTimer;
  MindfulNudgeSession? _currentSession;
  int _dailyBypassTokensUsed = 0;
  DateTime _lastTokenResetDay = DateTime.now();

  final StreamController<MindfulNudgeSession?> _sessionStreamController =
      StreamController<MindfulNudgeSession?>.broadcast();

  final StreamController<int> _secondsRemainingController =
      StreamController<int>.broadcast();

  MindfulNudgeCoordinator({
    this.defaultPauseSeconds = 10,
    this.requirePledgeToBypass = false,
    this.maxDailyBypassTokens = 3,
  });

  /// Broadcast stream of the current active session state.
  Stream<MindfulNudgeSession?> get sessionStream => _sessionStreamController.stream;

  /// Broadcast stream of raw countdown tick seconds.
  Stream<int> get secondsRemainingStream => _secondsRemainingController.stream;

  /// Current session or null if idle.
  MindfulNudgeSession? get currentSession => _currentSession;

  /// Number of daily bypass tokens remaining.
  int get remainingBypassTokens {
    _checkDailyTokenReset();
    return (maxDailyBypassTokens - _dailyBypassTokensUsed).clamp(0, maxDailyBypassTokens);
  }

  /// Initiates a mindful interstitial pause session.
  MindfulNudgeSession startNudge({
    required String platformId,
    required String platformName,
    required SurgicalSubfeature subfeature,
    int? customDurationSeconds,
    String? customPrompt,
  }) {
    _countdownTimer?.cancel();
    _checkDailyTokenReset();

    final duration = customDurationSeconds ?? defaultPauseSeconds;
    final prompt = customPrompt ?? _resolvePromptForSubfeature(platformName, subfeature);
    final pledge = _resolvePledgePhrase(subfeature);

    final session = MindfulNudgeSession(
      sessionId: 'nudge_${DateTime.now().millisecondsSinceEpoch}',
      platformId: platformId,
      platformName: platformName,
      subfeature: subfeature,
      totalDurationSeconds: duration,
      remainingSeconds: duration,
      motivationalPrompt: prompt,
      requiredPledgePhrase: pledge,
      state: MindfulNudgeState.countdownActive,
      startedAt: DateTime.now(),
    );

    _currentSession = session;
    _sessionStreamController.add(_currentSession);
    _secondsRemainingController.add(duration);

    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_currentSession == null) {
        timer.cancel();
        return;
      }

      final remaining = _currentSession!.remainingSeconds - 1;
      if (remaining > 0) {
        _currentSession = _currentSession!.copyWith(remainingSeconds: remaining);
        _sessionStreamController.add(_currentSession);
        _secondsRemainingController.add(remaining);
      } else {
        timer.cancel();
        _currentSession = _currentSession!.copyWith(
          remainingSeconds: 0,
          state: MindfulNudgeState.reflectionActive,
        );
        _sessionStreamController.add(_currentSession);
        _secondsRemainingController.add(0);
      }
    });

    return session;
  }

  /// Cancels the session and enforces return/redirect to protect focus.
  void cancelAndRedirect() {
    _countdownTimer?.cancel();
    if (_currentSession != null) {
      _currentSession = _currentSession!.copyWith(state: MindfulNudgeState.redirectEnforced);
      _sessionStreamController.add(_currentSession);
    }
    _currentSession = null;
    _sessionStreamController.add(null);
  }

  /// Submits a typed pledge to satisfy the cognitive friction challenge.
  bool submitPledge(String text) {
    if (_currentSession == null) return false;
    final normalizedInput = text.trim().toLowerCase();
    final normalizedTarget = _currentSession!.requiredPledgePhrase.trim().toLowerCase();

    if (normalizedInput == normalizedTarget) {
      return grantBypass();
    }
    return false;
  }

  /// Grants a bypass token if the countdown has expired and tokens are available.
  bool grantBypass() {
    _checkDailyTokenReset();
    if (_currentSession == null) return false;
    if (_dailyBypassTokensUsed >= maxDailyBypassTokens) return false;

    _dailyBypassTokensUsed++;
    _countdownTimer?.cancel();
    _currentSession = _currentSession!.copyWith(state: MindfulNudgeState.bypassGranted);
    _sessionStreamController.add(_currentSession);

    // Reset back to idle after short delay
    Future.delayed(const Duration(milliseconds: 300), () {
      _currentSession = null;
      _sessionStreamController.add(null);
    });

    return true;
  }

  /// Resets daily tokens if crossing midnight boundary.
  void _checkDailyTokenReset() {
    final now = DateTime.now();
    if (now.day != _lastTokenResetDay.day ||
        now.month != _lastTokenResetDay.month ||
        now.year != _lastTokenResetDay.year) {
      _dailyBypassTokensUsed = 0;
      _lastTokenResetDay = now;
    }
  }

  String _resolvePromptForSubfeature(String platformName, SurgicalSubfeature subfeature) {
    switch (subfeature) {
      case SurgicalSubfeature.reelsOrShorts:
        return 'You opened $platformName. Vertical video is an infinite variable reward loop. Protect your focus.';
      case SurgicalSubfeature.feed:
        return 'Algorithmic feeds are engineered to steal your afternoon. Return to intentional messaging.';
      case SurgicalSubfeature.explore:
        return 'The discovery grid has no end. Did you come here for a specific person or topic?';
      case SurgicalSubfeature.comments:
        return 'Public comment sections trigger outrage. Is this discussion worth your peace of mind?';
      case SurgicalSubfeature.stories:
        return 'Stories expire in 24 hours. Your focus is finite and permanent.';
      default:
        return 'Take a deep breath. Choose intentional action over impulse.';
    }
  }

  String _resolvePledgePhrase(SurgicalSubfeature subfeature) {
    switch (subfeature) {
      case SurgicalSubfeature.reelsOrShorts:
        return 'I choose deep work over short reels';
      case SurgicalSubfeature.feed:
        return 'I communicate intentionally';
      default:
        return 'I protect my focus';
    }
  }

  /// Disposes active timer and streams.
  void dispose() {
    _countdownTimer?.cancel();
    _sessionStreamController.close();
    _secondsRemainingController.close();
  }
}
