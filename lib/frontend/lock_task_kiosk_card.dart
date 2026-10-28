import 'dart:async';
import 'package:flutter/material.dart';
import '../backend/dpc_service.dart';
import '../backend/attestation_service.dart';

/// Card managing Android Enterprise LockTask (Single/Multi-App Kiosk Mode)
/// with hardcoded life-safety emergency dialer exemptions.
class LockTaskKioskCard extends StatefulWidget {
  const LockTaskKioskCard({super.key});

  @override
  State<LockTaskKioskCard> createState() => _LockTaskKioskCardState();
}

class _LockTaskKioskCardState extends State<LockTaskKioskCard> {
  bool _isKioskActive = false;
  bool _isProcessing = false;

  final List<String> _whitelistedApps = const [
    'FocusDNS (Active App)',
    'Emergency Phone Dialer (com.android.phone)',
    'Google / Samsung Dialer (com.google.android.dialer)',
    'Telecom In-Call UI (com.android.server.telecom)',
  ];

  @override
  void initState() {
    super.initState();
    _checkKioskState();
  }

  Future<void> _checkKioskState() async {
    final active = await FocusDpcService.isKioskModeActive();
    if (mounted) {
      setState(() => _isKioskActive = active);
    }
  }

  Future<void> _toggleKioskMode() async {
    setState(() => _isProcessing = true);
    if (_isKioskActive) {
      await FocusDpcService.stopKioskMode();
    } else {
      await FocusDpcService.startKioskMode();
    }
    await Future.delayed(const Duration(milliseconds: 300));
    final active = await FocusDpcService.isKioskModeActive();
    if (mounted) {
      setState(() {
        _isKioskActive = active;
        _isProcessing = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            active
                ? 'LockTask Kiosk Mode entered. Navigation bar pinned to FocusDNS.'
                : 'LockTask Kiosk Mode stopped. Normal navigation restored.',
          ),
          backgroundColor: active ? const Color(0xFF1565C0) : const Color(0xFF2E7D32),
        ),
      );
    }
  }

  void _triggerEmergencyDialer() {
    FocusAttestationManager.triggerEmergencyCall(number: '112');
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Emergency dialer launched (112 exempt).'),
        backgroundColor: Color(0xFFE53935),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final statusColor = _isKioskActive ? const Color(0xFF29B6F6) : const Color(0xFF888888);

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
              Icon(Icons.lock_person, size: 20, color: statusColor),
              const SizedBox(width: 10),
              const Expanded(
                child: Text(
                  'Dedicated LockTask (Kiosk)',
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
                  color: statusColor.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  _isKioskActive ? 'PINNED / ACTIVE' : 'STANDBY',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: statusColor,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          const Text(
            'Pins the screen strictly to FocusDNS during active focus sessions, hiding notifications and task switchers. '
            'Telecom emergency dialers are hardcoded to remain accessible at all times.',
            style: TextStyle(fontSize: 12, color: Color(0xFFAAAAAA), height: 1.35),
          ),
          const SizedBox(height: 14),

          // Whitelisted packages summary
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFF141416),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFF2A2A2E)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Icon(Icons.checklist, size: 14, color: Color(0xFF81D4FA)),
                    SizedBox(width: 6),
                    Text(
                      'Permitted Kiosk App Manifest:',
                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.white70),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                ..._whitelistedApps.map((app) => Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: Row(
                        children: [
                          const Icon(Icons.check, size: 12, color: Color(0xFF4CAF50)),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              app,
                              style: const TextStyle(fontSize: 11, color: Color(0xFFBBBBBB)),
                            ),
                          ),
                        ],
                      ),
                    )),
              ],
            ),
          ),
          const SizedBox(height: 14),

          // Action row
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _isKioskActive ? const Color(0xFFC62828) : const Color(0xFF1565C0),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    padding: const EdgeInsets.symmetric(vertical: 10),
                  ),
                  icon: _isProcessing
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white70),
                        )
                      : Icon(_isKioskActive ? Icons.lock_open : Icons.lock_outline, size: 16),
                  label: Text(
                    _isProcessing
                        ? 'Applying...'
                        : (_isKioskActive ? 'Exit Kiosk Mode' : 'Start Focus Kiosk'),
                    style: const TextStyle(fontSize: 12),
                  ),
                  onPressed: _isProcessing ? null : _toggleKioskMode,
                ),
              ),
              const SizedBox(width: 10),
              IconButton(
                tooltip: 'Emergency SOS 112',
                icon: const Icon(Icons.emergency, color: Color(0xFFE53935)),
                onPressed: _triggerEmergencyDialer,
              ),
            ],
          ),
          const SizedBox(height: 10),

          // Uninstallation guarantee footnote
          const Row(
            children: [
              Icon(Icons.info_outline, size: 13, color: Color(0xFF888888)),
              SizedBox(width: 6),
              Expanded(
                child: Text(
                  'Kiosk pin cleanly releases when focus timer reaches zero, restoring normal mode.',
                  style: TextStyle(fontSize: 11, color: Color(0xFF777777)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
