// FocusDNS Enterprise Analytics Dashboard Screen - Big Data Columnar Analytics

import 'package:flutter/material.dart';
import '../models/enterprise_models.dart';
import '../services/enterprise_service.dart';
import '../widgets/columnar_timeseries_chart.dart';
import '../widgets/threat_matrix_gauge.dart';
import 'enterprise_tenants_screen.dart';
import 'enterprise_fleet_screen.dart';
import 'enterprise_rbac_screen.dart';
import 'enterprise_siem_screen.dart';
import 'enterprise_classroom_screen.dart';
import 'enterprise_scim_sso_screen.dart';

class EnterpriseAnalyticsDashboardScreen extends StatefulWidget {
  final String tenantId;
  final EnterpriseService? service;

  const EnterpriseAnalyticsDashboardScreen({
    super.key,
    this.tenantId = 'org_springfield',
    this.service,
  });

  @override
  State<EnterpriseAnalyticsDashboardScreen> createState() =>
      _EnterpriseAnalyticsDashboardScreenState();
}

class _EnterpriseAnalyticsDashboardScreenState
    extends State<EnterpriseAnalyticsDashboardScreen> {
  late final EnterpriseService _service;
  bool _isLoading = true;
  String _selectedTenant = 'org_springfield';

  List<TimeseriesPointModel> _timeseries = [];
  List<TopDomainStatModel> _topDomains = [];
  ThreatMatrixModel _threatMatrix = const ThreatMatrixModel(totalThreats: 0, breakdown: {});
  LatencyQuantilesModel _quantiles = const LatencyQuantilesModel(p50: 0, p90: 0, p95: 0, p99: 0, avg: 0, count: 0);

  String _searchFilter = '';

  @override
  void initState() {
    super.initState();
    _service = widget.service ?? EnterpriseService();
    _selectedTenant = widget.tenantId;
    _loadDashboardData();
  }

  Future<void> _loadDashboardData() async {
    setState(() => _isLoading = true);
    try {
      final tsFuture = _service.fetchTimeseries(_selectedTenant);
      final topFuture = _service.fetchTopDomains(_selectedTenant);
      final tmFuture = _service.fetchThreatMatrix(_selectedTenant);
      final latFuture = _service.fetchLatencyQuantiles(_selectedTenant);

      final results = await Future.wait([tsFuture, topFuture, tmFuture, latFuture]);

      if (mounted) {
        setState(() {
          _timeseries = results[0] as List<TimeseriesPointModel>;
          _topDomains = results[1] as List<TopDomainStatModel>;
          _threatMatrix = results[2] as ThreatMatrixModel;
          _quantiles = results[3] as LatencyQuantilesModel;
          _isLoading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF141416),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1E1E20),
        elevation: 0,
        title: Row(
          children: [
            const Icon(Icons.analytics_outlined, color: Color(0xFF64B5F6), size: 22),
            const SizedBox(width: 10),
            const Expanded(
              child: Text(
                'Enterprise Big Data Analytics',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.white70),
            tooltip: 'Refresh Telemetry',
            onPressed: _loadDashboardData,
          ),
          IconButton(
            icon: const Icon(Icons.hub_outlined, color: Color(0xFF81C784)),
            tooltip: 'Multi-Tenant Hierarchy',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => EnterpriseTenantsScreen(service: _service)),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.devices, color: Color(0xFFFFB74D)),
            tooltip: 'Fleet Push Control',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => EnterpriseFleetScreen(service: _service)),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.verified_user_outlined, color: Color(0xFFBA68C8)),
            tooltip: 'RBAC & Audit Ledger',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => EnterpriseRbacScreen(service: _service)),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.cloud_upload_outlined, color: Color(0xFF4DD0E1)),
            tooltip: 'SIEM Settings',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => EnterpriseSiemScreen(service: _service)),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.school_outlined, color: Color(0xFFFFD54F)),
            tooltip: 'Classroom & Exam Fleet',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => EnterpriseClassroomScreen(service: _service)),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.vpn_key_outlined, color: Color(0xFF80CBC4)),
            tooltip: 'Directory Federation & SCIM/SSO',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => EnterpriseScimSsoScreen(service: _service)),
            ),
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFF64B5F6)))
          : RefreshIndicator(
              onRefresh: _loadDashboardData,
              color: const Color(0xFF64B5F6),
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildTenantPill(),
                    const SizedBox(height: 16),
                    _buildKpiMetricsRow(),
                    const SizedBox(height: 18),
                    ColumnarTimeseriesChart(
                      points: _timeseries,
                      onRangeChanged: (seconds) => _loadDashboardData(),
                    ),
                    const SizedBox(height: 18),
                    ThreatMatrixGauge(matrix: _threatMatrix),
                    const SizedBox(height: 18),
                    _buildTopDomainsSection(),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _buildTenantPill() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E20),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFF2C2C2E)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              const Icon(Icons.apartment, color: Color(0xFF64B5F6), size: 18),
              const SizedBox(width: 8),
              Text(
                'Tenant: $_selectedTenant',
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.white),
              ),
            ],
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: const Color(0xFF4CAF50).withOpacity(0.15),
              borderRadius: BorderRadius.circular(6),
            ),
            child: const Text(
              'Columnar DuckDB Engine: ACTIVE',
              style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Color(0xFF4CAF50)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildKpiMetricsRow() {
    final totalQueries = _timeseries.fold<int>(0, (sum, p) => sum + p.totalQueries);
    final blockedCount = _timeseries.fold<int>(0, (sum, p) => sum + p.blockedQueries);

    return LayoutBuilder(
      builder: (context, constraints) {
        final cardWidth = (constraints.maxWidth - 12) / 2;
        return Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            _buildKpiCard(
              title: 'Ingested Telemetry',
              value: '$totalQueries',
              subtitle: 'Sub-second DuckDB buffer',
              icon: Icons.speed,
              iconColor: const Color(0xFF64B5F6),
              width: cardWidth,
            ),
            _buildKpiCard(
              title: 'Zero-Day Threats',
              value: '${_threatMatrix.totalThreats}',
              subtitle: 'On-device AI caught',
              icon: Icons.shield,
              iconColor: const Color(0xFFEF5350),
              width: cardWidth,
            ),
            _buildKpiCard(
              title: 'Policy Drops',
              value: '$blockedCount',
              subtitle: 'Focus rules enforced',
              icon: Icons.block,
              iconColor: const Color(0xFFFFB74D),
              width: cardWidth,
            ),
            _buildKpiCard(
              title: 'p99 Resolution Latency',
              value: '${_quantiles.p99.toStringAsFixed(0)} µs',
              subtitle: 'Avg: ${_quantiles.avg.toStringAsFixed(0)} µs',
              icon: Icons.timer_outlined,
              iconColor: const Color(0xFF81C784),
              width: cardWidth,
            ),
          ],
        );
      },
    );
  }

  Widget _buildKpiCard({
    required String title,
    required String value,
    required String subtitle,
    required IconData icon,
    required Color iconColor,
    required double width,
  }) {
    return Container(
      width: width,
      padding: const EdgeInsets.all(14),
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
              Text(title, style: const TextStyle(fontSize: 12, color: Color(0xFF888888))),
              Icon(icon, color: iconColor, size: 16),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white),
          ),
          const SizedBox(height: 4),
          Text(subtitle, style: const TextStyle(fontSize: 11, color: Color(0xFF666666))),
        ],
      ),
    );
  }

  Widget _buildTopDomainsSection() {
    final filtered = _topDomains.where((d) {
      if (_searchFilter.isEmpty) return true;
      return d.domain.contains(_searchFilter.toLowerCase());
    }).toList();

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
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Top Queried Domains',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                  letterSpacing: -0.2,
                ),
              ),
              Text(
                'Showing ${filtered.length}',
                style: const TextStyle(fontSize: 12, color: Color(0xFF888888)),
              ),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            style: const TextStyle(color: Colors.white, fontSize: 13),
            decoration: InputDecoration(
              hintText: 'Search domain name...',
              hintStyle: const TextStyle(color: Color(0xFF666666), fontSize: 13),
              prefixIcon: const Icon(Icons.search, color: Color(0xFF888888), size: 18),
              filled: true,
              fillColor: const Color(0xFF141416),
              isDense: true,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: Color(0xFF2C2C2E)),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: Color(0xFF2C2C2E)),
              ),
            ),
            onChanged: (val) => setState(() => _searchFilter = val),
          ),
          const SizedBox(height: 14),
          Column(
            children: filtered.map((d) {
              final isBlocked = d.action.contains('BLOCK');
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  children: [
                    Icon(
                      isBlocked ? Icons.shield : Icons.check_circle_outline,
                      color: isBlocked ? const Color(0xFFEF5350) : const Color(0xFF4CAF50),
                      size: 16,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            d.domain,
                            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.white),
                          ),
                          Text(
                            d.category,
                            style: const TextStyle(fontSize: 10, color: Color(0xFF888888)),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: isBlocked
                            ? const Color(0xFFEF5350).withOpacity(0.15)
                            : const Color(0xFF4CAF50).withOpacity(0.15),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        d.action,
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: isBlocked ? const Color(0xFFEF5350) : const Color(0xFF4CAF50),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      '${d.queryCount}',
                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.white70),
                    ),
                  ],
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }
}
