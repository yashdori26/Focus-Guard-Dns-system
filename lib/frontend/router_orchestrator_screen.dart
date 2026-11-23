import 'package:flutter/material.dart';
import '../backend/mikrotik_ubiquiti_service.dart';
import 'theme/wabi_sabi_theme.dart';

/// Screen displaying the Unified Router Orchestrator visual cockpit.
class RouterOrchestratorScreen extends StatefulWidget {
  const RouterOrchestratorScreen({super.key});

  @override
  State<RouterOrchestratorScreen> createState() => _RouterOrchestratorScreenState();
}

class _RouterOrchestratorScreenState extends State<RouterOrchestratorScreen> {
  RouterOrchestratorStatus? _status;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadStatus();
  }

  Future<void> _loadStatus() async {
    setState(() => _isLoading = true);
    final s = await FocusMikrotikUbiquitiService.getOrchestratorStatus();
    if (mounted) {
      setState(() {
        _status = s;
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = WabiSabiPalette.of(context);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Router Master Cockpit'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            onPressed: _loadStatus,
            tooltip: 'Refresh Cockpit',
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(20.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Master Cockpit Banner Card
                  _buildMasterCard(palette, theme),
                  const SizedBox(height: 20),

                  // Conditional Posture Card
                  _buildConditionalPostureCard(palette, theme),
                  const SizedBox(height: 20),

                  // Edge Subsystems Grid
                  _buildSubsystemsGrid(palette, theme),
                ],
              ),
            ),
    );
  }

  Widget _buildMasterCard(WabiSabiPalette palette, ThemeData theme) {
    final s = _status;
    if (s == null) return const SizedBox.shrink();

    final hitPct = (s.cacheHitRatio * 100).toStringAsFixed(1);

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: palette.canvas,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: palette.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.green.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Text(
                  'ORCHESTRATOR ONLINE',
                  style: TextStyle(color: Colors.green, fontWeight: FontWeight.bold, fontSize: 11),
                ),
              ),
              const Spacer(),
              Text(
                s.platform,
                style: TextStyle(color: palette.mutedInk, fontSize: 12),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            'Master Edge Router Firewall & DNS Orchestrator',
            style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 4),
          Text(
            'Coordinates in-memory cache, DoQ 0-RTT, DNSSEC validation, Multi-WAN failover, and CAKE traffic shaping.',
            style: TextStyle(color: palette.mutedInk, fontSize: 12),
          ),
          const Divider(height: 24),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _metricTile('Total Queries', '${s.totalQueries}', palette),
              _metricTile('Cache Hit Ratio', '$hitPct%', palette),
              _metricTile('Active Clients', '${s.connectedClientsCount}', palette),
              _metricTile('Active Uplink', 'Fiber WAN1', palette),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildConditionalPostureCard(WabiSabiPalette palette, ThemeData theme) {
    final s = _status;
    if (s == null) return const SizedBox.shrink();

    final isLocked = !s.canUninstall;
    final mins = s.remainingTimerSeconds ~/ 60;
    final secs = s.remainingTimerSeconds % 60;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: isLocked ? palette.strictAccent.withOpacity(0.08) : palette.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isLocked ? palette.strictAccent.withOpacity(0.3) : palette.border,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                isLocked ? Icons.lock_rounded : Icons.check_circle_outline_rounded,
                color: isLocked ? palette.strictAccent : Colors.green,
                size: 20,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  isLocked
                      ? 'LOCKED: Router Subsystem Teardown Forbidden (${mins.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')})'
                      : 'Normal Mode: Clean Router Deactivation Permitted',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: isLocked ? palette.strictAccent : Colors.green,
                    fontSize: 13,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            isLocked
                ? 'All router edge hooks, CAKE traffic shaping, and DNS redirection are locked. Daemon shutdown commands return ERROR_ACCESS_DENIED.'
                : 'The edge router is in normal mode. Router services can be stopped or uninstalled with zero friction.',
            style: TextStyle(fontSize: 12, color: palette.mutedInk),
          ),
        ],
      ),
    );
  }

  Widget _buildSubsystemsGrid(WabiSabiPalette palette, ThemeData theme) {
    final subsystems = [
      {
        'title': 'RFC 9250 DNS-over-QUIC (DoQ)',
        'subtitle': '0-RTT session resumption active over UDP 853',
        'status': 'ALPN: doq',
        'icon': Icons.bolt_rounded,
        'color': Colors.amber,
      },
      {
        'title': 'ICANN Root DNSSEC Validator',
        'subtitle': 'KSK-2017 & KSK-2024 trust anchors validated',
        'status': 'AD BIT ENFORCED',
        'icon': Icons.verified_user_rounded,
        'color': Colors.green,
      },
      {
        'title': 'Multi-WAN Uplink Failover',
        'subtitle': 'Fiber WAN1 primary, 5G LTE backup with LAN fallback',
        'status': 'WAN1 ACTIVE',
        'icon': Icons.alt_route_rounded,
        'color': Colors.blue,
      },
      {
        'title': 'CAKE DiffServ QoS & SQM',
        'subtitle': 'Emergency VoIP (DSCP EF) & DNS (DSCP CS6) prioritized',
        'status': 'DIFFSERV4 ACTIVE',
        'icon': Icons.speed_rounded,
        'color': Colors.deepOrange,
      },
      {
        'title': 'Fast-Path IPSet Engine',
        'subtitle': 'Hash:ip & hash:mac sub-microsecond line-rate filter',
        'status': '65k MAX ELEMS',
        'icon': Icons.flash_on_rounded,
        'color': Colors.purpleAccent,
      },
      {
        'title': 'Fail-Safe Local Fallback',
        'subtitle': 'IoT smart home (.lan, .local) continues if WAN fails',
        'status': 'STANDBY READY',
        'icon': Icons.security_rounded,
        'color': Colors.teal,
      },
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Unified Edge Subsystems',
          style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 12),
        ...subsystems.map((sub) {
          return Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: palette.canvas,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: palette.border),
            ),
            child: Row(
              children: [
                Icon(sub['icon'] as IconData, color: sub['color'] as Color, size: 24),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        sub['title'] as String,
                        style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        sub['subtitle'] as String,
                        style: TextStyle(fontSize: 11, color: palette.mutedInk),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: (sub['color'] as Color).withOpacity(0.12),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    sub['status'] as String,
                    style: TextStyle(
                      color: sub['color'] as Color,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
          );
        }),
      ],
    );
  }

  Widget _metricTile(String label, String value, WabiSabiPalette palette) {
    return Column(
      children: [
        Text(value, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: palette.ink)),
        const SizedBox(height: 2),
        Text(label, style: TextStyle(fontSize: 11, color: palette.mutedInk)),
      ],
    );
  }
}
