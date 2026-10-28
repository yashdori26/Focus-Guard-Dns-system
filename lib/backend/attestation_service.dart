import 'dart:async';
import 'package:flutter/services.dart';

/// Represents the hardware security posture of the endpoint's cryptographic Keystore.
class HardwareAttestationModel {
  final String alias;
  final String securityLevel;
  final String publicKeyBase64;
  final int certificateChainLength;
  final bool isHardwareBacked;

  const HardwareAttestationModel({
    this.alias = 'focus_dns_master_attestation_key_v1',
    this.securityLevel = 'TRUSTED_EXECUTION_ENVIRONMENT',
    this.publicKeyBase64 = '',
    this.certificateChainLength = 3,
    this.isHardwareBacked = true,
  });

  factory HardwareAttestationModel.fromMap(Map<dynamic, dynamic> map) {
    return HardwareAttestationModel(
      alias: (map['alias'] ?? '').toString(),
      securityLevel: (map['securityLevel'] ?? 'TRUSTED_EXECUTION_ENVIRONMENT').toString(),
      publicKeyBase64: (map['publicKeyBase64'] ?? '').toString(),
      certificateChainLength: (map['certificateChainLength'] as num?)?.toInt() ?? 0,
      isHardwareBacked: map['isHardwareBacked'] == true,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'alias': alias,
      'securityLevel': securityLevel,
      'publicKeyBase64': publicKeyBase64,
      'certificateChainLength': certificateChainLength,
      'isHardwareBacked': isHardwareBacked,
    };
  }
}

/// Represents the Android Private DNS (DoT) compliance state.
class PrivateDnsStatusModel {
  final String mode;
  final String hostnameSpecifier;
  final bool isCompliant;
  final String reason;

  const PrivateDnsStatusModel({
    this.mode = 'opportunistic',
    this.hostnameSpecifier = '',
    this.isCompliant = true,
    this.reason = 'COMPLIANT',
  });

  factory PrivateDnsStatusModel.fromMap(Map<dynamic, dynamic> map) {
    return PrivateDnsStatusModel(
      mode: (map['mode'] ?? 'off').toString(),
      hostnameSpecifier: (map['hostnameSpecifier'] ?? '').toString(),
      isCompliant: map['isCompliant'] == true,
      reason: (map['reason'] ?? '').toString(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'mode': mode,
      'hostnameSpecifier': hostnameSpecifier,
      'isCompliant': isCompliant,
      'reason': reason,
    };
  }
}

/// Signed attestation payload assertion for anti-tamper verification.
class SignedAssertionModel {
  final String payload;
  final String nonce;
  final String signatureBase64;
  final int timestampMs;
  final String keyAlias;

  const SignedAssertionModel({
    required this.payload,
    required this.nonce,
    required this.signatureBase64,
    required this.timestampMs,
    required this.keyAlias,
  });

  factory SignedAssertionModel.fromMap(Map<dynamic, dynamic> map) {
    return SignedAssertionModel(
      payload: (map['payload'] ?? '').toString(),
      nonce: (map['nonce'] ?? '').toString(),
      signatureBase64: (map['signatureBase64'] ?? '').toString(),
      timestampMs: (map['timestampMs'] as num?)?.toInt() ?? 0,
      keyAlias: (map['keyAlias'] ?? '').toString(),
    );
  }
}

/// Manager service coordinating hardware attestation, Private DNS, and emergency bypass.
class FocusAttestationManager {
  static const MethodChannel _channel = MethodChannel('focus_dns/mdm');

  // Simulation fallbacks for desktop and tests
  static bool _simulatedHardwareBacked = true;
  static String _simulatedSecurityLevel = 'TRUSTED_EXECUTION_ENVIRONMENT';
  static PrivateDnsStatusModel _simulatedPrivateDns = const PrivateDnsStatusModel();
  static bool _simulatedCanDrawOverlays = true;

  static void setSimulatedState({
    bool? isHardwareBacked,
    String? securityLevel,
    PrivateDnsStatusModel? privateDns,
    bool? canDrawOverlays,
  }) {
    if (isHardwareBacked != null) _simulatedHardwareBacked = isHardwareBacked;
    if (securityLevel != null) _simulatedSecurityLevel = securityLevel;
    if (privateDns != null) _simulatedPrivateDns = privateDns;
    if (canDrawOverlays != null) _simulatedCanDrawOverlays = canDrawOverlays;
  }

  /// Retrieves hardware attestation details from device KeyStore.
  static Future<HardwareAttestationModel> getHardwareAttestation() async {
    try {
      final res = await _channel.invokeMethod<Map<dynamic, dynamic>>('getHardwareAttestation');
      if (res != null) {
        return HardwareAttestationModel.fromMap(res);
      }
    } catch (_) {
      // Fallback to simulation
    }

    return HardwareAttestationModel(
      alias: 'focus_dns_master_attestation_key_v1',
      securityLevel: _simulatedSecurityLevel,
      publicKeyBase64: 'MFkwEwYHKoZIzj0CAQYIKoZIzj0DAQcDQgAE7q2n3',
      certificateChainLength: 3,
      isHardwareBacked: _simulatedHardwareBacked,
    );
  }

  /// Signs an arbitrary state assertion with hardware private key.
  static Future<SignedAssertionModel> signPayload(String payload, {String? nonce}) async {
    try {
      final res = await _channel.invokeMethod<Map<dynamic, dynamic>>('signAttestationPayload', {
        'payload': payload,
        if (nonce != null) 'nonce': nonce,
      });
      if (res != null) {
        return SignedAssertionModel.fromMap(res);
      }
    } catch (_) {
      // Simulation
    }

    final n = nonce ?? 'simulated_nonce_1234567890abcdef1234567890abcdef';
    return SignedAssertionModel(
      payload: payload,
      nonce: n,
      signatureBase64: 'MEQCIAz7x3y5w...simulated_ecdsa_sig...',
      timestampMs: DateTime.now().millisecondsSinceEpoch,
      keyAlias: 'focus_dns_master_attestation_key_v1',
    );
  }

  /// Inspects system Private DNS compliance.
  static Future<PrivateDnsStatusModel> getPrivateDnsStatus() async {
    try {
      final res = await _channel.invokeMethod<Map<dynamic, dynamic>>('getPrivateDnsStatus');
      if (res != null) {
        return PrivateDnsStatusModel.fromMap(res);
      }
    } catch (_) {
      // Simulation
    }

    return _simulatedPrivateDns;
  }

  /// Checks if SYSTEM_ALERT_WINDOW permission is granted.
  static Future<bool> canDrawOverlays() async {
    try {
      final res = await _channel.invokeMethod<bool>('canDrawOverlays');
      if (res != null) return res;
    } catch (_) {
      // Simulation
    }
    return _simulatedCanDrawOverlays;
  }

  /// Requests overlay permission from system settings.
  static Future<bool> requestOverlayPermission() async {
    try {
      final res = await _channel.invokeMethod<bool>('requestOverlayPermission');
      if (res != null) return res;
    } catch (_) {
      // Simulation
    }
    return false;
  }

  /// Triggers emergency dialer with life-safety number.
  static Future<bool> triggerEmergencyCall({String number = '112'}) async {
    try {
      final res = await _channel.invokeMethod<bool>('triggerEmergencyCall', {'number': number});
      if (res != null) return res;
    } catch (_) {
      // Simulation
    }
    return true;
  }
}
