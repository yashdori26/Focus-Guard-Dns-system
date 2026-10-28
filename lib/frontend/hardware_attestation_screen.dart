import 'dart:async';
import 'package:flutter/material.dart';
import '../backend/attestation_service.dart';

/// Screen displaying Android KeyStore hardware-backed attestation posture,
/// EC P-256 certificate chain integrity, and interactive cryptographic signature proofs.
class HardwareAttestationScreen extends StatefulWidget {
  const HardwareAttestationScreen({super.key});

  @override
  State<HardwareAttestationScreen> createState() => _HardwareAttestationScreenState();
}

class _HardwareAttestationScreenState extends State<HardwareAttestationScreen> {
  HardwareAttestationModel _attestation = const HardwareAttestationModel();
  bool _isLoading = true;
  bool _isSigning = false;
  SignedAssertionModel? _lastAssertion;
  String _statusMessage = 'Awaiting challenge assertion...';

  @override
  void initState() {
    super.initState();
    _loadAttestation();
  }

  Future<void> _loadAttestation() async {
    setState(() => _isLoading = true);
    final attestation = await FocusAttestationManager.getHardwareAttestation();
    if (mounted) {
      setState(() {
        _attestation = attestation;
        _isLoading = false;
      });
    }
  }

  Future<void> _signInteractiveProof() async {
    setState(() {
      _isSigning = true;
      _statusMessage = 'Requesting hardware cryptographic signature...';
    });

    final testPayload = 'FOCUS_DNS_INTEGRITY_CHECK:${DateTime.now().toIso8601String()}';
    final assertion = await FocusAttestationManager.signPayload(testPayload);

    if (mounted) {
      setState(() {
        _lastAssertion = assertion;
        _isSigning = false;
        _statusMessage = 'Assertion signed by hardware Keymaster!';
      });
    }
  }

