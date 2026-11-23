/// FocusDNS Flutter Screen - AI-Powered On-Device Threat Radar
/// Displays live radar scan, edge device threat events, latency metrics,
/// interactive domain hunt inspector, and Conditional Whitelisting controls.

import 'package:flutter/material.dart';
import '../models/ai_threat_models.dart';
import '../services/ai_threat_service.dart';
import '../widgets/radar_scan_widget.dart';
import '../widgets/ai_risk_meter.dart';
import 'homograph_inspector_screen.dart';
import 'dga_neural_screen.dart';

class AiThreatRadarScreen extends StatefulWidget {
  final AiThreatService? threatService;

  const AiThreatRadarScreen({Key? key, this.threatService}) : super(key: key);

  @override
  State<AiThreatRadarScreen> createState() => _AiThreatRadarScreenState();
}

class _AiThreatRadarScreenState extends State<AiThreatRadarScreen> {
  late AiThreatService _service;
  final TextEditingController _domainController = TextEditingController();

  bool _isLoading = true;
  bool _isHunting = false;
  AiTelemetrySnapshot? _telemetry;
  List<EdgeThreatEvent> _threatEvents = [];
  AiThreatVerdict? _huntResult;

  @override
  void initState() {
    super.initState();
    _service = widget.threatService ?? AiThreatService();
    _loadDashboardData();
  }

  @override
  void dispose() {
    _domainController.dispose();
    super.dispose();
  }

  Future<void> _loadDashboardData() async {
    if (mounted) {
      setState(() => _isLoading = true);
    }
    final telem = await _service.fetchTelemetry();
    final events = await _service.fetchRecentRouterThreats();

    if (mounted) {
      setState(() {
        _telemetry = telem;
        _threatEvents = events;
        _isLoading = false;
      });
    }
  }

  Future<void> _runDomainHunt() async {
    final query = _domainController.text.trim();
    if (query.isEmpty) return;

    setState(() => _isHunting = true);
    final verdict = await _service.huntDomain(query);
    if (mounted) {
      setState(() {
        _huntResult = verdict;
        _isHunting = false;
      });
    }
  }

  Future<void> _handleWhitelistAttempt(String domain) async {
    final res = await _service.requestWhitelist(domain);
    if (!mounted) return;

    if (res['success'] == true) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Domain "$domain" added to whitelist successfully.'),
          backgroundColor: Colors.green,
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            res['error'] ?? 'Access Denied: Focus lockdown active!',
          ),
          backgroundColor: Colors.redAccent,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final telem = _telemetry ??
        AiTelemetrySnapshot(
          totalQueries: 0,
          totalThreatsBlocked: 0,
          homographsBlocked: 0,
          dgaBlocked: 0,
          phishingBlocked: 0,
          exemptionsPassed: 0,
          avgLatencyUs: 0.0,
          isLocked: false,
        );

