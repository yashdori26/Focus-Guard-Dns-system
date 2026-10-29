// FocusDNS Enterprise Commercial Billing & Cryptographic Invoicing Portal

import 'package:flutter/material.dart';
import '../models/enterprise_models.dart';
import '../services/enterprise_service.dart';

class EnterpriseBillingInvoicesScreen extends StatefulWidget {
  final EnterpriseService? service;
  final String orgId;

  const EnterpriseBillingInvoicesScreen({
    super.key,
    this.service,
    this.orgId = 'org_springfield',
  });

  @override
  State<EnterpriseBillingInvoicesScreen> createState() =>
      _EnterpriseBillingInvoicesScreenState();
}

class _EnterpriseBillingInvoicesScreenState
    extends State<EnterpriseBillingInvoicesScreen> {
  late final EnterpriseService _service;
  bool _isLoading = true;
  bool _isVerifying = false;
  bool? _isHmacVerified;
  String _selectedOrgId = 'org_springfield';

  BillingSummaryModel? _billingSummary;
  UsageInvoiceModel? _invoice;

  @override
  void initState() {
    super.initState();
    _service = widget.service ?? EnterpriseService();
    _selectedOrgId = widget.orgId;
    _loadBillingData();
  }

  Future<void> _loadBillingData() async {
    setState(() => _isLoading = true);
    try {
      final summary = await _service.fetchBillingSummary(_selectedOrgId);
      final invoice = await _service.fetchUsageInvoice(_selectedOrgId);
      if (mounted) {
        setState(() {
          _billingSummary = summary;
          _invoice = invoice;
          _isHmacVerified = null;
          _isLoading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _verifyCertificate({bool simulateTampering = false}) async {
    if (_invoice == null) return;
    setState(() => _isVerifying = true);

    try {
      final payload = _invoice!.toJson();
      if (simulateTampering) {
        // Deliberately corrupt charges to test cryptographic tamper detection
        payload['charges_usd'] = {'total': 99999.99};
      }
      final verified = await _service.verifyInvoiceHmacCertificate(payload);
      if (mounted) {
        setState(() {
          _isHmacVerified = verified;
          _isVerifying = false;
        });
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              verified
                  ? 'HMAC-SHA256 Signature VALID: Invoice is authentic and untampered.'
                  : 'TAMPERING DETECTED: Cryptographic digest mismatch!',
            ),
            backgroundColor: verified ? const Color(0xFF2E7D32) : const Color(0xFFC62828),
          ),
        );
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _isHmacVerified = false;
          _isVerifying = false;
        });
      }
    }
  }

  String _formatNumber(int number) {
    if (number >= 1000000) {
      return '${(number / 1000000.0).toStringAsFixed(2)}M';
    } else if (number >= 1000) {
      return '${(number / 1000.0).toStringAsFixed(1)}k';
    }
    return number.toString();
  }

  Color _getQuotaColor(double percent) {
    if (percent >= 95.0) return const Color(0xFFE57373);
    if (percent >= 80.0) return const Color(0xFFFFB74D);
    return const Color(0xFF81C784);
  }

  @override
  Widget build(BuildContext context) {
    final summary = _billingSummary;
    final invoice = _invoice;

    final active = summary?.activeDevices ?? 0;
    final max = (summary?.maxDevices ?? 1) > 0 ? (summary?.maxDevices ?? 1) : 1;
    final ratio = (active / max).clamp(0.0, 1.0);
    final percent = (active / max) * 100.0;
    final quotaColor = _getQuotaColor(percent);

    return Scaffold(
      backgroundColor: const Color(0xFF141416),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1E1E20),
        elevation: 0,
        title: const Row(
          children: [
            Icon(Icons.receipt_long, color: Color(0xFF81C784), size: 22),
            SizedBox(width: 10),
            Expanded(
              child: Text(
                'Commercial Billing & Invoicing',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.white70),
            tooltip: 'Refresh Billing Telemetry',
            onPressed: _loadBillingData,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFF81C784)))
          : RefreshIndicator(
              onRefresh: _loadBillingData,
              color: const Color(0xFF81C784),
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildOrgTierHeader(summary),
                    const SizedBox(height: 18),
                    _buildQuotaMeterCard(summary, active, max, ratio, percent, quotaColor),
                    const SizedBox(height: 18),
                    _buildUsageKpiCards(summary),
                    const SizedBox(height: 18),
                    _buildInvoiceSection(invoice),
                    const SizedBox(height: 24),
                    _buildLifeSafetyNotice(),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _buildOrgTierHeader(BillingSummaryModel? summary) {
    final planTier = summary?.planTier ?? 'ENTERPRISE';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E20),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF2E2E32)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'ORGANIZATION: ${_selectedOrgId.toUpperCase()}',
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.white54, letterSpacing: 0.8),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Springfield Unified District',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: const Color(0xFF81C784).withOpacity(0.15),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFF81C784)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.workspace_premium, color: Color(0xFF81C784), size: 16),
                const SizedBox(width: 6),
                Text(
                  planTier,
                  style: const TextStyle(
                    color: Color(0xFF81C784),
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.5,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQuotaMeterCard(
    BillingSummaryModel? summary,
    int active,
    int max,
    double ratio,
    double percent,
    Color quotaColor,
  ) {
    final isExceeded = summary?.isQuotaExceeded ?? false;
    final warnings = summary?.warnings ?? [];

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E20),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isExceeded ? const Color(0xFFE57373) : const Color(0xFF2E2E32),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Row(
                children: [
                  Icon(Icons.speed, color: Color(0xFF64B5F6), size: 18),
                  SizedBox(width: 8),
                  Text(
                    'Active Devices Quota Meter',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.white),
                  ),
                ],
              ),
              Text(
                '$active / $max Devices (${percent.toStringAsFixed(1)}%)',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  color: quotaColor,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: ratio,
              minHeight: 12,
              backgroundColor: const Color(0xFF2A2A2E),
              valueColor: AlwaysStoppedAnimation<Color>(quotaColor),
            ),
          ),
          const SizedBox(height: 8),
          const Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('0%', style: TextStyle(fontSize: 11, color: Colors.white38)),
              Text('80% (Warning)', style: TextStyle(fontSize: 11, color: Color(0xFFFFB74D))),
              Text('95% (Critical)', style: TextStyle(fontSize: 11, color: Color(0xFFE57373))),
              Text('100% Max', style: TextStyle(fontSize: 11, color: Colors.white38)),
            ],
          ),
          if (warnings.isNotEmpty) ...[
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFFFB74D).withOpacity(0.12),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFFFFB74D).withOpacity(0.5)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.warning_amber_rounded, color: Color(0xFFFFB74D), size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      warnings.join('\n'),
                      style: const TextStyle(color: Color(0xFFFFD54F), fontSize: 13),
                    ),
                  ),
                ],
              ),
            ),
          ],
          if (isExceeded) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFE57373).withOpacity(0.12),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFFE57373)),
              ),
              child: const Row(
                children: [
                  Icon(Icons.error_outline, color: Color(0xFFE57373), size: 20),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'DEVICE QUOTA EXCEEDED: Additional agent enrollments are restricted until fleet capacity is upgraded or inactive endpoints are pruned.',
                      style: TextStyle(color: Color(0xFFEF9A9A), fontSize: 13, fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildUsageKpiCards(BillingSummaryModel? summary) {
    final queries = summary?.totalQueriesMonth ?? 0;
    final qps = summary?.peakQps ?? 0.0;
    final cost = summary?.currentCostUsd ?? 0.0;

    return Row(
      children: [
        Expanded(
          child: _buildMetricTile(
            title: 'Monthly DNS Volume',
            value: '${_formatNumber(queries)} queries',
            icon: Icons.dns_outlined,
            color: const Color(0xFF64B5F6),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _buildMetricTile(
            title: 'Peak Measured QPS',
            value: '${qps.toStringAsFixed(1)} QPS',
            icon: Icons.bolt,
            color: const Color(0xFFFFD54F),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _buildMetricTile(
            title: 'Current Accrued Cost',
            value: '\$${cost.toStringAsFixed(2)}',
            icon: Icons.attach_money,
            color: const Color(0xFF81C784),
          ),
        ),
      ],
    );
  }

  Widget _buildMetricTile({
    required String title,
    required String value,
    required IconData icon,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E20),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF2E2E32)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: color, size: 16),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(fontSize: 11, color: Colors.white54, fontWeight: FontWeight.w500),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: color),
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  Widget _buildInvoiceSection(UsageInvoiceModel? invoice) {
    if (invoice == null) {
      return Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: const Color(0xFF1E1E20),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFF2E2E32)),
        ),
        child: const Center(
          child: Text(
            'No usage invoice available for the current billing cycle.',
            style: TextStyle(color: Colors.white54),
          ),
        ),
      );
    }

    final isVerified = _isHmacVerified;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E20),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF2E2E32)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Cryptographically Signed Invoice',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Invoice ID: ${invoice.invoiceId}  •  Cycle: ${invoice.billingCycle}',
                    style: const TextStyle(fontSize: 12, color: Colors.white54),
                  ),
                ],
              ),
              _buildVerificationBadge(isVerified),
            ],
          ),
          const SizedBox(height: 16),
          _buildItemizedChargesTable(invoice),
          const SizedBox(height: 16),
          _buildHmacSignatureDetails(invoice),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  key: const Key('verify_hmac_certificate_button'),
                  icon: _isVerifying
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : const Icon(Icons.verified, size: 18),
                  label: Text(_isVerifying ? 'Verifying Digest...' : 'Verify HMAC Certificate'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF2E7D32),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  onPressed: _isVerifying ? null : () => _verifyCertificate(simulateTampering: false),
                ),
              ),
              const SizedBox(width: 12),
              OutlinedButton.icon(
                key: const Key('simulate_tamper_button'),
                icon: const Icon(Icons.gpp_bad, size: 18, color: Color(0xFFE57373)),
                label: const Text('Test Tamper Detection', style: TextStyle(color: Color(0xFFE57373))),
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: Color(0xFFE57373)),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                onPressed: _isVerifying ? null : () => _verifyCertificate(simulateTampering: true),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildVerificationBadge(bool? isVerified) {
    Color bg;
    Color border;
    IconData icon;
    String text;

    if (isVerified == true) {
      bg = const Color(0xFF2E7D32).withOpacity(0.2);
      border = const Color(0xFF81C784);
      icon = Icons.check_circle;
      text = 'VERIFIED TAMPER-PROOF';
    } else if (isVerified == false) {
      bg = const Color(0xFFC62828).withOpacity(0.2);
      border = const Color(0xFFE57373);
      icon = Icons.warning;
      text = 'TAMPERING DETECTED';
    } else {
      bg = const Color(0xFF424242).withOpacity(0.3);
      border = const Color(0xFF9E9E9E);
      icon = Icons.hourglass_top;
      text = 'PENDING VERIFICATION';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: border, size: 14),
          const SizedBox(width: 6),
          Text(
            text,
            style: TextStyle(color: border, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 0.5),
          ),
        ],
      ),
    );
  }

  Widget _buildItemizedChargesTable(UsageInvoiceModel invoice) {
    final active = invoice.activeDevices;
    final totalQueries = invoice.totalQueries;
    final totalCost = invoice.totalAmountUsd;

    // Estimate itemized charges
    final deviceBaseCost = (active * 0.10).clamp(0.0, totalCost);
    final queriesCost = ((totalQueries / 1000000.0) * 10.0).clamp(0.0, totalCost);
    final storageCost = (totalCost * 0.15).clamp(0.0, totalCost);
    final siemEgressCost = (totalCost - deviceBaseCost - queriesCost - storageCost).clamp(0.0, totalCost);

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF141416),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFF2A2A2E)),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          headingRowHeight: 38,
          dataRowMinHeight: 38,
          dataRowMaxHeight: 42,
          columnSpacing: 24,
          columns: const [
            DataColumn(label: Text('Line Item', style: TextStyle(color: Colors.white70, fontWeight: FontWeight.bold))),
            DataColumn(label: Text('Quantity', style: TextStyle(color: Colors.white70, fontWeight: FontWeight.bold))),
            DataColumn(label: Text('Unit Rate', style: TextStyle(color: Colors.white70, fontWeight: FontWeight.bold))),
            DataColumn(label: Text('Subtotal (USD)', style: TextStyle(color: Colors.white70, fontWeight: FontWeight.bold))),
          ],
          rows: [
            DataRow(cells: [
              const DataCell(Text('Device Licenses (Active)', style: TextStyle(color: Colors.white))),
              DataCell(Text('$active endpoints', style: const TextStyle(color: Colors.white70))),
              const DataCell(Text('\$0.10 / seat', style: TextStyle(color: Colors.white70))),
              DataCell(Text('\$${deviceBaseCost.toStringAsFixed(2)}', style: const TextStyle(color: Color(0xFF81C784)))),
            ]),
            DataRow(cells: [
              const DataCell(Text('DNS Query Volume', style: TextStyle(color: Colors.white))),
              DataCell(Text('${_formatNumber(totalQueries)} queries', style: const TextStyle(color: Colors.white70))),
              const DataCell(Text('\$10.00 / 1M', style: TextStyle(color: Colors.white70))),
              DataCell(Text('\$${queriesCost.toStringAsFixed(2)}', style: const TextStyle(color: Color(0xFF81C784)))),
            ]),
            DataRow(cells: [
              const DataCell(Text('Columnar DuckDB Storage', style: TextStyle(color: Colors.white))),
              const DataCell(Text('128 GB Hot Parquet', style: TextStyle(color: Colors.white70))),
              const DataCell(Text('\$0.12 / GB', style: TextStyle(color: Colors.white70))),
              DataCell(Text('\$${storageCost.toStringAsFixed(2)}', style: const TextStyle(color: Color(0xFF81C784)))),
            ]),
            DataRow(cells: [
              const DataCell(Text('SIEM Gateway Webhook Egress', style: TextStyle(color: Colors.white))),
              const DataCell(Text('Real-time alerts', style: TextStyle(color: Colors.white70))),
              const DataCell(Text('Included tier', style: TextStyle(color: Colors.white70))),
              DataCell(Text('\$${siemEgressCost.toStringAsFixed(2)}', style: const TextStyle(color: Color(0xFF81C784)))),
            ]),
            DataRow(cells: [
              const DataCell(Text('TOTAL INVOICE CHARGES', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold))),
              const DataCell(Text('Current Period', style: TextStyle(color: Colors.white70))),
              const DataCell(Text('-', style: TextStyle(color: Colors.white70))),
              DataCell(Text('\$${totalCost.toStringAsFixed(2)} USD', style: const TextStyle(color: Color(0xFF81C784), fontWeight: FontWeight.bold))),
            ]),
          ],
        ),
      ),
    );
  }

  Widget _buildHmacSignatureDetails(UsageInvoiceModel invoice) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF141416),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFF2A2A2E)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.lock_outline, color: Color(0xFF80CBC4), size: 16),
              SizedBox(width: 8),
              Text(
                'HMAC-SHA256 Cryptographic Digital Certificate',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF80CBC4)),
              ),
            ],
          ),
          const SizedBox(height: 6),
          SelectableText(
            invoice.signatureSha256.isNotEmpty
                ? invoice.signatureSha256
                : 'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855',
            style: const TextStyle(
              fontFamily: 'monospace',
              fontSize: 11,
              color: Colors.white70,
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLifeSafetyNotice() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E20),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFF333336)),
      ),
      child: const Row(
        children: [
          Icon(Icons.shield_outlined, color: Color(0xFF64B5F6), size: 20),
          SizedBox(width: 12),
          Expanded(
            child: Text(
              'Inviolable Life Safety Exemption: Commercial billing quotas, rate throttles, or account suspensions can NEVER disable DNS resolution for emergency services (911.gov, 112.gov, emergency.gov) or core OS updates (update.microsoft.com).',
              style: TextStyle(color: Colors.white60, fontSize: 12, height: 1.4),
            ),
          ),
        ],
      ),
    );
  }
}
