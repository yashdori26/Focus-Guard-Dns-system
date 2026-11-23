import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';

/// Parsed pairing payload unpacked from a QR code or pairing URL.
@immutable
class PairingPayload {
  final String userId;
  final String deviceName;
  final int timestampSeconds;
  final String signature;
  final bool isValid;
  final String? validationError;

  const PairingPayload({
    required this.userId,
    required this.deviceName,
    required this.timestampSeconds,
    required this.signature,
    required this.isValid,
    this.validationError,
  });

  @override
  String toString() => 'PairingPayload(user: $userId, dev: $deviceName, valid: $isValid)';
}

/// Cryptographic engine generating and verifying HMAC-SHA256 signatures for QR pairing,
/// cross-device authentication tokens, and replay attack prevention.
class DevicePairingCrypto {
  static const String scheme = 'focusdns';
  static const String host = 'pair';
  static const int replayWindowSeconds = 300; // 5 minutes

  final String _sharedSecret;

  const DevicePairingCrypto([this._sharedSecret = 'focus_dns_master_secret_2026']);

  /// Generates a tamper-proof pairing URI suitable for QR code rendering.
  /// Format: focusdns://pair?uid=...&dev=...&ts=...&sig=...
  String generatePairingUri({
    required String userId,
    required String deviceName,
    int? timestampSeconds,
  }) {
    final ts = timestampSeconds ?? (DateTime.now().millisecondsSinceEpoch ~/ 1000);
    final signature = _computeHmacSignature('$userId:$deviceName:$ts');

    final uri = Uri(
      scheme: scheme,
      host: host,
      queryParameters: {
        'uid': userId,
        'dev': deviceName,
        'ts': ts.toString(),
        'sig': signature,
      },
    );

    return uri.toString();
  }

  /// Parses and cryptographically validates an incoming pairing URI string.
  PairingPayload parseAndValidatePairingUri(String uriString, [int? currentTimestampSeconds]) {
    try {
      final uri = Uri.parse(uriString);
      if (uri.scheme != scheme || uri.host != host) {
        return const PairingPayload(
          userId: '',
          deviceName: '',
          timestampSeconds: 0,
          signature: '',
          isValid: false,
          validationError: 'Invalid URI scheme or host.',
        );
      }

      final uid = uri.queryParameters['uid'];
      final dev = uri.queryParameters['dev'];
      final tsStr = uri.queryParameters['ts'];
      final sig = uri.queryParameters['sig'];

      if (uid == null || dev == null || tsStr == null || sig == null) {
        return const PairingPayload(
          userId: '',
          deviceName: '',
          timestampSeconds: 0,
          signature: '',
          isValid: false,
          validationError: 'Missing required query parameters.',
        );
      }

      final ts = int.tryParse(tsStr);
      if (ts == null) {
        return const PairingPayload(
          userId: '',
          deviceName: '',
          timestampSeconds: 0,
          signature: '',
          isValid: false,
          validationError: 'Invalid timestamp format.',
        );
      }

      // Replay window verification (5 minutes)
      final nowSec = currentTimestampSeconds ?? (DateTime.now().millisecondsSinceEpoch ~/ 1000);
      if ((nowSec - ts).abs() > replayWindowSeconds) {
        return PairingPayload(
          userId: uid,
          deviceName: dev,
          timestampSeconds: ts,
          signature: sig,
          isValid: false,
          validationError: 'Pairing QR code expired. Please generate a fresh code.',
        );
      }

      // HMAC Signature validation
      final expectedSignature = _computeHmacSignature('$uid:$dev:$ts');
      if (expectedSignature != sig) {
        return PairingPayload(
          userId: uid,
          deviceName: dev,
          timestampSeconds: ts,
          signature: sig,
          isValid: false,
          validationError: 'Cryptographic signature mismatch. Possible tampering.',
        );
      }

      return PairingPayload(
        userId: uid,
        deviceName: dev,
        timestampSeconds: ts,
        signature: sig,
        isValid: true,
      );
    } catch (e) {
      return PairingPayload(
        userId: '',
        deviceName: '',
        timestampSeconds: 0,
        signature: '',
        isValid: false,
        validationError: 'Malformed URI: $e',
      );
    }
  }

  /// Generates a device authentication token signature for WebSocket handshakes.
  String generateDeviceAuthSignature({
    required String userId,
    required String deviceId,
    required int timestampMs,
  }) {
    final message = '$userId:$deviceId:$timestampMs';
    return _computeHmacSignature(message);
  }

  /// Verifies a device authentication token signature.
  bool verifyDeviceAuthSignature({
    required String userId,
    required String deviceId,
    required int timestampMs,
    required String signature,
    int? currentTimestampMs,
  }) {
    final nowMs = currentTimestampMs ?? DateTime.now().millisecondsSinceEpoch;
    // 5-minute replay tolerance
    if ((nowMs - timestampMs).abs() > (replayWindowSeconds * 1000)) {
      return false;
    }

    final expected = generateDeviceAuthSignature(
      userId: userId,
      deviceId: deviceId,
      timestampMs: timestampMs,
    );
    return expected == signature;
  }

  String _computeHmacSignature(String message) {
    final keyBytes = utf8.encode(_sharedSecret);
    final messageBytes = utf8.encode(message);
    final hmacSha256 = Hmac(sha256, keyBytes);
    final digest = hmacSha256.convert(messageBytes);
    return digest.toString();
  }
}
