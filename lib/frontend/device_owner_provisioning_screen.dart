import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../backend/dpc_service.dart';
import 'dpc_qr_code_widget.dart';

/// Screen displaying Android Enterprise Device Owner (DPC) status,
/// Zero-Touch enrollment JSON payload, and conditional OS restriction management.
class DeviceOwnerProvisioningScreen extends StatefulWidget {
  const DeviceOwnerProvisioningScreen({super.key});

  @override
  State<DeviceOwnerProvisioningScreen> createState() => _DeviceOwnerProvisioningScreenState();
}

class _DeviceOwnerProvisioningScreenState extends State<DeviceOwnerProvisioningScreen> {
  DpcDiagnosticModel _diagnostics = const DpcDiagnosticModel();
  ManagedConfigModel _config = const ManagedConfigModel();
  bool _isLoading = false;
  String _statusMessage = 'DPC profile loaded.';

  @override
  void initState() {
    super.initState();
    _loadState();
  }

  Future<void> _loadState() async {
    final diag = await FocusDpcService.getDpcDiagnostics();
    final cfg = await FocusDpcService.getManagedConfiguration();
    if (mounted) {
      setState(() {
        _diagnostics = diag;
        _config = cfg;
        _isLoading = false;
      });
    }
  }

  Map<String, dynamic> _buildProvisioningBundle() {
    return {
      'android.app.extra.PROVISIONING_DEVICE_ADMIN_PACKAGE_NAME': 'com.focusdns.app',
      'android.app.extra.PROVISIONING_DEVICE_ADMIN_COMPONENT_NAME': 'com.focusdns.app/.FocusDeviceAdminReceiver',
      'android.app.extra.PROVISIONING_DEVICE_ADMIN_SIGNATURE_CHECKSUM': '4a24cd80388b818606eb02eb55b650c4035787207dd6551724d2968a07a9e163',
      'android.app.extra.PROVISIONING_ADMIN_EXTRAS_BUNDLE': {
        'server_url': _config.serverUrl,
        'tenant_id': _config.tenantId,
        'enforce_strict_uninstall_lock': _config.enforceStrictUninstallLock,
      },
      'android.app.extra.PROVISIONING_LEAVE_ALL_SYSTEM_APPS_ENABLED': true,
      'android.app.extra.PROVISIONING_SKIP_ENCRYPTION': false,
    };
  }