    return Scaffold(
      backgroundColor: const Color(0xFF090D16),
      appBar: AppBar(
        title: const Text('AI Threat Radar', style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: const Color(0xFF0F172A),
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadDashboardData,
            tooltip: 'Refresh Telemetry',
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFF10B981)))
          : RefreshIndicator(
              onRefresh: _loadDashboardData,
              child: ListView(
                padding: const EdgeInsets.all(16.0),
                children: [
                  // Top Radar Banner
                  _buildRadarBanner(telem),
                  const SizedBox(height: 16),

                  // 4 Primary Metric Cards
                  _buildTelemetryGrid(telem),
                  const SizedBox(height: 20),

                  // Interactive Threat Hunting Input
                  _buildDomainHuntCard(),
                  const SizedBox(height: 20),

                  // Navigation Tabs to Sub-Inspectors
                  _buildInspectorNavigation(),
                  const SizedBox(height: 20),

                  // Live Edge Router Threat Log
                  _buildLiveThreatFeed(),
                ],
              ),
            ),
    );
  }

  Widget _buildRadarBanner(AiTelemetrySnapshot telem) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF0F172A),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF10B981).withOpacity(0.3)),
      ),
      child: Row(
        children: [
          RadarScanWidget(
            size: 110,
            activeThreatBlips: _threatEvents.length,
            isScanning: true,
          ),
          const SizedBox(width: 20),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: const BoxDecoration(
                        color: Color(0xFF10B981),
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 6),
                    const Text(
                      'REAL-TIME AI HUNTING ACTIVE',
                      style: TextStyle(
                        color: Color(0xFF10B981),
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1.0,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                const Text(
                  'Zero-Day Threat Shield',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Analyzing IDN homographs, DGA C2 patterns, and brand spoofing locally with sub-microsecond latency.',
                  style: TextStyle(fontSize: 12, color: Colors.grey[400]),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTelemetryGrid(AiTelemetrySnapshot telem) {
    return GridView.count(
      crossAxisCount: 2,
      crossAxisSpacing: 12,
      mainAxisSpacing: 12,
      childAspectRatio: 1.6,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      children: [
        _buildMetricTile(
          'Threats Neutralized',
          '${telem.totalThreatsBlocked}',
          '${telem.homographsBlocked} Homo · ${telem.dgaBlocked} DGA',
          Icons.shield,
          const Color(0xFFEF4444),
        ),
        _buildMetricTile(
          'Inference Latency',
          '${telem.avgLatencyUs.toStringAsFixed(1)} µs',
          'Zero Cloud Dependency',
          Icons.speed,
          const Color(0xFF10B981),
        ),
        _buildMetricTile(
          'Total Analyzed',
          '${telem.totalQueries}',
          '${telem.exemptionsPassed} Life-Safety Passed',
          Icons.analytics,
          const Color(0xFF3B82F6),
        ),
        _buildMetricTile(
          'Focus Lockdown',
          telem.isLocked ? 'LOCKED' : 'IDLE',
          telem.isLocked ? 'Law Active (Timer > 0)' : 'Modifications Allowed',
          Icons.lock_clock,
          telem.isLocked ? const Color(0xFFF59E0B) : const Color(0xFF10B981),
        ),
      ],
    );
  }

  Widget _buildMetricTile(
    String title,
    String value,
    String subtitle,
    IconData icon,
    Color color,
  ) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF0F172A),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withOpacity(0.06)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(title, style: TextStyle(color: Colors.grey[400], fontSize: 11)),
              Icon(icon, color: color, size: 18),
            ],
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          Text(
            subtitle,
            style: TextStyle(color: Colors.grey[500], fontSize: 10),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  Widget _buildDomainHuntCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF0F172A),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Live Domain Threat Hunting',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
          ),
          const SizedBox(height: 6),
          Text(
            'Test real-time on-device classification against any domain name.',
            style: TextStyle(fontSize: 12, color: Colors.grey[400]),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _domainController,
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    hintText: 'Enter domain (e.g. \u0430pple.com, paypa1.com)',
                    hintStyle: TextStyle(color: Colors.grey[600]),
                    filled: true,
                    fillColor: const Color(0xFF1E293B),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide.none,
                    ),
                  ),
                  onSubmitted: (_) => _runDomainHunt(),
                ),
              ),
              const SizedBox(width: 10),
              ElevatedButton.icon(
                onPressed: _isHunting ? null : _runDomainHunt,
                icon: _isHunting
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : const Icon(Icons.search, size: 18),
                label: const Text('Hunt'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF10B981),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
              ),
            ],
          ),
          if (_huntResult != null) ...[
            const SizedBox(height: 16),
            _buildHuntResultCard(_huntResult!),
          ],
        ],
      ),
    );
  }

  Widget _buildHuntResultCard(AiThreatVerdict res) {
    final isThreat = res.isThreat;
    final color = isThreat ? const Color(0xFFEF4444) : const Color(0xFF10B981);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  res.domain,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: color),
                ),
                child: Text(
                  res.action,
                  style: TextStyle(
                    color: color,
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          AiRiskMeter(score: res.riskScore),
          const SizedBox(height: 10),
          Text(
            'Reason: ${res.reason}',
            style: const TextStyle(fontSize: 12, color: Colors.white70),
          ),
          const SizedBox(height: 4),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Category: ${res.category}',
                style: TextStyle(fontSize: 11, color: Colors.grey[400]),
              ),
              Text(
                'Inference: ${res.latencyUs.toStringAsFixed(1)} µs',
                style: TextStyle(fontSize: 11, color: Colors.grey[400]),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              OutlinedButton.icon(
                onPressed: () => _handleWhitelistAttempt(res.domain),
                icon: const Icon(Icons.playlist_add, size: 16),
                label: const Text('Add to Whitelist'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.white70,
                  side: BorderSide(color: Colors.white.withOpacity(0.2)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildInspectorNavigation() {
    return Row(
      children: [
        Expanded(
          child: OutlinedButton.icon(
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => HomographInspectorScreen(threatService: _service),
                ),
              );
            },
            icon: const Icon(Icons.translate, size: 18),
            label: const Text('TR39 Homographs'),
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14),
              side: BorderSide(color: const Color(0xFF10B981).withOpacity(0.4)),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: OutlinedButton.icon(
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => DgaNeuralScreen(threatService: _service),
                ),
              );
            },
            icon: const Icon(Icons.memory, size: 18),
            label: const Text('DGA Neural MLP'),
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14),
              side: BorderSide(color: const Color(0xFF3B82F6).withOpacity(0.4)),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildLiveThreatFeed() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF0F172A),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'LAN Edge Threat Feed',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
              ),
              Text(
                '${_threatEvents.length} Recent Events',
                style: TextStyle(fontSize: 12, color: Colors.grey[400]),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (_threatEvents.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Center(
                child: Text('No threats detected on LAN.', style: TextStyle(color: Colors.grey[500])),
              ),
            )
          else
            ListView.separated(
              itemCount: _threatEvents.length,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              separatorBuilder: (_, __) => Divider(color: Colors.white.withOpacity(0.06)),
              itemBuilder: (context, index) {
                final ev = _threatEvents[index];
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: const Color(0xFFEF4444).withOpacity(0.15),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.shield_outlined, color: Color(0xFFEF4444), size: 18),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              ev.domain,
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                                fontSize: 13,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              '${ev.deviceName} (${ev.clientIp})',
                              style: TextStyle(color: Colors.grey[400], fontSize: 11),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              ev.reason,
                              style: TextStyle(color: Colors.grey[500], fontSize: 11),
                            ),
                          ],
                        ),
                      ),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: const Color(0xFFEF4444).withOpacity(0.2),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              ev.threatType,
                              style: const TextStyle(
                                color: Color(0xFFEF4444),
                                fontSize: 9,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '${ev.riskScore.toStringAsFixed(0)}%',
                            style: const TextStyle(
                              color: Color(0xFFEF4444),
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                );
              },
            ),
        ],
      ),
    );
  }
}
