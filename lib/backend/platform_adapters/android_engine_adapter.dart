import 'dart:async';
import 'package:flutter/services.dart';

/// Dart platform adapter bridging Flutter services to `:android-engine`.
/// Conforms strictly to `android-engine/UI_HOOKS_NEEDED.md` with zero UI dependencies.
class AndroidEngineAdapter {
  static const MethodChannel _methodChannel =
      MethodChannel('com.focusdns.engine/methods');
  static const EventChannel _eventChannel =
      EventChannel('com.focusdns.engine/events');

  static final AndroidEngineAdapter instance = AndroidEngineAdapter._();
  AndroidEngineAdapter._();

  Stream<dynamic>? _eventStream;

  /// Stream of engine events: onPhaseTransition, onVpnConflictDegraded, onTamperDetected, etc.
  Stream<dynamic> get events {
    _eventStream ??= _eventChannel.receiveBroadcastStream();
    return _eventStream!;
  }

  /// Starts a local-first focus session on Android with absolute timelines.
  Future<bool> startSession({
    required String sessionId,
    required String mode, // 'NORMAL', 'STRICT', 'CYCLES', 'FEED_ONLY'
    int focusMinutes = 25,
    int breakMinutes = 5,
    int cycles = 4,
    bool strictLockout = false,
    List<String> blockedFeatures = const [],
  }) async {
    try {
      final result = await _methodChannel.invokeMethod<bool>('startSession', {
        'sessionId': sessionId,
        'mode': mode,
        'focusMinutes': focusMinutes,
        'breakMinutes': breakMinutes,
        'cycles': cycles,
        'strictLockout': strictLockout,
        'blockedFeatures': blockedFeatures,
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
  Future<bool> pauseSession({required String sessionId}) async {
    try {
      final result = await _methodChannel.invokeMethod<bool>('pauseSession', {
        'sessionId': sessionId,
      });
      return result ?? false;
    } on PlatformException catch (e) {
      if (e.code == 'ERR_PAUSE_NOT_ALLOWED') {
        // Enforce Option B Ironclad Lockout
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

  /// Retrieves the current snapshot state from `:android-engine`.
  Future<Map<String, dynamic>> getEngineStatus() async {
    try {
      final result = await _methodChannel
          .invokeMapMethod<String, dynamic>('getEngineStatus');
      return result ?? {};
    } catch (_) {
      return {};
    }
  }

  /// Ingests and applies an Ed25519-signed rule pack delta.
  Future<bool> applyRulePack({
    required String rawJson,
    required String ed25519SignatureHex,
  }) async {
    final result = await _methodChannel.invokeMethod<bool>('applyRulePack', {
      'rawJson': rawJson,
      'ed25519SignatureHex': ed25519SignatureHex,
    });
    return result ?? false;
  }

  /// Launches system intent to request Device Administrator for anti-uninstall protection.
  Future<bool> requestDeviceAdmin() async {
    final result =
        await _methodChannel.invokeMethod<bool>('requestDeviceAdmin');
    return result ?? false;
  }
}