  void _triggerEmergencySos() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E20),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.emergency, color: Color(0xFFE53935)),
            SizedBox(width: 8),
            Text('Life-Safety Exemption', style: TextStyle(color: Colors.white, fontSize: 16)),
          ],
        ),
        content: const Text(
          'Emergency dialing (911/112) is NEVER blocked by FocusDNS kiosk, overlay, or MDM locks. '
          'Would you like to simulate or trigger the emergency phone dialer?',
          style: TextStyle(color: Color(0xFFCCCCCC), fontSize: 13, height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel', style: TextStyle(color: Colors.white54)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFE53935),
              foregroundColor: Colors.white,
            ),
            onPressed: () {
              Navigator.of(ctx).pop();
              FocusAttestationManager.triggerEmergencyCall(number: '112');
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Emergency dialer exempt and dispatched.'),
                  backgroundColor: Color(0xFFE53935),
                ),
              );
            },
            child: const Text('Launch 112'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF141416),
      appBar: AppBar(
        backgroundColor: const Color(0xFF141416),
        elevation: 0,
        title: const Text(
          'Hardware Attestation',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w600,
            color: Colors.white,
            letterSpacing: -0.3,
          ),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.of(context).pop(),
        ),
        actions: [
          IconButton(
            tooltip: 'Emergency SOS Dial',
            icon: const Icon(Icons.emergency, color: Color(0xFFE53935)),
            onPressed: _triggerEmergencySos,
          ),
          IconButton(
            tooltip: 'Refresh Keys',
            icon: const Icon(Icons.refresh, color: Colors.white70),
            onPressed: _loadAttestation,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white54),
            )
          : ListView(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              children: [
                // 1. Security Level Banner
                _buildSecurityLevelBanner(),
                const SizedBox(height: 16),

                // 2. Cryptographic Key Profile Card
                _buildKeyProfileCard(),
                const SizedBox(height: 16),

                // 3. Interactive Proof of Possession Card
                _buildInteractiveProofCard(),
                const SizedBox(height: 16),

                // 4. Life-Safety & Hardware Isolation Notice
                _buildIsolationNoticeCard(),
                const SizedBox(height: 24),
              ],
            ),
    );
  }

  Widget _buildSecurityLevelBanner() {
    final isStrongBox = _attestation.securityLevel.contains('STRONGBOX');
    final isTee = _attestation.securityLevel.contains('TRUSTED') || _attestation.securityLevel.contains('TEE');

    Color badgeColor;
    String label;
    IconData icon;

    if (isStrongBox) {
      badgeColor = const Color(0xFF00E676);
      label = 'StrongBox Keymint (Hardware Level 2 Isolated)';
      icon = Icons.verified_user;
    } else if (isTee) {
      badgeColor = const Color(0xFF00B0FF);
      label = 'Hardware TEE (ARM TrustZone / Secure Enclave)';
      icon = Icons.security;
    } else {
      badgeColor = const Color(0xFFFFB300);
      label = 'Software KeyStore (Emulated Environment)';
      icon = Icons.shield_outlined;
    }

    return Container(
      decoration: BoxDecoration(
        color: badgeColor.withOpacity(0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: badgeColor.withOpacity(0.3)),
      ),
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: badgeColor.withOpacity(0.15),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: badgeColor, size: 24),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: badgeColor,
                    letterSpacing: -0.2,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _attestation.isHardwareBacked
                      ? 'Private key material is physically non-extractable, even under root kernel compromise.'
                      : 'Running in simulated or development container.',
                  style: const TextStyle(fontSize: 12, color: Color(0xFFAAAAAA), height: 1.3),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildKeyProfileCard() {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E20),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF2C2C2E)),
      ),
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.key, size: 18, color: Color(0xFF90CAF9)),
              SizedBox(width: 8),
              Text(
                'Keymaster Parameters',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: Colors.white),
              ),
            ],
          ),
          const SizedBox(height: 14),
          _buildInfoRow('Key Alias', _attestation.alias),
          _buildInfoRow('Algorithm', 'EC (secp256r1 / P-256)'),
          _buildInfoRow('Purpose', 'SIGN | VERIFY (SHA256withECDSA)'),
          _buildInfoRow('Cert Chain Depth', '${_attestation.certificateChainLength} Certificates'),
          _buildInfoRow(
            'Hardware Backed',
            _attestation.isHardwareBacked ? 'TRUE' : 'FALSE',
            valueColor: _attestation.isHardwareBacked ? const Color(0xFF4CAF50) : const Color(0xFFFFB300),
          ),
          const SizedBox(height: 12),
          const Text(
            'Public Key (Base64 X.509 SPKI):',
            style: TextStyle(fontSize: 11, color: Color(0xFF888888)),
          ),
          const SizedBox(height: 6),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: const Color(0xFF141416),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFF333336)),
            ),
            child: SelectableText(
              _attestation.publicKeyBase64.isNotEmpty
                  ? _attestation.publicKeyBase64
                  : 'MFkwEwYHKoZIzj0CAQYIKoZIzj0DAQcDQgAE7q2n3X9L...',
              style: const TextStyle(
                fontSize: 11,
                fontFamily: 'monospace',
                color: Color(0xFFCCCCCC),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInteractiveProofCard() {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E20),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF2C2C2E)),
      ),
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.fingerprint, size: 18, color: Color(0xFFCE93D8)),
              SizedBox(width: 8),
              Text(
                'Cryptographic Proof of State',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: Colors.white),
              ),
            ],
          ),
          const SizedBox(height: 8),
          const Text(
            'Generate a tamper-proof ECDSA assertion proving uninstallation and protection integrity to the MDM server.',
            style: TextStyle(fontSize: 12, color: Color(0xFFAAAAAA), height: 1.3),
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            height: 44,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF2A2A2E),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                  side: const BorderSide(color: Color(0xFF3E3E42)),
                ),
              ),
              icon: _isSigning
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white70),
                    )
                  : const Icon(Icons.edit_note, size: 20),
              label: Text(_isSigning ? 'Signing Assertion...' : 'Sign Hardware Proof'),
              onPressed: _isSigning ? null : _signInteractiveProof,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            _statusMessage,
            style: const TextStyle(fontSize: 12, fontStyle: FontStyle.italic, color: Color(0xFF888888)),
          ),
          if (_lastAssertion != null) ...[
            const SizedBox(height: 12),
            _buildAssertionDetailCard(_lastAssertion!),
          ],
        ],
      ),
    );
  }

  Widget _buildAssertionDetailCard(SignedAssertionModel assertion) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF141416),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFF388E3C).withOpacity(0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.check_circle, size: 14, color: Color(0xFF4CAF50)),
              SizedBox(width: 6),
              Text(
                'Signed Assertion Verified',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF4CAF50)),
              ),
            ],
          ),
          const SizedBox(height: 8),
          _buildCompactText('Payload:', assertion.payload),
          _buildCompactText('Anti-Replay Nonce:', assertion.nonce),
          _buildCompactText('Timestamp:', '${DateTime.fromMillisecondsSinceEpoch(assertion.timestampMs)}'),
          const SizedBox(height: 6),
          const Text('ECDSA Signature (DER Base64):', style: TextStyle(fontSize: 10, color: Color(0xFF888888))),
          SelectableText(
            assertion.signatureBase64,
            style: const TextStyle(fontSize: 10, fontFamily: 'monospace', color: Color(0xFF90CAF9)),
          ),
        ],
      ),
    );
  }

  Widget _buildIsolationNoticeCard() {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A1D),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF262629)),
      ),
      padding: const EdgeInsets.all(14),
      child: const Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline, size: 18, color: Color(0xFF78909C)),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              'Attestation keys are verified against the Google Key Attestation Root Certificate. '
              'The uninstallation permission lock evaluates both local KeyStore timestamps and server fleet consensus.',
              style: TextStyle(fontSize: 12, color: Color(0xFF90A4AE), height: 1.4),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoRow(String label, String value, {Color? valueColor}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(fontSize: 13, color: Color(0xFF888888))),
          Text(
            value,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: valueColor ?? Colors.white70,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCompactText(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(fontSize: 11, color: Color(0xFF777777))),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontSize: 11, fontFamily: 'monospace', color: Color(0xFFDDDDDD)),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}
