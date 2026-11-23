// FocusDNS Enterprise RBAC Screen - User Directory & Tamper-Evident Audit Ledger

import 'package:flutter/material.dart';
import '../models/enterprise_models.dart';
import '../services/enterprise_service.dart';

class EnterpriseRbacScreen extends StatefulWidget {
  final EnterpriseService? service;

  const EnterpriseRbacScreen({super.key, this.service});

  @override
  State<EnterpriseRbacScreen> createState() => _EnterpriseRbacScreenState();
}

class _EnterpriseRbacScreenState extends State<EnterpriseRbacScreen> {
  late final EnterpriseService _service;
  bool _isLoading = true;
  List<RbacUserModel> _users = [];
  List<AuditEntryModel> _auditTrail = [];
  bool _isChainValid = true;
  String _chainStatusText = 'UNBROKEN_CRYPTOGRAPHIC_CHAIN';

  @override
  void initState() {
    super.initState();
    _service = widget.service ?? EnterpriseService();
    _loadRbacData();
  }

  Future<void> _loadRbacData() async {
    setState(() => _isLoading = true);
    try {
      final trail = await _service.fetchAuditTrail();
      final verifyRes = await _service.verifyAuditChain();

      final mockUsers = [
        RbacUserModel(
          userId: 'usr_super_admin',
          username: 'superadmin',
          email: 'admin@focusdns.internal',
          role: RoleTier.superAdmin,
          tenantId: 'global',
          subTenantIds: [],
          isActive: true,
          createdAt: DateTime.now().millisecondsSinceEpoch / 1000.0 - 86400 * 30,
        ),
        RbacUserModel(
          userId: 'usr_org_admin',
          username: 'district_superintendent',
          email: 'superintendent@springfield.k12.us',
          role: RoleTier.orgAdmin,
          tenantId: 'org_springfield',
          subTenantIds: [],
          isActive: true,
          createdAt: DateTime.now().millisecondsSinceEpoch / 1000.0 - 86400 * 14,
        ),
        RbacUserModel(
          userId: 'usr_auditor',
          username: 'auditor_maria',
          email: 'maria@regulatory.gov',
          role: RoleTier.complianceAuditor,
          tenantId: 'org_springfield',
          subTenantIds: [],
          isActive: true,
          createdAt: DateTime.now().millisecondsSinceEpoch / 1000.0 - 86400 * 5,
        ),
      ];

      if (mounted) {
        setState(() {
          _users = mockUsers;
          _auditTrail = trail;
          _isChainValid = verifyRes['chain_valid'] as bool? ?? true;
          _chainStatusText = verifyRes['status'] as String? ?? 'UNBROKEN_CRYPTOGRAPHIC_CHAIN';
          _isLoading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Color _roleColor(RoleTier role) {
    switch (role) {
      case RoleTier.superAdmin:
        return const Color(0xFFBA68C8);
      case RoleTier.orgAdmin:
        return const Color(0xFF64B5F6);
      case RoleTier.teamLead:
        return const Color(0xFF4DD0E1);
      case RoleTier.teacherParent:
        return const Color(0xFFFFB74D);
      case RoleTier.complianceAuditor:
        return const Color(0xFFFFD54F);
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
          'RBAC & Cryptographic Audit Ledger',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.white70),
            onPressed: _loadRbacData,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFFBA68C8)))
          : SingleChildScrollView(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildChainVerificationBanner(),
                  const SizedBox(height: 16),
                  _buildUsersDirectoryCard(),
                  const SizedBox(height: 18),
                  _buildAuditLedgerCard(),
                ],
              ),
            ),
    );
  }

  Widget _buildChainVerificationBanner() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _isChainValid ? const Color(0xFF4CAF50).withOpacity(0.12) : const Color(0xFFEF5350).withOpacity(0.15),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _isChainValid ? const Color(0xFF4CAF50) : const Color(0xFFEF5350)),
      ),
      child: Row(
        children: [
          Icon(
            _isChainValid ? Icons.verified : Icons.warning_amber_rounded,
            color: _isChainValid ? const Color(0xFF4CAF50) : const Color(0xFFEF5350),
            size: 24,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _isChainValid ? 'Cryptographic SHA-256 Audit Chain: VALID' : 'TAMPERING DETECTED IN AUDIT LEDGER',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: _isChainValid ? const Color(0xFF4CAF50) : const Color(0xFFEF5350),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Genesis-to-head hash continuity: $_chainStatusText',
                  style: const TextStyle(fontSize: 11, color: Color(0xFF888888)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildUsersDirectoryCard() {
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
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Enterprise User Directory', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.white)),
              Text('${_users.length} Active Staff', style: const TextStyle(fontSize: 12, color: Color(0xFF888888))),
            ],
          ),
          const SizedBox(height: 14),
          ..._users.map((u) {
            final color = _roleColor(u.role);
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 14,
                    backgroundColor: color.withOpacity(0.2),
                    child: Text(
                      u.username.substring(0, 1).toUpperCase(),
                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: color),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(u.username, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.white)),
                        Text(u.email, style: const TextStyle(fontSize: 11, color: Color(0xFF888888))),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(color: color.withOpacity(0.15), borderRadius: BorderRadius.circular(6)),
                    child: Text(
                      u.role.label,
                      style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: color),
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildAuditLedgerCard() {
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
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Immutable Audit Ledger', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.white)),
              const Text('SHA-256 Chained', style: TextStyle(fontSize: 11, color: Color(0xFF81C784))),
            ],
          ),
          const SizedBox(height: 14),
          ..._auditTrail.map((entry) {
            final isBlocked = entry.status.contains('BLOCKED') || entry.status.contains('FAIL');
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFF141416),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFF2C2C2E)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          entry.action,
                          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.white),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: isBlocked ? const Color(0xFFEF5350).withOpacity(0.15) : const Color(0xFF4CAF50).withOpacity(0.15),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            entry.status,
                            style: TextStyle(
                              fontSize: 9,
                              fontWeight: FontWeight.bold,
                              color: isBlocked ? const Color(0xFFEF5350) : const Color(0xFF4CAF50),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text('Actor: ${entry.actorUserId} (${entry.actorRole}) • Resource: ${entry.resource}',
                        style: const TextStyle(fontSize: 11, color: Color(0xFF888888))),
                    const SizedBox(height: 4),
                    Text('Hash: ${entry.entryHash.substring(0, 16)}...',
                        style: const TextStyle(fontSize: 10, fontFamily: 'monospace', color: Color(0xFF666666))),
                  ],
                ),
              ),
            );
          }),
        ],
      ),
    );
  }
}
