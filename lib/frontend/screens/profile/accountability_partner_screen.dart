import 'package:flutter/material.dart';
import '../../../engine/profile/accountability_partner_manager.dart';

/// Screen managing accountability partner assignment, emergency unlock reviews,
/// and trust score history.
class AccountabilityPartnerScreen extends StatefulWidget {
  final AccountabilityPartnerManager manager;

  const AccountabilityPartnerScreen({
    super.key,
    required this.manager,
  });

  @override
  State<AccountabilityPartnerScreen> createState() => _AccountabilityPartnerScreenState();
}

class _AccountabilityPartnerScreenState extends State<AccountabilityPartnerScreen> {
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _phoneController = TextEditingController();
  bool _isEditingPartner = false;

  @override
  void initState() {
    super.initState();
    final p = widget.manager.partner;
    if (p != null) {
      _nameController.text = p.name;
      _emailController.text = p.email;
      _phoneController.text = p.phoneNumber ?? '';
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final partner = widget.manager.partner;
    final requests = widget.manager.requests;

    return Scaffold(
      backgroundColor: const Color(0xFF0E0E12),
      appBar: AppBar(
        backgroundColor: const Color(0xFF14141A),
        elevation: 0,
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Accountability Partner',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: Colors.white),
            ),
            Text(
              'Anti-Tamper Emergency Guardian',
              style: TextStyle(fontSize: 11, color: Colors.white54),
            ),
          ],
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // 1. Partner Status / Profile Card
          if (partner != null && !_isEditingPartner)
            _buildPartnerProfileCard(partner)
          else
            _buildPartnerEditCard(),
          const SizedBox(height: 20),

          // 2. Trust Score & Protocol Card
          _buildTrustScoreCard(partner?.trustScore ?? 100),
          const SizedBox(height: 20),

          // 3. Emergency Requests Log
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'EMERGENCY REQUESTS AUDIT',
                style: TextStyle(
                  color: Colors.white54,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.8,
                ),
              ),
              Text(
                '${requests.length} Requests',
                style: TextStyle(color: Colors.white.withOpacity(0.4), fontSize: 11),
              ),
            ],
          ),
          const SizedBox(height: 10),

          if (requests.isEmpty)
            _buildEmptyRequestsPlaceholder()
          else
            ...requests.map((req) => _buildRequestCard(req)),
        ],
      ),
    );
  }

  Widget _buildPartnerProfileCard(AccountabilityPartner partner) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFF16161E),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 24,
                backgroundColor: const Color(0xFF00E699).withOpacity(0.15),
                child: const Text('🛡️', style: TextStyle(fontSize: 22)),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      partner.name,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      partner.email,
                      style: TextStyle(color: Colors.white.withOpacity(0.6), fontSize: 12),
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.edit, size: 18, color: Colors.white54),
                onPressed: () => setState(() => _isEditingPartner = true),
              ),
            ],
          ),
          const SizedBox(height: 14),

          // Verification badge & Stats
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFF00E699).withOpacity(0.12),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFF00E699).withOpacity(0.3)),
                ),
                child: const Text(
                  '✓ Verified Guardian',
                  style: TextStyle(color: Color(0xFF00E699), fontSize: 11, fontWeight: FontWeight.w700),
                ),
              ),
              Text(
                '${partner.totalRequestsReviewed} Reviewed • ${partner.totalRequestsApproved} Approved',
                style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 11),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPartnerEditCard() {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFF16161E),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'ASSIGN ACCOUNTABILITY PARTNER',
            style: TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Your partner must approve any emergency request before a strict focus lock can be released.',
            style: TextStyle(color: Colors.white.withOpacity(0.55), fontSize: 11),
          ),
          const SizedBox(height: 14),

          TextField(
            controller: _nameController,
            style: const TextStyle(color: Colors.white, fontSize: 13),
            decoration: InputDecoration(
              labelText: 'Partner Full Name',
              labelStyle: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 12),
              filled: true,
              fillColor: const Color(0xFF101015),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
            ),
          ),
          const SizedBox(height: 10),

          TextField(
            controller: _emailController,
            keyboardType: TextInputType.emailAddress,
            style: const TextStyle(color: Colors.white, fontSize: 13),
            decoration: InputDecoration(
              labelText: 'Partner Email (For Web Vault Signing)',
              labelStyle: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 12),
              filled: true,
              fillColor: const Color(0xFF101015),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
            ),
          ),
          const SizedBox(height: 14),

          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              if (widget.manager.partner != null)
                TextButton(
                  onPressed: () => setState(() => _isEditingPartner = false),
                  child: const Text('Cancel', style: TextStyle(color: Colors.white54)),
                ),
              const SizedBox(width: 8),
              ElevatedButton(
                onPressed: _savePartner,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF00E699),
                  foregroundColor: Colors.black,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                child: const Text('Save Partner', style: TextStyle(fontWeight: FontWeight.w700)),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTrustScoreCard(int trustScore) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF16161C),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withOpacity(0.06)),
      ),
      child: Row(
        children: [
          Container(
            width: 50,
            height: 50,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: const Color(0xFF00E699).withOpacity(0.12),
              shape: BoxShape.circle,
            ),
            child: Text(
              '$trustScore',
              style: const TextStyle(
                color: Color(0xFF00E699),
                fontSize: 18,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Guardian Trust Rating',
                  style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 2),
                Text(
                  'High rating confirms active anti-relapse support and timely review of emergency requests.',
                  style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 11),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRequestCard(EmergencyUnlockRequestModel req) {
    Color statusColor;
    String statusText;

    switch (req.status) {
      case EmergencyRequestStatus.pending:
        statusColor = const Color(0xFFFF9F1C);
        statusText = 'PENDING APPROVAL';
        break;
      case EmergencyRequestStatus.approved:
        statusColor = const Color(0xFF00E699);
        statusText = 'APPROVED & UNLOCKED';
        break;
      case EmergencyRequestStatus.rejected:
        statusColor = const Color(0xFFFF3B5C);
        statusText = 'REJECTED';
        break;
      case EmergencyRequestStatus.expired:
        statusColor = Colors.white54;
        statusText = 'EXPIRED';
        break;
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF16161E),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withOpacity(0.06)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Device: ${req.deviceId}',
                style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: statusColor.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  statusText,
                  style: TextStyle(color: statusColor, fontSize: 9, fontWeight: FontWeight.w800),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            '"${req.reason}"',
            style: TextStyle(color: Colors.white.withOpacity(0.8), fontSize: 12, fontStyle: FontStyle.italic),
          ),
          const SizedBox(height: 8),
          Text(
            'Requested: ${req.requestedAt.toLocal().toString().split('.')[0]}',
            style: TextStyle(color: Colors.white.withOpacity(0.4), fontSize: 10),
          ),
          if (req.isPending) ...[
            const SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => _handleReject(req.requestId),
                  child: const Text('Reject', style: TextStyle(color: Color(0xFFFF3B5C), fontSize: 12)),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: () => _handleApprove(req.requestId),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF00E699),
                    foregroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  child: const Text('Approve Unlock 🔓', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildEmptyRequestsPlaceholder() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: const Color(0xFF16161C),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withOpacity(0.04)),
      ),
      child: Center(
        child: Text(
          'No emergency unblock requests submitted. Focus discipline is solid!',
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 12),
        ),
      ),
    );
  }

  void _savePartner() {
    final name = _nameController.text.trim();
    final email = _emailController.text.trim();
    if (name.isEmpty || email.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter partner name and email.')),
      );
      return;
    }

    widget.manager.assignPartner(name: name, email: email, phone: _phoneController.text.trim());
    setState(() => _isEditingPartner = false);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Accountability partner assigned successfully!')),
    );
  }

  void _handleApprove(String requestId) async {
    final success = await widget.manager.approveRequest(requestId, 'PIN_1234');
    if (success) {
      setState(() {});
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Emergency request approved. Lock released.')),
      );
    }
  }

  void _handleReject(String requestId) async {
    await widget.manager.rejectRequest(requestId);
    setState(() {});
  }
}
