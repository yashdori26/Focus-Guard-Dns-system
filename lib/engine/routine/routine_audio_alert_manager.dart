import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';

/// Audio alert types dispatched by the Routine Engine.
enum RoutineAlertType {
  prepStart,
  focusStart,
  breakStart,
  breakExpiringWarning,
  lockdownEngaged,
  routineCompleted,
}

/// Orchestrates non-intrusive sound cues and haptic vibration feedback for focus transitions.
class RoutineAudioAlertManager {
  final bool soundEnabled;
  final bool hapticsEnabled;

  const RoutineAudioAlertManager({
    this.soundEnabled = true,
    this.hapticsEnabled = true,
  });

  /// Dispatches the appropriate audio-haptic pattern for the given event name.
  Future<void> triggerAlertByName(String alertName) async {
    switch (alertName.toUpperCase()) {
      case 'PREP_START':
        await triggerAlert(RoutineAlertType.prepStart);
        break;
      case 'FOCUS_START':
        await triggerAlert(RoutineAlertType.focusStart);
        break;
      case 'BREAK_START':
        await triggerAlert(RoutineAlertType.breakStart);
        break;
      case 'BREAK_EXPIRING_WARNING':
        await triggerAlert(RoutineAlertType.breakExpiringWarning);
        break;
      case 'LOCKDOWN_ENGAGED':
        await triggerAlert(RoutineAlertType.lockdownEngaged);
        break;
      case 'ROUTINE_COMPLETED':
        await triggerAlert(RoutineAlertType.routineCompleted);
        break;
      default:
        debugPrint('[AudioAlertManager] Unknown alert trigger: $alertName');
    }
  }

  /// Dispatches precise sound and vibration combinations.
  Future<void> triggerAlert(RoutineAlertType type) async {
    try {
      switch (type) {
        case RoutineAlertType.prepStart:
          if (hapticsEnabled) await HapticFeedback.selectionClick();
          break;

        case RoutineAlertType.focusStart:
          if (soundEnabled) await SystemSound.play(SystemSoundType.click);
          if (hapticsEnabled) {
            await HapticFeedback.mediumImpact();
            await Future.delayed(const Duration(milliseconds: 100));
            await HapticFeedback.heavyImpact();
          }
          break;

        case RoutineAlertType.breakStart:
          if (soundEnabled) await SystemSound.play(SystemSoundType.click);
          if (hapticsEnabled) {
            await HapticFeedback.lightImpact();
            await Future.delayed(const Duration(milliseconds: 150));
            await HapticFeedback.lightImpact();
          }
          break;

        case RoutineAlertType.breakExpiringWarning:
          // Distinct 3-pulse urgent haptic pattern for the 30-second warning
          if (soundEnabled) await SystemSound.play(SystemSoundType.alert);
          if (hapticsEnabled) {
            for (int i = 0; i < 3; i++) {
              await HapticFeedback.heavyImpact();
              await Future.delayed(const Duration(milliseconds: 180));
            }
          }
          break;

        case RoutineAlertType.lockdownEngaged:
          // Heavy single alert upon app close & network blackout re-engagement
          if (soundEnabled) await SystemSound.play(SystemSoundType.alert);
          if (hapticsEnabled) await HapticFeedback.vibrate();
          break;

        case RoutineAlertType.routineCompleted:
          if (soundEnabled) await SystemSound.play(SystemSoundType.click);
          if (hapticsEnabled) {
            await HapticFeedback.mediumImpact();
            await Future.delayed(const Duration(milliseconds: 120));
            await HapticFeedback.heavyImpact();
            await Future.delayed(const Duration(milliseconds: 120));
            await HapticFeedback.mediumImpact();
          }
          break;
      }
    } catch (e) {
      debugPrint('[AudioAlertManager] Haptic/Sound error: $e');
    }
  }
}
