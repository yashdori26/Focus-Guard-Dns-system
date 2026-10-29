// FocusDNS Enterprise SOAR Incident Console & SIEM Ingestion Screen

import 'package:flutter/material.dart';
import '../models/enterprise_models.dart';
import '../services/enterprise_service.dart';

class EnterpriseSoarIncidentsScreen extends StatefulWidget {
  final EnterpriseService? service;
  final String tenantId;

  const EnterpriseSoarIncidentsScreen({
    super.key,
    this.service,
    this.tenantId = 'org_springfield',
  });

  @override
  State<EnterpriseSoarIncidentsScreen> createState() =>
      _EnterpriseSoarIncidentsScreenState();
}

class _EnterpriseSoarIncidentsScreenState
    extends State<EnterpriseSoarIncidentsScreen> with SingleTickerProviderStateMixin {
  late final EnterpriseService _service;
  late final TabController _tabController;
  bool _isLoading = true;

  List<SoarIncidentModel> _incidents = [];
  List<SiemIngestAlertModel> _siemAlerts = [];
  String _statusFilter = 'ALL';

  @override
  void initState() {
    super.initState();
    _service = widget.service ?? EnterpriseService();
    _tabController = TabController(length: 2, vsync: this);
    _loadData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      final incFuture = _service.fetchSoarIncidents();
      final siemFuture = _service.fetchSiemIngestAlerts(tenantId: widget.tenantId);
      final results = await Future.wait([incFuture, siemFuture]);

      if (mounted) {
        setState(() {
          _incidents = results[0] as List<SoarIncidentModel>;
          _siemAlerts = results[1] as List<SiemIngestAlertModel>;
          _isLoading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _liftQuarantine(String deviceId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E20),
        title: const Text('Lift Device Quarantine', style: TextStyle(color: Colors.white)),
        content: Text(
          'Are you sure you want to lift network isolation for device "$deviceId"?\n\n'
          'Life Safety exemptions (911.gov, update.microsoft.com) remain active regardless.',
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            child: const Text('Cancel', style: TextStyle(color: Colors.white60)),
            onPressed: () => Navigator.of(ctx).pop(false),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF4CAF50)),
            child: const Text('Confirm & Restore', style: TextStyle(color: Colors.white)),
            onPressed: () => Navigator.of(ctx).pop(true),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      final ok = await _service.liftDeviceQuarantine(deviceId);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              ok
                  ? 'Device "$deviceId" restored from quarantine.'
                  : 'Failed to lift quarantine.',
            ),
            backgroundColor: ok ? const Color(0xFF4CAF50) : const Color(0xFFE53935),
          ),
        );
        _loadData();
      }
    }
  }

  Future<void> _viewForensicTimeline(String deviceId) async {
    showDialog(
      context: context,
      builder: (ctx) => FutureBuilder<EndpointDnsTimelineModel>(
        future: _service.fetchEndpointTimeline(
          tenantId: widget.tenantId,
          deviceId: deviceId,
        ),
        builder: (ctx, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator(color: Color(0xFF64B5F6)));
          }
          final timeline = snapshot.data!;
          return AlertDialog(
            backgroundColor: const Color(0xFF1E1E20),
            title: Text(
              'Forensic Trace: $deviceId',
              style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
            ),
            content: SizedBox(
              width: 550,
              height: 380,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 12,
                    runSpacing: 8,
                    children: [
                      _metricChip('Total Queries', '${timeline.totalQueriesRecorded}', const Color(0xFF64B5F6)),
                      _metricChip('Bursts Detected', '${timeline.burstCount}', const Color(0xFFFFB74D)),
                      _metricChip('C2 Beacons', '${timeline.suspectedBeacons.length}', const Color(0xFFE57373)),
                    ],
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Chronological DNS Resolution Activity:',
                    style: TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: ListView.separated(
                      itemCount: timeline.timeline.length,
                      separatorBuilder: (_, __) => const Divider(color: Colors.white12, height: 1),
                      itemBuilder: (ctx, i) {
                        final entry = timeline.timeline[i];
                        final isBlock = entry.action == 'BLOCK';
                        return ListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          leading: Icon(
                            isBlock ? Icons.block : Icons.check_circle_outline,
                            color: isBlock ? const Color(0xFFE53935) : const Color(0xFF4CAF50),
                            size: 18,
                          ),
                          title: Text(
                            entry.domain,
                            style: const TextStyle(color: Colors.white, fontSize: 13, fontFamily: 'monospace'),
                          ),
                          subtitle: Text(
                            'Client: ${entry.clientIp} • Threat: ${entry.threatType}',
                            style: const TextStyle(color: Colors.white54, fontSize: 11),
                          ),
                          trailing: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: isBlock ? const Color(0x33E53935) : const Color(0x334CAF50),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              entry.action,
                              style: TextStyle(
                                color: isBlock ? const Color(0xFFEF9A9A) : const Color(0xFFA5D6A7),
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                child: const Text('Close', style: TextStyle(color: Color(0xFF64B5F6))),
                onPressed: () => Navigator.of(ctx).pop(),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _metricChip(String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('$label: ', style: const TextStyle(color: Colors.white70, fontSize: 11)),
          Text(value, style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF141416),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1E1E20),
        elevation: 0,
        title: const Row(
          children: [
            Icon(Icons.security, color: Color(0xFFE53935), size: 22),
            SizedBox(width: 10),
            Expanded(
              child: Text(
                'SOAR Security & Incident Response',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.white70),
            tooltip: 'Refresh Incidents',
            onPressed: _loadData,
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: const Color(0xFFE53935),
          tabs: [
            Tab(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.shield_outlined, size: 16),
                  const SizedBox(width: 8),
                  Text('SOAR Incidents (${_incidents.length})'),
                ],
              ),
            ),
            Tab(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.cloud_sync_outlined, size: 16),
                  const SizedBox(width: 8),
                  Text('SIEM Ingest Alerts (${_siemAlerts.length})'),
                ],
              ),
            ),
          ],
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFFE53935)))
          : TabBarView(
              controller: _tabController,
              children: [
                _buildSoarIncidentsTab(),
                _buildSiemIngestTab(),
              ],
            ),
    );
  }

  Widget _buildSoarIncidentsTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildCircuitBreakerCard(),
          const SizedBox(height: 16),
          Row(
            children: [
              const Text(
                'Incident Records',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.white),
              ),
              const Spacer(),
              _buildStatusFilterChip('ALL'),
              const SizedBox(width: 8),
              _buildStatusFilterChip('CONTAINED'),
              const SizedBox(width: 8),
              _buildStatusFilterChip('OPEN'),
            ],
          ),
          const SizedBox(height: 12),
          if (_incidents.isEmpty)
            _buildEmptyState('No active security incidents detected.')
          else
            ..._incidents
                .where((i) => _statusFilter == 'ALL' || i.status == _statusFilter)
                .map(_buildIncidentCard),
        ],
      ),
    );
  }

  Widget _buildCircuitBreakerCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E20),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFF2E2E32)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.electric_bolt, color: Color(0xFFFFB74D), size: 20),
              const SizedBox(width: 8),
              const Text(
                'SOAR Anti-Cascade Circuit Breaker',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.white),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: const Color(0x334CAF50),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: const Text(
                  'HEALTHY - ARMED',
                  style: TextStyle(color: Color(0xFF81C784), fontSize: 10, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          const Text(
            'Limits automated device isolations to max 5 endpoints per 10 minutes to protect entire organizations '
            'from synthetic denial-of-service or alert storms.',
            style: TextStyle(color: Colors.white60, fontSize: 12),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 16,
            runSpacing: 8,
            children: [
              _metricChip('Quarantine Rate-Limit', '5 / 10m', const Color(0xFFFFB74D)),
              _metricChip('Trips Recorded', '0', const Color(0xFF4CAF50)),
              _metricChip('Life Safety Guard', 'ACTIVE (Unconditional)', const Color(0xFF64B5F6)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStatusFilterChip(String label) {
    final isSelected = _statusFilter == label;
    return ChoiceChip(
      label: Text(label, style: TextStyle(color: isSelected ? Colors.white : Colors.white70, fontSize: 11)),
      selected: isSelected,
      selectedColor: const Color(0xFFE53935),
      backgroundColor: const Color(0xFF2E2E32),
      onSelected: (_) => setState(() => _statusFilter = label),
    );
  }

  Widget _buildIncidentCard(SoarIncidentModel inc) {
    final isContained = inc.status == 'CONTAINED';
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E20),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: inc.riskScore >= 90 ? const Color(0xFFE53935).withOpacity(0.5) : const Color(0xFF2E2E32),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: isContained ? const Color(0x334CAF50) : const Color(0x33E53935),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  inc.status,
                  style: TextStyle(
                    color: isContained ? const Color(0xFF81C784) : const Color(0xFFE57373),
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  inc.domain,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    fontFamily: 'monospace',
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                'Risk: ${inc.riskScore.toStringAsFixed(1)}',
                style: TextStyle(
                  color: inc.riskScore >= 90 ? const Color(0xFFE53935) : const Color(0xFFFFB74D),
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              Text('Device: ${inc.deviceId}', style: const TextStyle(color: Colors.white70, fontSize: 12)),
              const Text('•', style: TextStyle(color: Colors.white30)),
              Text('Trigger: ${inc.triggerType}', style: const TextStyle(color: Colors.white70, fontSize: 12)),
              const Text('•', style: TextStyle(color: Colors.white30)),
              Text('Snapshot: ${inc.snapshotRecords} records', style: const TextStyle(color: Colors.white70, fontSize: 12)),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: inc.actionsExecuted.map((act) {
              return Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: const Color(0xFF2E2E32),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  act,
                  style: const TextStyle(color: Color(0xFF64B5F6), fontSize: 10, fontWeight: FontWeight.bold),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              OutlinedButton.icon(
                icon: const Icon(Icons.history, size: 14, color: Color(0xFF64B5F6)),
                label: const Text('Forensic Trace', style: TextStyle(color: Color(0xFF64B5F6), fontSize: 12)),
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: Color(0xFF64B5F6)),
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                ),
                onPressed: () => _viewForensicTimeline(inc.deviceId),
              ),
              const SizedBox(width: 8),
              ElevatedButton.icon(
                icon: const Icon(Icons.lock_open, size: 14, color: Colors.white),
                label: const Text('Lift Quarantine', style: TextStyle(color: Colors.white, fontSize: 12)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF4CAF50),
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                ),
                onPressed: () => _liftQuarantine(inc.deviceId),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSiemIngestTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSiemVendorSummary(),
          const SizedBox(height: 16),
          const Text(
            'Inbound Normalized Security Feeds',
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.white),
          ),
          const SizedBox(height: 12),
          if (_siemAlerts.isEmpty)
            _buildEmptyState('No external SIEM alerts received yet.')
          else
            ..._siemAlerts.map(_buildSiemAlertCard),
        ],
      ),
    );
  }

  Widget _buildSiemVendorSummary() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E20),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFF2E2E32)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.hub, color: Color(0xFF4DD0E1), size: 20),
              SizedBox(width: 8),
              Text(
                'Bidirectional SIEM Ingestion Gateway',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.white),
              ),
            ],
          ),
          const SizedBox(height: 8),
          const Text(
            'Receives alerts from external Splunk CIM, Datadog Monitors, and Elastic ECS with cryptographic '
            'HMAC verification, sliding-window deduplication, and automated SOAR response.',
            style: TextStyle(color: Colors.white60, fontSize: 12),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 12,
            runSpacing: 8,
            children: [
              _vendorBadge('SPLUNK', const Color(0xFFFF9800)),
              _vendorBadge('DATADOG', const Color(0xFFAB47BC)),
              _vendorBadge('ELASTIC', const Color(0xFF26A69A)),
              _metricChip('Dedup Window', '300s', const Color(0xFF81C784)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _vendorBadge(String name, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.15),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withOpacity(0.4)),
      ),
      child: Text(
        name,
        style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.bold),
      ),
    );
  }

  Widget _buildSiemAlertCard(SiemIngestAlertModel alert) {
    Color vendorColor = const Color(0xFF64B5F6);
    if (alert.vendor == 'SPLUNK') vendorColor = const Color(0xFFFF9800);
    if (alert.vendor == 'DATADOG') vendorColor = const Color(0xFFAB47BC);
    if (alert.vendor == 'ELASTIC') vendorColor = const Color(0xFF26A69A);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E20),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFF2E2E32)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: vendorColor.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  alert.vendor,
                  style: TextStyle(color: vendorColor, fontSize: 10, fontWeight: FontWeight.bold),
                ),
              ),
              const SizedBox(width: 8),
              if (alert.deduplicated)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: const Color(0x33FFB74D),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: const Text(
                    'DEDUPLICATED',
                    style: TextStyle(color: Color(0xFFFFB74D), fontSize: 9, fontWeight: FontWeight.bold),
                  ),
                ),
              const Spacer(),
              Text(
                'Severity: ${alert.severity}',
                style: const TextStyle(color: Color(0xFFE57373), fontSize: 11, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            alert.threatType,
            style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 4),
          if (alert.indicatorDomain.isNotEmpty)
            Text(
              'Domain: ${alert.indicatorDomain}',
              style: const TextStyle(color: Color(0xFF81C784), fontSize: 12, fontFamily: 'monospace'),
            ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            children: [
              if (alert.deviceId != null)
                Text('Device: ${alert.deviceId}', style: const TextStyle(color: Colors.white60, fontSize: 11)),
              if (alert.clientIp != null)
                Text('Client IP: ${alert.clientIp}', style: const TextStyle(color: Colors.white60, fontSize: 11)),
              Text('Risk Score: ${alert.riskScore}', style: const TextStyle(color: Colors.white60, fontSize: 11)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(String msg) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 36, horizontal: 16),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E20),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        children: [
          const Icon(Icons.check_circle_outline, color: Color(0xFF4CAF50), size: 36),
          const SizedBox(height: 12),
          Text(msg, style: const TextStyle(color: Colors.white70, fontSize: 13)),
        ],
      ),
    );
  }
}
