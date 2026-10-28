import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:focus_dns/backend/attestation_service.dart';
import 'package:focus_dns/frontend/hardware_attestation_screen.dart';
import 'package:focus_dns/frontend/private_dns_guard_card.dart';
import 'package:focus_dns/frontend/multi_oem_shield_card.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('focus_dns/mdm'),
      (MethodCall methodCall) async {
        if (methodCall.method == 'getHardwareAttestation') {
          return {
            'alias': 'focus_dns_master_attestation_key_v1',
            'securityLevel': 'STRONGBOX',
            'publicKeyBase64': 'MFkwEwYHKoZIzj0CAQYIKoZIzj0DAQcDQgAE7q2n3X9L...',
            'certificateChainLength': 3,
            'isHardwareBacked': true,
          };
        }
        if (methodCall.method == 'getPrivateDnsStatus') {
          return {
            'mode': 'opportunistic',
            'hostnameSpecifier': '',
            'isCompliant': true,
            'reason': 'COMPLIANT_OPPORTUNISTIC',
          };
        }
        if (methodCall.method == 'canDrawOverlays') {
          return true;
        }
        if (methodCall.method == 'signAttestationPayload') {
          return {
            'payload': methodCall.arguments['payload'] ?? 'test',
            'nonce': methodCall.arguments['nonce'] ?? 'simulated_nonce_123',
            'signatureBase64': 'MEQCIDxyz...',
            'timestampMs': 1700000000000,
            'keyAlias': 'focus_dns_master_attestation_key_v1',
          };
        }
        if (methodCall.method == 'triggerEmergencyCall') {
          return true;
        }
        return null;
      },
    );
  });

  group('Hardware Attestation & Anti-Bypass Unit Tests', () {
    test('HardwareAttestationModel serialization and defaults', () {
      const model = HardwareAttestationModel();
      expect(model.alias, 'focus_dns_master_attestation_key_v1');
      expect(model.securityLevel, 'TRUSTED_EXECUTION_ENVIRONMENT');
      expect(model.isHardwareBacked, isTrue);
      expect(model.certificateChainLength, 3);

      final map = model.toMap();
      final fromMap = HardwareAttestationModel.fromMap(map);
      expect(fromMap.alias, model.alias);
      expect(fromMap.securityLevel, model.securityLevel);
      expect(fromMap.isHardwareBacked, model.isHardwareBacked);
      expect(fromMap.certificateChainLength, 3);
    });

    test('PrivateDnsStatusModel compliance verification', () {
      const compliant = PrivateDnsStatusModel(
        mode: 'opportunistic',
        hostnameSpecifier: '',
        isCompliant: true,
        reason: 'COMPLIANT',
      );
      expect(compliant.isCompliant, isTrue);

      final rogue = PrivateDnsStatusModel.fromMap(const {
        'mode': 'strict',
        'hostnameSpecifier': 'dns.rogue-bypass.com',
        'isCompliant': false,
        'reason': 'ROGUE_DOT_SPECIFIER_DETECTED',
      });
      expect(rogue.isCompliant, isFalse);
      expect(rogue.hostnameSpecifier, 'dns.rogue-bypass.com');
      expect(rogue.reason, 'ROGUE_DOT_SPECIFIER_DETECTED');
    });

    test('SignedAssertionModel serialization', () {
      final assertion = SignedAssertionModel.fromMap(const {
        'payload': 'CHALLENGE_9999',
        'nonce': '1122334455667788',
        'signatureBase64': 'MEQCIDxyz...',
        'timestampMs': 1700000000000,
        'keyAlias': 'focus_dns_test_key',
      });
      expect(assertion.payload, 'CHALLENGE_9999');
      expect(assertion.nonce, '1122334455667788');
      expect(assertion.signatureBase64, 'MEQCIDxyz...');
      expect(assertion.timestampMs, 1700000000000);
      expect(assertion.keyAlias, 'focus_dns_test_key');
    });

    test('FocusAttestationManager simulation controls', () async {
      final att = await FocusAttestationManager.getHardwareAttestation();
      expect(att.securityLevel, 'STRONGBOX');
      expect(att.isHardwareBacked, isTrue);

      final signed = await FocusAttestationManager.signPayload('TEST_STATE');
      expect(signed.payload, 'TEST_STATE');
      expect(signed.signatureBase64.isNotEmpty, isTrue);

      final dns = await FocusAttestationManager.getPrivateDnsStatus();
      expect(dns.mode, 'opportunistic');
      expect(dns.isCompliant, isTrue);

      final canOverlay = await FocusAttestationManager.canDrawOverlays();
      expect(canOverlay, isTrue);

      final emergencyOk = await FocusAttestationManager.triggerEmergencyCall(number: '911');
      expect(emergencyOk, isTrue);
    });
  });

  group('Phase 2 Widget Tests', () {
    testWidgets('HardwareAttestationScreen renders StrongBox security level and signs assertion', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: HardwareAttestationScreen(),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Hardware Attestation'), findsOneWidget);
      expect(find.textContaining('StrongBox Keymint'), findsOneWidget);
      expect(find.text('Keymaster Parameters'), findsOneWidget);
      expect(find.text('Cryptographic Proof of State'), findsOneWidget);

      // Tap Sign Hardware Proof
      final signButton = find.text('Sign Hardware Proof');
      expect(signButton, findsOneWidget);
      await tester.tap(signButton);
      await tester.pumpAndSettle();

      expect(find.textContaining('Signed Assertion Verified'), findsOneWidget);
      expect(find.textContaining('Assertion signed by hardware Keymaster!'), findsOneWidget);
    });

    testWidgets('HardwareAttestationScreen emergency dialog flow', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: HardwareAttestationScreen(),
        ),
      );
      await tester.pumpAndSettle();

      final emergencyIcon = find.byTooltip('Emergency SOS Dial');
      expect(emergencyIcon, findsOneWidget);
      await tester.tap(emergencyIcon);
      await tester.pumpAndSettle();

      expect(find.text('Life-Safety Exemption'), findsOneWidget);
      expect(find.textContaining('Emergency dialing (911/112) is NEVER blocked'), findsOneWidget);

      await tester.tap(find.text('Launch 112'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.text('Emergency dialer exempt and dispatched.'), findsOneWidget);
    });

    testWidgets('PrivateDnsGuardCard displays compliant status and runs probe', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: PrivateDnsGuardCard()),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Private DNS (DoT) Defense'), findsOneWidget);
      expect(find.text('SECURE'), findsOneWidget);
      expect(find.text('OPPORTUNISTIC'), findsOneWidget);

      final probeBtn = find.text('Probe Circumvention');
      expect(probeBtn, findsOneWidget);
      await tester.tap(probeBtn);
      await tester.pump(const Duration(milliseconds: 700));
      await tester.pump();

      expect(find.textContaining('Private DNS audit passed'), findsOneWidget);
    });

    testWidgets('MultiOemShieldCard renders OEM support chips and vectors', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: MultiOemShieldCard()),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Multi-OEM Anti-Evasion Matrix'), findsOneWidget);
      expect(find.text('Samsung OneUI'), findsOneWidget);
      expect(find.text('Xiaomi HyperOS'), findsOneWidget);
      expect(find.text('Oppo ColorOS'), findsOneWidget);
      expect(find.text('Vivo OriginOS'), findsOneWidget);
      expect(find.text('Huawei EMUI'), findsOneWidget);
      expect(find.text('Google Pixel'), findsOneWidget);

      expect(find.text('System Alert Overlay Active'), findsOneWidget);
    });

    testWidgets('MultiOemShieldCard prompts for overlay when not granted', (tester) async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
        const MethodChannel('focus_dns/mdm'),
        (MethodCall methodCall) async {
          if (methodCall.method == 'canDrawOverlays') {
            return false;
          }
          return null;
        },
      );

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: MultiOemShieldCard()),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Overlay Permission Needed'), findsOneWidget);
      expect(find.text('Grant'), findsOneWidget);
    });
  });
}
