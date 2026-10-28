import 'dart:async';
import 'package:flutter/material.dart';
import '../backend/mdm_service.dart';
import 'split_tunnel_screen.dart';
import 'device_policy_audit_screen.dart';

/// A card component displaying Device Administrator status and the live uninstallation lock state.
class MdmShieldCard extends StatefulWidget {
  const MdmShieldCard({super.key});

  @override
  State<MdmShieldCard> createState() => _MdmShieldCardState();
}

class _MdmShieldCardState extends State<MdmShieldCard> {
  MdmLockStatus _status = const MdmLockStatus();
  bool _isAdminActive = false;
  bool _isLoading = true;
  StreamSubscription<MdmLockStatus>? _subscription;

  @override
  void initState() {
    super.initState();
    _loadInitialState();
    _subscription = FocusMdmManager.lockStatusStream.listen((status) {
      if (mounted) {
        setState(() {
          _status = status;
          _isAdminActive = status.isDeviceAdminActive;
        });
      }
    });
  }

  Future<void> _loadInitialState() async {
    final status = await FocusMdmManager.getLockStatus();
    final adminActive = await FocusMdmManager.isDeviceAdminActive();
    if (mounted) {
      setState(() {
        _status = status;
        _isAdminActive = adminActive;
        _isLoading = false;
      });
    }
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  Future<void> _toggleDeviceAdmin() async {
    setState(() => _isLoading = true);
    if (_isAdminActive) {
      // Try to deactivate
      final success = await FocusMdmManager.deactivateDeviceAdmin();
      if (!success && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: const Color(0xFF2C2C2E),
            content: Text(
              _status.isTimerActive
                  ? 'Cannot deactivate admin! Focus session active (${_status.formattedRemainingTime} remaining).'
                  : 'Cannot deactivate admin while DNS Protection is running.',
              style: const TextStyle(color: Colors.white),
            ),
          ),
        );
      }
    } else {
      await FocusMdmManager.requestDeviceAdmin();
    }
    await _loadInitialState();
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const SizedBox(
        height: 120,
        child: Center(
          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white54),
        ),
      );
    }

    final isLocked = !_status.canUninstall;

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E20),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isLocked ? const Color(0xFFE5A93C).withOpacity(0.4) : const Color(0xFF2C2C2E),
          width: 1,
        ),
      ),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                isLocked ? Icons.lock_clock : Icons.shield_outlined,
                color: isLocked ? const Color(0xFFE5A93C) : const Color(0xFF4CAF50),
                size: 24,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Anti-Uninstall & Device Shield',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                    letterSpacing: -0.3,
                  ),
                ),
              ),
              // Status Pill
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: isLocked
                      ? const Color(0xFFE5A93C).withOpacity(0.15)
                      : const Color(0xFF4CAF50).withOpacity(0.15),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  isLocked ? '🔒 LOCKED' : '✓ UNLOCKED',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: isLocked ? const Color(0xFFE5A93C) : const Color(0xFF4CAF50),
                    letterSpacing: 0.5,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            isLocked
                ? 'Uninstallation and removal are strictly locked to protect your focus. The lock will automatically release when your session timer reaches 00:00.'
                : 'Uninstallation is currently allowed. When you start a focus countdown or turn on protection, uninstallation locks automatically until the session ends.',
            style: const TextStyle(
              fontSize: 13,
              color: Color(0xFF9E9E9E),
              height: 1.4,
            ),
          ),
          if (isLocked && _status.isTimerActive) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFF141416),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  const Icon(Icons.timer_outlined, size: 18, color: Color(0xFFE5A93C)),
                  const SizedBox(width: 8),
                  Text(
                    'Time until uninstallation unlocks:',
                    style: const TextStyle(fontSize: 12, color: Color(0xFFB0B0B0)),
                  ),
                  const Spacer(),
                  Text(
                    _status.formattedRemainingTime,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      fontFamily: 'monospace',
                      color: Color(0xFFE5A93C),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 16),
          const Divider(color: Color(0xFF2C2C2E), height: 1),
          const SizedBox(height: 16),
          // Device Administrator Switch
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Device Administrator',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _isAdminActive
                          ? 'Enrolled (Hardware protection active)'
                          : 'Tap to enroll (Blocks system settings evasion)',
                      style: const TextStyle(fontSize: 12, color: Color(0xFF888888)),
                    ),
                  ],
                ),
              ),
              Switch(
                value: _isAdminActive,
                onChanged: (_) => _toggleDeviceAdmin(),
                activeColor: const Color(0xFF4CAF50),
                activeTrackColor: const Color(0xFF4CAF50).withOpacity(0.3),
                inactiveThumbColor: const Color(0xFF888888),
                inactiveTrackColor: const Color(0xFF2C2C2E),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // Per-App Split Tunneling Navigation
          InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const SplitTunnelScreen()),
              );
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: const Color(0xFF141416),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFF2C2C2E)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.alt_route, size: 18, color: Colors.white70),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Text(
                      'Per-App Split Tunneling (Bypass Apps)',
                      style: TextStyle(fontSize: 13, color: Colors.white),
                    ),
                  ),
                  const Icon(Icons.arrow_forward_ios, size: 14, color: Colors.white38),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          // Security & Policy Audit Navigation
          InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const DevicePolicyAuditScreen()),
              );
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: const Color(0xFF141416),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFF2C2C2E)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.security, size: 18, color: Colors.white70),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Text(
                      'Device Security & Policy Audit',
                      style: TextStyle(fontSize: 13, color: Colors.white),
                    ),
                  ),
                  const Icon(Icons.arrow_forward_ios, size: 14, color: Colors.white38),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
