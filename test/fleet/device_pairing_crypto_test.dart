import 'package:flutter_test/flutter_test.dart';
import 'package:focus_dns/engine/profile/device_pairing_crypto.dart';

void main() {
  group('Device Pairing Crypto Tests', () {
    const crypto = DevicePairingCrypto('test_secret_key_12345');

    test('1. Generated pairing URI contains proper scheme, host, and params', () {
      final nowSec = 1700000000;
      final uri = crypto.generatePairingUri(
        userId: 'usr_alpha',
        deviceName: 'Chrome Extension',
        timestampSeconds: nowSec,
      );

      expect(uri.startsWith('focusdns://pair?'), isTrue);
      expect(uri.contains('uid=usr_alpha'), isTrue);
      expect(uri.contains('dev=Chrome+Extension') || uri.contains('dev=Chrome%20Extension'), isTrue);
      expect(uri.contains('ts=1700000000'), isTrue);
      expect(uri.contains('sig='), isTrue);
    });

    test('2. Valid pairing URI passes cryptographic validation', () {
      final nowSec = 1700000000;
      final uri = crypto.generatePairingUri(
        userId: 'usr_alpha',
        deviceName: 'Chrome Extension',
        timestampSeconds: nowSec,
      );

      final payload = crypto.parseAndValidatePairingUri(uri, nowSec + 30); // 30s later
      expect(payload.isValid, isTrue);
      expect(payload.userId, equals('usr_alpha'));
      expect(payload.deviceName, equals('Chrome Extension'));
      expect(payload.validationError, isNull);
    });

    test('3. Expired pairing URI outside 5-minute replay window is rejected', () {
      final oldSec = 1700000000;
      final uri = crypto.generatePairingUri(
        userId: 'usr_alpha',
        deviceName: 'Laptop',
        timestampSeconds: oldSec,
      );

      // Attempt validation 10 minutes later (600s > 300s)
      final payload = crypto.parseAndValidatePairingUri(uri, oldSec + 600);
      expect(payload.isValid, isFalse);
      expect(payload.validationError?.contains('expired'), isTrue);
    });

    test('4. Tampered query parameter fails HMAC signature validation', () {
      final nowSec = 1700000000;
      final uri = crypto.generatePairingUri(
        userId: 'usr_alpha',
        deviceName: 'Laptop',
        timestampSeconds: nowSec,
      );

      // Maliciously tamper user ID in URI
      final tamperedUri = uri.replaceAll('uid=usr_alpha', 'uid=usr_hacked');
      final payload = crypto.parseAndValidatePairingUri(tamperedUri, nowSec + 10);

      expect(payload.isValid, isFalse);
      expect(payload.validationError?.contains('mismatch'), isTrue);
    });

    test('5. Device authentication signature generation and verification', () {
      final ts = 1700000000000;
      final sig = crypto.generateDeviceAuthSignature(
        userId: 'usr_123',
        deviceId: 'dev_456',
        timestampMs: ts,
      );

      expect(sig, isNotEmpty);
      expect(sig.length, equals(64)); // 256-bit hex is 64 chars

      final isValid = crypto.verifyDeviceAuthSignature(
        userId: 'usr_123',
        deviceId: 'dev_456',
        timestampMs: ts,
        signature: sig,
        currentTimestampMs: ts + 1000,
      );
      expect(isValid, isTrue);

      final isInvalidDevice = crypto.verifyDeviceAuthSignature(
        userId: 'usr_123',
        deviceId: 'dev_wrong',
        timestampMs: ts,
        signature: sig,
        currentTimestampMs: ts + 1000,
      );
      expect(isInvalidDevice, isFalse);
    });
  });
}