  void _copyProvisioningJson() {
    final jsonStr = const JsonEncoder.withIndent('  ').convert(_buildProvisioningBundle());
    Clipboard.setData(ClipboardData(text: jsonStr));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Android Enterprise Zero-Touch JSON copied to clipboard.'),
        backgroundColor: Color(0xFF2E7D32),
      ),
    );
  }

  Future<void> _testConditionalPolicy() async {
    setState(() => _statusMessage = 'Toggling conditional OS restrictions...');
    final result = await FocusDpcService.applyConditionalFocusPolicy(true);
    if (mounted) {
      setState(() {
        _statusMessage = 'Active focus restrictions applied: ${result.keys.length} policies.';
      });
      _loadState();
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDeviceOwner = _diagnostics.isDeviceOwner;
    final isProfileOwner = _diagnostics.isProfileOwner;

    Color badgeColor;
    String statusTitle;
    String statusSubtitle;

    if (isDeviceOwner) {
      badgeColor = const Color(0xFF00E676);
      statusTitle = 'DEVICE OWNER (FULL DPC)';
      statusSubtitle = 'Maximum OS protection: Kernel-level Force Stop, Clear Data, and uninstall locks.';
    } else if (isProfileOwner) {
      badgeColor = const Color(0xFF00B0FF);
      statusTitle = 'PROFILE OWNER (WORK PROFILE)';
      statusSubtitle = 'Work profile sandboxing active. Restrictions apply to managed workspace.';
    } else {
      badgeColor = const Color(0xFFFFB300);
      statusTitle = 'DEVICE ADMINISTRATOR (LEGACY)';
      statusSubtitle = 'Active via standard Device Administration API. Zero-Touch DPC available for full lock.';
    }

    return Scaffold(
      backgroundColor: const Color(0xFF141416),
      appBar: AppBar(
        backgroundColor: const Color(0xFF141416),
        elevation: 0,
        title: const Text(
          'Enterprise DPC Provisioning',
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
            tooltip: 'Refresh Status',
            icon: const Icon(Icons.refresh, color: Colors.white70),
            onPressed: _loadState,
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
                // 1. DPC Status Banner
                _buildStatusBanner(badgeColor, statusTitle, statusSubtitle),
                const SizedBox(height: 16),

                // 2. Uninstallation Law & Guarantee Notice
                _buildGuaranteeCard(),
                const SizedBox(height: 16),

                // 3. Android Enterprise Zero-Touch QR Payload Card
                _buildProvisioningPayloadCard(),
                const SizedBox(height: 16),

                // 4. Active OS Restrictions Matrix
                _buildRestrictionsMatrixCard(),
                const SizedBox(height: 24),
              ],
            ),
    );
  }

  Widget _buildStatusBanner(Color badgeColor, String title, String subtitle) {
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
            child: Icon(Icons.corporate_fare, color: badgeColor, size: 24),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: badgeColor,
                    letterSpacing: -0.2,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: const TextStyle(fontSize: 12, color: Color(0xFFAAAAAA), height: 1.3),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGuaranteeCard() {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E20),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF2C2C2E)),
      ),
      padding: const EdgeInsets.all(18),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.verified_user_outlined, size: 18, color: Color(0xFF81D4FA)),
              SizedBox(width: 8),
              Text(
                'Inviolable Uninstallation Law',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: Colors.white),
              ),
            ],
          ),
          SizedBox(height: 10),
          Text(
            '• Normal Mode (Protection OFF & Timer 0): Uninstallation is 100% permitted. All DPC user restrictions are cleared with zero friction.\n'
            '• Active Focus Mode: DISALLOW_UNINSTALL_APPS and DISALLOW_APPS_CONTROL are enforced until timer completion.\n'
            '• Emergency SOS Exemption: Dialing 911/112 is NEVER blocked, delayed, or sandboxed under any condition.',
            style: TextStyle(fontSize: 12, color: Color(0xFFCCCCCC), height: 1.45),
          ),
        ],
      ),
    );
  }

  Widget _buildProvisioningPayloadCard() {
    final jsonStr = const JsonEncoder.withIndent('  ').convert(_buildProvisioningBundle());

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
              Icon(Icons.qr_code_2, size: 18, color: Color(0xFFCE93D8)),
              SizedBox(width: 8),
              Text(
                'Zero-Touch Provisioning Bundle',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: Colors.white),
              ),
            ],
          ),
          const SizedBox(height: 8),
          const Text(
            'Scan or deploy via Android Enterprise Zero-Touch / QR Code setup during device initialization.',
            style: TextStyle(fontSize: 12, color: Color(0xFFAAAAAA), height: 1.3),
          ),
          const SizedBox(height: 16),
          DpcQrCodeWidget(
            payload: _buildProvisioningBundle(),
            size: 220.0,
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFF141416),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFF333336)),
            ),
            child: SelectableText(
              jsonStr,
              style: const TextStyle(fontSize: 11, fontFamily: 'monospace', color: Color(0xFFCCCCCC)),
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF2A2A2E),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  icon: const Icon(Icons.copy, size: 16),
                  label: const Text('Copy JSON', style: TextStyle(fontSize: 12)),
                  onPressed: _copyProvisioningJson,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white,
                    side: const BorderSide(color: Color(0xFF3E3E42)),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  icon: const Icon(Icons.play_arrow, size: 16),
                  label: const Text('Test Policy', style: TextStyle(fontSize: 12)),
                  onPressed: _testConditionalPolicy,
                ),
              ),
            ],
          ),
          if (_statusMessage.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              _statusMessage,
              style: const TextStyle(fontSize: 11, fontStyle: FontStyle.italic, color: Color(0xFF888888)),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildRestrictionsMatrixCard() {
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
              Icon(Icons.shield, size: 18, color: Color(0xFF90CAF9)),
              SizedBox(width: 8),
              Text(
                'OS User Restrictions Matrix',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: Colors.white),
              ),
            ],
          ),
          const SizedBox(height: 14),
          _buildRestrictionRow('Block Uninstallation', 'no_uninstall_apps'),
          _buildRestrictionRow('Block Task Manager Force Stop', 'no_control_apps'),
          _buildRestrictionRow('Block Safe Boot Evasion', 'no_safe_boot'),
          _buildRestrictionRow('Block VPN Configuration Override', 'no_config_vpn'),
          _buildRestrictionRow('Block USB Debugging (ADB)', 'no_debugging_features'),
          _buildRestrictionRow('Block Factory Reset Evasion', 'no_factory_reset'),
        ],
      ),
    );
  }

  Widget _buildRestrictionRow(String label, String key) {
    final isEnforced = _diagnostics.activeRestrictions[key] == true;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(fontSize: 12, color: Color(0xFF888888))),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: isEnforced ? const Color(0xFF2E7D32).withOpacity(0.2) : const Color(0xFF333336),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              isEnforced ? 'ENFORCED' : 'CLEARED',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.bold,
                color: isEnforced ? const Color(0xFF4CAF50) : const Color(0xFF777777),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
