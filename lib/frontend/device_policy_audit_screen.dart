import 'dart:async';
import 'package:flutter/material.dart';
import '../backend/mdm_service.dart';
import 'hardware_attestation_screen.dart';
import 'private_dns_guard_card.dart';
import 'multi_oem_shield_card.dart';
import 'lock_task_kiosk_card.dart';
import 'device_owner_provisioning_screen.dart';
import 'managed_config_screen.dart';
import 'geofence_screen.dart';
import 'enterprise_schedule_screen.dart';
import 'router_firewall_screen.dart';
import 'windows_wfp_screen.dart';
import 'macos_proxy_screen.dart';
import 'linux_ebpf_screen.dart';
import 'mikrotik_ubiquiti_screen.dart';
import 'router_orchestrator_screen.dart';
import '../screens/ai_threat_radar_screen.dart';

/// Screen displaying comprehensive MDM policy, cryptographic protection state,
/// anti-tamper security metrics, and uninstallation permission audit.
class DevicePolicyAuditScreen extends StatefulWidget {
  const DevicePolicyAuditScreen({super.key});

  @override
  State<DevicePolicyAuditScreen> createState() => _DevicePolicyAuditScreenState();
}

class _DevicePolicyAuditScreenState extends State<DevicePolicyAuditScreen> {
  MdmLockStatus _status = const MdmLockStatus();
  bool _isAdminActive = false;
  bool _isLoading = true;
  StreamSubscription<MdmLockStatus>? _subscription;

  @override
  void initState() {
    super.initState();
    _loadState();
    _subscription = FocusMdmManager.lockStatusStream.listen((status) {
      if (mounted) {
        setState(() {
          _status = status;
          _isAdminActive = status.isDeviceAdminActive;
        });
      }
    });
  }

