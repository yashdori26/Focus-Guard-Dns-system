import 'dart:async';
import 'package:flutter/services.dart';

/// Dart platform adapter bridging Flutter services to `ios-engine`.
/// Conforms strictly to `ios-engine/UI_HOOKS_NEEDED.md` with zero UI dependencies.
class IosEngineAdapter {
  static const MethodChannel _methodChannel =
      MethodChannel('com.focusdns.app/screen_time');

  static final IosEngineAdapter instance = IosEngineAdapter._();
  IosEngineAdapter._();

  /// Prompts user for Apple `FamilyControls` individual authorization.
  Future<bool> requestAuthorization() async {
    try {
      final result =
          await _methodChannel.invokeMethod<bool>('requestAuthorization');
      return result ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Checks if Apple `FamilyControls` status is currently approved.
  Future<bool> isAuthorized() async {
    try {
      final result = await _methodChannel.invokeMethod<bool>('isAuthorized');
      return result ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Starts an iOS focus session. Precomputes absolute timeline and configures ManagedSettings.
  Future<bool> startSession({
    required String sessionId,
    required String mode,
    int focusMinutes = 25,
    int breakMinutes = 5,
    int cycles = 4,
    bool strictLockout = false,
  }) async {
    try {
      final result = await _methodChannel.invokeMethod<bool>('startSession', {
        'sessionId': sessionId,
        'mode': mode,
        'focusMinutes': focusMinutes,
        'breakMinutes': breakMinutes,
        'cycles': cycles,
        'strictLockout': strictLockout,
      });
      return result ?? false;
    } on PlatformException catch (e) {
      if (e.code == 'ERR_STRICT_LOCKOUT_ACTIVE') {
        rethrow;
      }
      return false;
    }
  }

  /// Pauses an active non-strict session. Rejects if in strict lockout (Option B).
  Future<bool> pauseSession({
    required String sessionId,
    int pauseMinutes = 15,
  }) async {
    try {
      final result = await _methodChannel.invokeMethod<bool>('pauseSession', {
        'sessionId': sessionId,
        'pauseMinutes': pauseMinutes,
      });
      return result ?? false;
    } on PlatformException catch (e) {
      if (e.code == 'ERR_PAUSE_NOT_ALLOWED') {
        return false;
      }
      rethrow;
    }
  }

  /// Resumes a paused session.
  Future<bool> resumeSession({required String sessionId}) async {
    final result = await _methodChannel.invokeMethod<bool>('resumeSession', {
      'sessionId': sessionId,
    });
    return result ?? false;
  }

  /// Stops an active session. Strictly rejected during active strict lockout.
  Future<bool> stopSession({required String sessionId}) async {
    try {
      final result = await _methodChannel.invokeMethod<bool>('stopSession', {
        'sessionId': sessionId,
      });
      return result ?? false;
    } on PlatformException catch (e) {
      if (e.code == 'ERR_STRICT_LOCKOUT_ACTIVE') {
        return false;
      }
      rethrow;
    }
  }

  /// Applies OS-level ManagedSettings shields until absolute `endsAt` timestamp.
  Future<bool> applyShields({
    required int endsAtMillis,
    required bool isStrict,
  }) async {
    try {
      final result = await _methodChannel.invokeMethod<bool>('applyShields', {
        'endsAt': endsAtMillis,
        'isStrict': isStrict,
      });
      return result ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Clears active application shields.
  Future<bool> clearShields() async {
    try {
      final result = await _methodChannel.invokeMethod<bool>('clearShields');
      return result ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Queries the active engine status from App Group container.
  Future<Map<String, dynamic>> getEngineStatus() async {
    try {
      final result =
          await _methodChannel.invokeMapMethod<String, dynamic>('checkStatus');
      return result ?? {};
    } catch (_) {
      return {};
    }
  }

  /// Generates the raw Apple `.mobileconfig` XML with removal passcode protection.
  Future<String?> generateMobileConfig({String? removalPasscode = '2026'}) async {
    try {
      final result = await _methodChannel.invokeMethod<String>(
        'generateMobileConfig',
        {'removalPasscode': removalPasscode},
      );
      return result;
    } catch (_) {
      return null;
    }
  }
}
