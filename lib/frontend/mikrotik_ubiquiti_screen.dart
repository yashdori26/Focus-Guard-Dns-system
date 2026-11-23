import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../backend/mikrotik_ubiquiti_service.dart';
import 'theme/wabi_sabi_theme.dart';

/// Screen displaying MikroTik RouterOS and Ubiquiti Gateway integrations.
class MikrotikUbiquitiScreen extends StatefulWidget {
  const MikrotikUbiquitiScreen({super.key});

  @override
  State<MikrotikUbiquitiScreen> createState() => _MikrotikUbiquitiScreenState();
}

class _MikrotikUbiquitiScreenState extends State<MikrotikUbiquitiScreen> with SingleTickerProviderStateMixin {
  MikrotikGatewayStatus? _mikrotikStatus;
  UbiquitiGatewayStatus? _ubiquitiStatus;
  bool _isLoading = true;
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
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
    final m = await FocusMikrotikUbiquitiService.getMikrotikStatus();
    final u = await FocusMikrotikUbiquitiService.getUbiquitiStatus();
    if (mounted) {
      setState(() {
        _mikrotikStatus = m;
        _ubiquitiStatus = u;
        _isLoading = false;
      });
    }
  }

  void _copyCommand(BuildContext context, String text, String message) {
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: WabiSabiPalette.of(context).ink,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final palette = WabiSabiPalette.of(context);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('MikroTik & Ubiquiti Gateways'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            onPressed: _loadData,
            tooltip: 'Refresh Status',
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
                  // Enterprise Gateway Health Card
                  _buildHeaderCard(palette, theme),
                  const SizedBox(height: 20),

                  // Conditional Uninstallation Posture Card
                  _buildConditionalPostureCard(palette, theme),
                  const SizedBox(height: 20),

                  // Gateway Platform Tabs
                  _buildPlatformTabs(palette, theme),
                ],
              ),
            ),
    );
  }

  Widget _buildHeaderCard(WabiSabiPalette palette, ThemeData theme) {
    final m = _mikrotikStatus;
    final u = _ubiquitiStatus;
    if (m == null || u == null) return const SizedBox.shrink();

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
                  color: Colors.teal.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Text(
                  'ENTERPRISE GATEWAY ACTIVE',
                  style: TextStyle(color: Colors.teal, fontWeight: FontWeight.bold, fontSize: 11),
                ),
              ),
              const Spacer(),
              Text(
                'Container & L7 Interception',
                style: TextStyle(color: palette.mutedInk, fontSize: 12),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            'Hardware Wi-Fi Router Edge Protection',
            style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 4),
          Text(
            'Transparent dst-nat interception with RouterOS containers and UniFi on_boot podman daemons.',
            style: TextStyle(color: palette.mutedInk, fontSize: 12),
          ),
          const Divider(height: 24),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _metricTile('MikroTik Netwatch', 'Healthy', palette),
              _metricTile('UniFi DoT Drops', '${u.blockedDoTDrops}', palette),
              _metricTile('Rogue IPs Filtered', '${m.monitoredRogueIps}', palette),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildConditionalPostureCard(WabiSabiPalette palette, ThemeData theme) {
    final m = _mikrotikStatus;
    if (m == null) return const SizedBox.shrink();

    final isLocked = !m.canUninstall;
    final mins = m.remainingTimerSeconds ~/ 60;
    final secs = m.remainingTimerSeconds % 60;

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
                      ? 'LOCKED: Router NAT Modification Forbidden (${mins.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')})'
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
                ? 'RouterOS dst-nat rules and UniFi podman containers are strictly locked. Teardown script generation is blocked until the focus session concludes.'
                : 'Router firewall protection is idle. You may freely disable NAT redirection or uninstall the container.',
            style: TextStyle(fontSize: 12, color: palette.mutedInk),
          ),
        ],
      ),
    );
  }

  Widget _buildPlatformTabs(WabiSabiPalette palette, ThemeData theme) {
    final mikrotikCmd = FocusMikrotikUbiquitiService.getMikrotikScript('profile_home_primary');
    final ubiquitiCmd = FocusMikrotikUbiquitiService.getUbiquitiScript('profile_home_primary');

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: palette.canvas,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: palette.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '1-Click Gateway Deployment Scripts',
            style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 4),
          Text(
            'Copy and paste into your router SSH terminal or WebFig command prompt.',
            style: TextStyle(fontSize: 12, color: palette.mutedInk),
          ),
          const SizedBox(height: 14),
          TabBar(
            controller: _tabController,
            labelColor: palette.ink,
            unselectedLabelColor: palette.mutedInk,
            indicatorColor: palette.strictAccent,
            tabs: const [
              Tab(text: 'MikroTik RouterOS v7'),
              Tab(text: 'Ubiquiti UniFi & EdgeMAX'),
            ],
          ),
          const SizedBox(height: 14),
          SizedBox(
            height: 130,
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildInstallTab(mikrotikCmd, 'MikroTik CLI command copied to clipboard.', palette),
                _buildInstallTab(ubiquitiCmd, 'UniFi curl command copied to clipboard.', palette),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInstallTab(String command, String copyMsg, WabiSabiPalette palette) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: palette.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  command,
                  style: TextStyle(fontFamily: 'monospace', fontSize: 11, color: palette.ink),
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              IconButton(
                icon: const Icon(Icons.copy_rounded, size: 18),
                onPressed: () => _copyCommand(context, command, copyMsg),
                tooltip: 'Copy Command',
              ),
            ],
          ),
          const Spacer(),
          Text(
            '• Auto-configures netwatch fail-safe & anti-bypass drops',
            style: TextStyle(fontSize: 11, color: palette.mutedInk),
          ),
        ],
      ),
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
