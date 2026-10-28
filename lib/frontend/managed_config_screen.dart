import 'dart:async';
import 'package:flutter/material.dart';
import '../backend/dpc_service.dart';

/// Screen inspecting dynamic Android Enterprise Managed Configurations (AppConfig).
class ManagedConfigScreen extends StatefulWidget {
  const ManagedConfigScreen({super.key});

  @override
  State<ManagedConfigScreen> createState() => _ManagedConfigScreenState();
}

class _ManagedConfigScreenState extends State<ManagedConfigScreen> {
  ManagedConfigModel _config = const ManagedConfigModel();
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _loadConfig();
  }

  Future<void> _loadConfig() async {
    final cfg = await FocusDpcService.getManagedConfiguration();
    if (mounted) {
      setState(() {
        _config = cfg;
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasEnterpriseConfig = _config.enrollmentToken.isNotEmpty || _config.enforceStrictUninstallLock;

    return Scaffold(
      backgroundColor: const Color(0xFF141416),
      appBar: AppBar(
        backgroundColor: const Color(0xFF141416),
        elevation: 0,
        title: const Text(
          'Managed Configurations',
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
            tooltip: 'Reload AppConfig',
            icon: const Icon(Icons.refresh, color: Colors.white70),
            onPressed: _loadConfig,
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
                // 1. Enterprise EMM Status Banner
                _buildEmmBanner(hasEnterpriseConfig),
                const SizedBox(height: 16),

                // 2. Active AppConfig Key-Value Table
                _buildConfigParametersCard(),
                const SizedBox(height: 16),

                // 3. EMM Split-Tunnel Whitelist
                _buildWhitelistedAppsCard(),
                const SizedBox(height: 16),

                // 4. Policy Guarantee Notice
                _buildPolicyNoticeCard(),
                const SizedBox(height: 24),
              ],
            ),
    );
  }

  Widget _buildEmmBanner(bool isManaged) {
    final color = isManaged ? const Color(0xFF00E676) : const Color(0xFF90CAF9);
    return Container(
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          Icon(isManaged ? Icons.business : Icons.person_outline, color: color, size: 24),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isManaged ? 'Managed by Enterprise EMM' : 'Standalone Personal Device',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: color),
                ),
                const SizedBox(height: 2),
                Text(
                  isManaged
                      ? 'Configuration policies are dynamically pushed from central MDM console.'
                      : 'Running local configuration. Enterprise policies can be assigned via DPC.',
                  style: const TextStyle(fontSize: 12, color: Color(0xFFAAAAAA), height: 1.3),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildConfigParametersCard() {
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
              Icon(Icons.tune, size: 18, color: Color(0xFF81D4FA)),
              SizedBox(width: 8),
              Text(
                'Active AppConfig Schema',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: Colors.white),
              ),
            ],
          ),
          const SizedBox(height: 14),
          _buildParamRow('Server URL', _config.serverUrl),
          _buildParamRow('Tenant ID', _config.tenantId),
          _buildParamRow('Enrollment Token', _config.enrollmentToken.isEmpty ? '(Not Set)' : _config.enrollmentToken),
          _buildParamRow(
            'Strict Uninstall Lock',
            _config.enforceStrictUninstallLock ? 'ACTIVE' : 'OFF',
            valueColor: _config.enforceStrictUninstallLock ? const Color(0xFFFFB300) : const Color(0xFF4CAF50),
          ),
          _buildParamRow('Kiosk Mode Flag', _config.kioskEnabled ? 'ENABLED' : 'DISABLED'),
          _buildParamRow('Approved DoT Host', _config.approvedDotHost.isEmpty ? '(Opportunistic)' : _config.approvedDotHost),
        ],
      ),
    );
  }

  Widget _buildWhitelistedAppsCard() {
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
              Icon(Icons.call_split, size: 18, color: Color(0xFFCE93D8)),
              SizedBox(width: 8),
              Text(
                'EMM Bypass Tunnel Packages',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: Colors.white),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (_config.whitelistedPackages.isEmpty)
            const Text(
              'No external packages bypassed by EMM. All traffic routes through local DNS filtering.',
              style: TextStyle(fontSize: 12, color: Color(0xFF888888)),
            )
          else
            ..._config.whitelistedPackages.map((pkg) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: Row(
                    children: [
                      const Icon(Icons.check_circle, size: 12, color: Color(0xFF4CAF50)),
                      const SizedBox(width: 6),
                      Text(pkg, style: const TextStyle(fontSize: 12, color: Colors.white70)),
                    ],
                  ),
                )),
        ],
      ),
    );
  }

  Widget _buildPolicyNoticeCard() {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF19191C),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF27272B)),
      ),
      padding: const EdgeInsets.all(14),
      child: const Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline, size: 18, color: Color(0xFF90A4AE)),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              'Managed Configurations are read dynamically via Android RestrictionsManager. '
              'Emergency dialing (911/112) is fundamentally exempt from any administrative lock.',
              style: TextStyle(fontSize: 12, color: Color(0xFFB0BEC5), height: 1.4),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildParamRow(String label, String value, {Color? valueColor}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(fontSize: 12, color: Color(0xFF888888))),
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
