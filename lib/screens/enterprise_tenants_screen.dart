// FocusDNS Enterprise Tenants Screen - Multi-Tenant Hierarchy & Quota Management

import 'package:flutter/material.dart';
import '../models/enterprise_models.dart';
import '../services/enterprise_service.dart';

class EnterpriseTenantsScreen extends StatefulWidget {
  final String orgId;
  final EnterpriseService? service;

  const EnterpriseTenantsScreen({
    super.key,
    this.orgId = 'org_springfield',
    this.service,
  });

  @override
  State<EnterpriseTenantsScreen> createState() => _EnterpriseTenantsScreenState();
}

class _EnterpriseTenantsScreenState extends State<EnterpriseTenantsScreen> {
  late final EnterpriseService _service;
  bool _isLoading = true;
  OrganizationModel? _org;
  List<TenantUnitModel> _units = [];
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _service = widget.service ?? EnterpriseService();
    _loadTenantData();
  }

  Future<void> _loadTenantData() async {
    setState(() => _isLoading = true);
    try {
      final res = await _service.getOrganizationAndUnits(widget.orgId);
      if (mounted) {
        setState(() {
          _org = OrganizationModel.fromJson(Map<String, dynamic>.from(res['organization'] as Map));
          final rawUnits = res['units'] as List? ?? [];
          _units = rawUnits.map((u) => TenantUnitModel.fromJson(Map<String, dynamic>.from(u as Map))).toList();
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = e.toString();
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF141416),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1E1E20),
        elevation: 0,
        title: const Text(
          'Multi-Tenant Organization Hierarchy',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.white70),
            onPressed: _loadTenantData,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFF81C784)))
          : _errorMessage != null
              ? Center(child: Text(_errorMessage!, style: const TextStyle(color: Colors.redAccent)))
              : SingleChildScrollView(
                  padding: const EdgeInsets.all(18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (_org != null) _buildOrganizationCard(_org!),
                      const SizedBox(height: 18),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'Tenant Units (Schools / Departments)',
                            style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.white),
                          ),
                          Text(
                            '${_units.length} Active Units',
                            style: const TextStyle(fontSize: 12, color: Color(0xFF888888)),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      ..._units.map((u) => _buildUnitCard(u)),
                    ],
                  ),
                ),
    );
  }

  Widget _buildOrganizationCard(OrganizationModel org) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E20),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF2C2C2E)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0xFF81C784).withOpacity(0.15),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.corporate_fare, color: Color(0xFF81C784), size: 24),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      org.name,
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
                    ),
                    Text(
                      'Domain: ${org.domain} • Tier: ${org.planTier}',
                      style: const TextStyle(fontSize: 12, color: Color(0xFF888888)),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFF4CAF50).withOpacity(0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Text(
                  'HEALTHY',
                  style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Color(0xFF4CAF50)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          const Divider(color: Color(0xFF2C2C2E), height: 1),
          const SizedBox(height: 14),
          const Text('Tenant Resource Quota & Entitlements', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.white70)),
          const SizedBox(height: 10),
          Row(
            children: [
              _buildQuotaChip('Max Devices', '${org.quota.maxDevices}', Icons.devices),
              const SizedBox(width: 10),
              _buildQuotaChip('Rate Limit', '${org.quota.maxQps} QPS', Icons.speed),
              const SizedBox(width: 10),
              _buildQuotaChip('Log Retention', '${org.quota.retentionDays} Days', Icons.history),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildQuotaChip(String label, String value, IconData icon) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: const Color(0xFF141416),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: const Color(0xFF2C2C2E)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: const Color(0xFF888888), size: 12),
                const SizedBox(width: 4),
                Text(label, style: const TextStyle(fontSize: 10, color: Color(0xFF888888))),
              ],
            ),
            const SizedBox(height: 4),
            Text(value, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.white)),
          ],
        ),
      ),
    );
  }

  Widget _buildUnitCard(TenantUnitModel unit) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E20),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF2C2C2E)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  const Icon(Icons.school, color: Color(0xFF64B5F6), size: 18),
                  const SizedBox(width: 10),
                  Text(
                    unit.name,
                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.white),
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: const Color(0xFF64B5F6).withOpacity(0.15),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  unit.unitType,
                  style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Color(0xFF64B5F6)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Unit ID: ${unit.unitId}',
            style: const TextStyle(fontSize: 11, color: Color(0xFF888888)),
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton.icon(
                icon: const Icon(Icons.vpn_key_outlined, size: 14, color: Color(0xFFFFB74D)),
                label: const Text('Generate Enrollment Token', style: TextStyle(fontSize: 12, color: Color(0xFFFFB74D))),
                onPressed: () => _showEnrollmentDialog(unit),
              ),
              const SizedBox(width: 8),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF2C2C2E),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                ),
                icon: const Icon(Icons.settings, size: 14),
                label: const Text('Manage Fleets', style: TextStyle(fontSize: 12)),
                onPressed: () => _showManageFleetsDialog(unit),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _showEnrollmentDialog(TenantUnitModel unit) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E20),
        title: const Text('Device Enrollment Secret', style: TextStyle(color: Colors.white, fontSize: 16)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('One-time cryptographic enrollment token for ${unit.name}:', style: const TextStyle(fontSize: 12, color: Colors.white70)),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFF141416),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFF333336)),
              ),
              child: const SelectableText(
                'enr_sec_9a4f2b810d7e63c4',
                style: TextStyle(fontFamily: 'monospace', fontWeight: FontWeight.bold, color: Color(0xFF81C784)),
              ),
            ),
            const SizedBox(height: 8),
            const Text('Expires in 24 hours • Max uses: 50 devices', style: TextStyle(fontSize: 11, color: Color(0xFF888888))),
          ],
        ),
        actions: [
          TextButton(
            child: const Text('Close', style: TextStyle(color: Colors.white70)),
            onPressed: () => Navigator.of(ctx).pop(),
          ),
        ],
      ),
    );
  }

  void _showManageFleetsDialog(TenantUnitModel unit) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1E1E20),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (ctx) => Container(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Fleets in ${unit.name}', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white)),
            const SizedBox(height: 14),
            _buildFleetItem('Chromebook Cart 4B', 'CHROMEOS', 32, false),
            _buildFleetItem('Staff Laptops', 'MACOS', 14, false),
            const SizedBox(height: 16),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF64B5F6),
                foregroundColor: Colors.black,
                minimumSize: const Size.fromHeight(40),
              ),
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Create New Fleet'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFleetItem(String name, String platform, int count, bool isLocked) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Icon(platform == 'MACOS' ? Icons.laptop_mac : Icons.laptop_chromebook, color: const Color(0xFF888888), size: 18),
              const SizedBox(width: 8),
              Text(name, style: const TextStyle(fontSize: 13, color: Colors.white)),
            ],
          ),
          Text('$count Devices', style: const TextStyle(fontSize: 12, color: Color(0xFF888888))),
        ],
      ),
    );
  }
}