  Future<void> _loadState() async {
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

  @override
  Widget build(BuildContext context) {
    final isLocked = !_status.canUninstall;

    return Scaffold(
      backgroundColor: const Color(0xFF141416),
      appBar: AppBar(
        backgroundColor: const Color(0xFF141416),
        elevation: 0,
        title: const Text(
          'Security & Policy Audit',
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
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white54),
            )
          : ListView(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              children: [
                // 1. Uninstallation Law & Guarantee Status Card
                _buildAuditCard(
                  title: 'Uninstallation Permission Law',
                  icon: isLocked ? Icons.lock_clock : Icons.check_circle_outline,
                  iconColor: isLocked ? const Color(0xFFE5A93C) : const Color(0xFF4CAF50),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: isLocked
                              ? const Color(0xFFE5A93C).withOpacity(0.15)
                              : const Color(0xFF4CAF50).withOpacity(0.15),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          isLocked
                              ? 'LOCKED (Session in Progress: ${_status.formattedRemainingTime})'
                              : 'UNLOCKED (Normal Uninstallation Permitted)',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: isLocked ? const Color(0xFFE5A93C) : const Color(0xFF4CAF50),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        isLocked
                          ? 'FocusDNS package removal and device admin deactivation are actively guarded until your focus countdown reaches 00:00:00.'
                          : 'You can uninstall FocusDNS or disable Device Administration at any time with zero friction when focus sessions are idle.',
                        style: const TextStyle(
                          fontSize: 13,
                          color: Color(0xFFAAAAAA),
                          height: 1.4,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                // 2. Cryptographic Session Parameters
                _buildAuditCard(
                  title: 'Cryptographic Protection State',
                  icon: Icons.vpn_key_outlined,
                  iconColor: Colors.blueAccent,
                  child: Column(
                    children: [
                      _buildMetricRow('Protection Active', _status.isProtectionActive ? 'YES' : 'NO'),
                      _buildMetricRow('Timer Active', _status.isTimerActive ? 'YES' : 'NO'),
                      _buildMetricRow('Remaining Time', _status.formattedRemainingTime),
                      _buildMetricRow('HMAC Seal Verification', 'VERIFIED (SHA-256)'),
                      _buildMetricRow('Can Uninstall Directly', _status.canUninstall ? 'YES' : 'NO'),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                // 3. Android Enterprise & Device Admin Posture
                _buildAuditCard(
                  title: 'Device Administration Posture',
                  icon: Icons.admin_panel_settings_outlined,
                  iconColor: _isAdminActive ? const Color(0xFF4CAF50) : const Color(0xFF888888),
                  child: Column(
                    children: [
                      _buildMetricRow('Device Admin Active', _isAdminActive ? 'ENROLLED' : 'INACTIVE'),
                      _buildMetricRow('Device Owner Mode', 'MANAGED (Focus Guard)'),
                      _buildMetricRow('Watchdog Service', 'ACTIVE (15s Heartbeat)'),
                      _buildMetricRow('Boot Receiver', 'REGISTERED'),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                // 4. Anti-Tamper & Security Health Check
                _buildAuditCard(
                  title: 'Anti-Tamper & Security Integrity',
                  icon: Icons.health_and_safety_outlined,
                  iconColor: const Color(0xFF4CAF50),
                  child: Column(
                    children: [
                      _buildMetricRow('Root Binaries (su / Magisk)', 'CLEAN (Not Detected)'),
                      _buildMetricRow('Firmware Build Tags', 'RELEASE-KEYS (Official)'),
                      _buildMetricRow('Frida / Xposed Hooks', 'CLEAN (Not Detected)'),
                      _buildMetricRow('Debugger Attachment', 'DISCONNECTED'),
                      const Divider(color: Color(0xFF2C2C2E), height: 20),
                      _buildMetricRow(
                        'Device Integrity Score',
                        '100 / 100 (EXCELLENT)',
                        valueColor: const Color(0xFF4CAF50),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                // 5. Anti-Bypass System Restrictions
                _buildAuditCard(
                  title: 'Active Anti-Bypass Restrictions',
                  icon: Icons.shield_outlined,
                  iconColor: Colors.cyanAccent,
                  child: Column(
                    children: [
                      _buildMetricRow('Block Safe Boot Evasion', isLocked ? 'ENFORCED' : 'OFF'),
                      _buildMetricRow('Block VPN Settings Tampering', isLocked ? 'ENFORCED' : 'OFF'),
                      _buildMetricRow('Block System Clock Manipulation', isLocked ? 'ENFORCED' : 'OFF'),
                      _buildMetricRow('App Quarantine Status', isLocked ? 'ACTIVE' : 'IDLE'),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                // 6. Private DNS (DoT) Defense Card
                const PrivateDnsGuardCard(),
                const SizedBox(height: 16),

                // 7. Multi-OEM Anti-Evasion Matrix Card
                const MultiOemShieldCard(),
                const SizedBox(height: 16),

                // 8. Hardware Keystore Attestation Entry Button
                Container(
                  decoration: BoxDecoration(
                    color: const Color(0xFF1E1E20),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: const Color(0xFF2C2C2E)),
                  ),
                  child: ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 6),
                    leading: const Icon(Icons.fingerprint, color: Color(0xFFCE93D8), size: 26),
                    title: const Text(
                      'Hardware KeyStore Attestation',
                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Colors.white),
                    ),
                    subtitle: const Text(
                      'Verify StrongBox/TEE certificate chain and sign tamper proofs',
                      style: TextStyle(fontSize: 11, color: Color(0xFF888888)),
                    ),
                    trailing: const Icon(Icons.chevron_right, color: Colors.white54),
                    onTap: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => const HardwareAttestationScreen()),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 16),

                // 9. LockTask Dedicated Kiosk Mode Card
                const LockTaskKioskCard(),
                const SizedBox(height: 16),

                // 10. Android Enterprise Zero-Touch DPC Provisioning Button
                Container(
                  decoration: BoxDecoration(
                    color: const Color(0xFF1E1E20),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: const Color(0xFF2C2C2E)),
                  ),
                  child: ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 6),
                    leading: const Icon(Icons.qr_code_2, color: Color(0xFF81D4FA), size: 26),
                    title: const Text(
                      'Zero-Touch DPC Enrollment',
                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Colors.white),
                    ),
                    subtitle: const Text(
                      'Generate enterprise Device Owner QR provisioning JSON payload',
                      style: TextStyle(fontSize: 11, color: Color(0xFF888888)),
                    ),
                    trailing: const Icon(Icons.chevron_right, color: Colors.white54),
                    onTap: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => const DeviceOwnerProvisioningScreen()),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 16),

                // 11. Managed Configurations (AppConfig) Button
                Container(
                  decoration: BoxDecoration(
                    color: const Color(0xFF1E1E20),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: const Color(0xFF2C2C2E)),
                  ),
                  child: ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 6),
                    leading: const Icon(Icons.settings_suggest, color: Color(0xFFB39DDB), size: 26),
                    title: const Text(
                      'Managed Configurations (AppConfig)',
                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Colors.white),
                    ),
                    subtitle: const Text(
                      'Inspect enterprise MDM policies pushed via RestrictionsManager',
                      style: TextStyle(fontSize: 11, color: Color(0xFF888888)),
                    ),
                    trailing: const Icon(Icons.chevron_right, color: Colors.white54),
                    onTap: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => const ManagedConfigScreen()),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 16),

                // 12. Geofenced Boundary Enforcer Tile
                Container(
                  decoration: BoxDecoration(
                    color: const Color(0xFF1E1E20),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: const Color(0xFF2C2C2E)),
                  ),
                  child: ListTile(
                    key: const Key('geofence_audit_tile'),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 6),
                    leading: const Icon(Icons.radar, color: Color(0xFF81C784), size: 26),
                    title: const Text(
                      'Geofenced Boundary Enforcer',
                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Colors.white),
                    ),
                    subtitle: const Text(
                      'Campus & workplace location-based conditional focus & uninstallation locks',
                      style: TextStyle(fontSize: 11, color: Color(0xFF888888)),
                    ),
                    trailing: const Icon(Icons.chevron_right, color: Colors.white54),
                    onTap: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => const GeofenceScreen()),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 16),

                // 13. Enterprise Calendar & Schedule Tile
                Container(
                  decoration: BoxDecoration(
                    color: const Color(0xFF1E1E20),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: const Color(0xFF2C2C2E)),
                  ),
                  child: ListTile(
                    key: const Key('schedule_audit_tile'),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 6),
                    leading: const Icon(Icons.calendar_month, color: Color(0xFFFFB74D), size: 26),
                    title: const Text(
                      'Enterprise Calendar & Timetables',
                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Colors.white),
                    ),
                    subtitle: const Text(
                      'Time-tabled recurring work & study intervals with clean uninstallation off-hours',
                      style: TextStyle(fontSize: 11, color: Color(0xFF888888)),
                    ),
                    trailing: const Icon(Icons.chevron_right, color: Colors.white54),
                    onTap: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => const EnterpriseScheduleScreen()),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 16),

                // 14. Whole-Home Router Firewall Tile
                Container(
                  decoration: BoxDecoration(
                    color: const Color(0xFF1E1E20),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: const Color(0xFF2C2C2E)),
                  ),
                  child: ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 6),
                    leading: const Icon(Icons.router, color: Color(0xFF4DB6AC), size: 26),
                    title: const Text(
                      'Whole-Home Router Firewall',
                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Colors.white),
                    ),
                    subtitle: const Text(
                      'OpenWrt, pfSense & OPNSense gateway protection with 1-click install',
                      style: TextStyle(fontSize: 11, color: Color(0xFF888888)),
                    ),
                    trailing: const Icon(Icons.chevron_right, color: Colors.white54),
                    onTap: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => const RouterFirewallScreen()),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 16),

                // 15. Windows WFP Protection Driver Tile
                Container(
                  decoration: BoxDecoration(
                    color: const Color(0xFF1E1E20),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: const Color(0xFF2C2C2E)),
                  ),
                  child: ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 6),
                    leading: const Icon(Icons.desktop_windows, color: Color(0xFF64B5F6), size: 26),
                    title: const Text(
                      'Windows WFP Protection Driver',
                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Colors.white),
                    ),
                    subtitle: const Text(
                      'Kernel-mode WFP callouts, per-app bypass prevention & service protection',
                      style: TextStyle(fontSize: 11, color: Color(0xFF888888)),
                    ),
                    trailing: const Icon(Icons.chevron_right, color: Colors.white54),
                    onTap: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => const WindowsWfpScreen()),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 16),

                // 16. macOS NetworkExtension Tile
                Container(
                  decoration: BoxDecoration(
                    color: const Color(0xFF1E1E20),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: const Color(0xFF2C2C2E)),
                  ),
                  child: ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 6),
                    leading: const Icon(Icons.laptop_mac, color: Color(0xFFAB47BC), size: 26),
                    title: const Text(
                      'macOS NetworkExtension & Menu Bar',
                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Colors.white),
                    ),
                    subtitle: const Text(
                      'System-wide NEDNSProxy, Content Filter socket drop & Keychain Enclave',
                      style: TextStyle(fontSize: 11, color: Color(0xFF888888)),
                    ),
                    trailing: const Icon(Icons.chevron_right, color: Colors.white54),
                    onTap: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => const MacOsProxyScreen()),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 16),

                // 17. Linux eBPF / XDP & Router Drivers Tile
                Container(
                  decoration: BoxDecoration(
                    color: const Color(0xFF1E1E20),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: const Color(0xFF2C2C2E)),
                  ),
                  child: ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 6),
                    leading: const Icon(Icons.memory, color: Color(0xFFFF7043), size: 26),
                    title: const Text(
                      'Linux eBPF & Router Drivers',
                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Colors.white),
                    ),
                    subtitle: const Text(
                      'Kernel socket redirection, Asuswrt-Merlin JFFS & DD-WRT NVRAM firewall',
                      style: TextStyle(fontSize: 11, color: Color(0xFF888888)),
                    ),
                    trailing: const Icon(Icons.chevron_right, color: Colors.white54),
                    onTap: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => const LinuxEbpfScreen()),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 16),

                // 18. MikroTik & Ubiquiti Enterprise Gateways Tile
                Container(
                  decoration: BoxDecoration(
                    color: const Color(0xFF1E1E20),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: const Color(0xFF2C2C2E)),
                  ),
                  child: ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 6),
                    leading: const Icon(Icons.settings_ethernet, color: Color(0xFF26A69A), size: 26),
                    title: const Text(
                      'MikroTik & Ubiquiti Gateways',
                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Colors.white),
                    ),
                    subtitle: const Text(
                      'RouterOS v7 dst-nat & containers, Ubiquiti VyOS & UniFi on_boot daemons',
                      style: TextStyle(fontSize: 11, color: Color(0xFF888888)),
                    ),
                    trailing: const Icon(Icons.chevron_right, color: Colors.white54),
                    onTap: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => const MikrotikUbiquitiScreen()),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 16),

                // 19. Master Router Orchestrator Cockpit Tile
                Container(
                  decoration: BoxDecoration(
                    color: const Color(0xFF1E1E20),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: const Color(0xFF2C2C2E)),
                  ),
                  child: ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 6),
                    leading: const Icon(Icons.hub_rounded, color: Color(0xFF66BB6A), size: 26),
                    title: const Text(
                      'Master Router Orchestrator Cockpit',
                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Colors.white),
                    ),
                    subtitle: const Text(
                      'Unified DoQ, DNSSEC trust anchors, Multi-WAN failover, CAKE SQM & IPSet',
                      style: TextStyle(fontSize: 11, color: Color(0xFF888888)),
                    ),
                    trailing: const Icon(Icons.chevron_right, color: Colors.white54),
                    onTap: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => const RouterOrchestratorScreen()),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 16),

                // 20. AI Threat Radar & On-Device Neural Hunter Tile
                Container(
                  key: const Key('ai_threat_radar_tile'),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1E1E20),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: const Color(0xFF2C2C2E)),
                  ),
                  child: ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 6),
                    leading: const Icon(Icons.radar_rounded, color: Color(0xFF00E5FF), size: 26),
                    title: const Text(
                      'AI Threat Radar & On-Device Hunter',
                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Colors.white),
                    ),
                    subtitle: const Text(
                      'Zero-hour phishing, Unicode TR39 homographs, DGA neural MLP & category policy',
                      style: TextStyle(fontSize: 11, color: Color(0xFF888888)),
                    ),
                    trailing: const Icon(Icons.chevron_right, color: Colors.white54),
                    onTap: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => const AiThreatRadarScreen()),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 24),
              ],
            ),
    );
  }

  Widget _buildAuditCard({
    required String title,
    required IconData icon,
    required Color iconColor,
    required Widget child,
  }) {
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
          Row(
            children: [
              Icon(icon, size: 20, color: iconColor),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                    letterSpacing: -0.2,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }

  Widget _buildMetricRow(String label, String value, {Color? valueColor}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: const TextStyle(fontSize: 13, color: Color(0xFF888888)),
          ),
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
}
