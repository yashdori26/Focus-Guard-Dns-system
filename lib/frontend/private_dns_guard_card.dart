import 'dart:async';
import 'package:flutter/material.dart';
import '../backend/attestation_service.dart';

/// Interactive UI card inspecting Android 9+ Private DNS (DoT) state,
/// preventing tunnel circumvention, and preserving emergency telecom exemptions.
class PrivateDnsGuardCard extends StatefulWidget {
  final VoidCallback? onAuditRequested;

  const PrivateDnsGuardCard({
    super.key,
    this.onAuditRequested,
  });

  @override
  State<PrivateDnsGuardCard> createState() => _PrivateDnsGuardCardState();
}

class _PrivateDnsGuardCardState extends State<PrivateDnsGuardCard> {
  PrivateDnsStatusModel _status = const PrivateDnsStatusModel();
  bool _isLoading = false;
  bool _isAuditing = false;
  String _lastCheckTime = 'Just now';

  @override
  void initState() {
    super.initState();
    _refreshStatus();
  }

  Future<void> _refreshStatus() async {
    final status = await FocusAttestationManager.getPrivateDnsStatus();
    if (mounted) {
      setState(() {
        _status = status;
        _isLoading = false;
        _lastCheckTime = _formatTime(DateTime.now());
      });
    }
  }

  Future<void> _runCircumventionProbe() async {
    setState(() => _isAuditing = true);
    await Future.delayed(const Duration(milliseconds: 600));
    final status = await FocusAttestationManager.getPrivateDnsStatus();
    if (mounted) {
      setState(() {
        _status = status;
        _isAuditing = false;
        _lastCheckTime = _formatTime(DateTime.now());
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            status.isCompliant
                ? 'Private DNS audit passed: Local VPN tunnel is strictly respected.'
                : 'Warning: Private DNS circumvention detected (${status.hostnameSpecifier}).',
          ),
          backgroundColor: status.isCompliant ? const Color(0xFF2E7D32) : const Color(0xFFC62828),
        ),
      );
    }
  }

  String _formatTime(DateTime time) {
    return '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}:${time.second.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final isCompliant = _status.isCompliant;
    final badgeColor = isCompliant ? const Color(0xFF4CAF50) : const Color(0xFFE53935);

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
          // Header
          Row(
            children: [
              Icon(
                isCompliant ? Icons.vpn_lock : Icons.warning_amber_rounded,
                size: 20,
                color: badgeColor,
              ),
              const SizedBox(width: 10),
              const Expanded(
                child: Text(
                  'Private DNS (DoT) Defense',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                    letterSpacing: -0.2,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: badgeColor.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  isCompliant ? 'SECURE' : 'BYPASS DETECTED',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: badgeColor,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Description
          const Text(
            'Android 9+ Private DNS can bypass VPN interfaces if configured with a custom DNS-over-TLS resolver. '
            'FocusDNS active defense monitors Settings.Global to prevent filtering circumvention.',
            style: TextStyle(fontSize: 12, color: Color(0xFFAAAAAA), height: 1.35),
          ),
          const SizedBox(height: 14),

          // Status table
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFF141416),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFF2B2B2F)),
            ),
            child: _isLoading
                ? const Center(
                    child: SizedBox(
                      height: 24,
                      width: 24,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white54),
                    ),
                  )
                : Column(
                    children: [
                      _buildDetailRow('Mode', _status.mode.toUpperCase()),
                      _buildDetailRow(
                        'Hostname Specifier',
                        _status.hostnameSpecifier.isEmpty ? '(None / Local Tunnel)' : _status.hostnameSpecifier,
                      ),
                      _buildDetailRow(
                        'Compliance Verdict',
                        _status.reason,
                        valueColor: badgeColor,
                      ),
                      _buildDetailRow('Last Audited', _lastCheckTime),
                    ],
                  ),
          ),
          const SizedBox(height: 14),

          // Action row
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white,
                    side: const BorderSide(color: Color(0xFF3E3E42)),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    padding: const EdgeInsets.symmetric(vertical: 10),
                  ),
                  icon: _isAuditing
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white70),
                        )
                      : const Icon(Icons.shield_outlined, size: 16),
                  label: Text(
                    _isAuditing ? 'Auditing...' : 'Probe Circumvention',
                    style: const TextStyle(fontSize: 12),
                  ),
                  onPressed: _isAuditing ? null : _runCircumventionProbe,
                ),
              ),
              const SizedBox(width: 10),
              IconButton(
                tooltip: 'Refresh Status',
                icon: const Icon(Icons.refresh, size: 18, color: Colors.white70),
                onPressed: _refreshStatus,
              ),
            ],
          ),
          const SizedBox(height: 10),

          // Life safety footnote
          const Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Icon(Icons.health_and_safety, size: 14, color: Color(0xFF4CAF50)),
              SizedBox(width: 6),
              Expanded(
                child: Text(
                  'Emergency telephony (911/112) is exempt from all DNS redirection policies.',
                  style: TextStyle(fontSize: 11, color: Color(0xFF888888)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildDetailRow(String label, String value, {Color? valueColor}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(fontSize: 12, color: Color(0xFF777777))),
          Text(
            value,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: valueColor ?? Colors.white70,
            ),
          ),
        ],
      ),
    );
  }
}
