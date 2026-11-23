import 'package:flutter/material.dart';
import '../backend/router_service.dart';
import 'theme/wabi_sabi_theme.dart';

/// Screen displaying Windows Filtering Platform (WFP) driver status and per-app bypass prevention.
class WindowsWfpScreen extends StatefulWidget {
  const WindowsWfpScreen({super.key});

  @override
  State<WindowsWfpScreen> createState() => _WindowsWfpScreenState();
}

class _WindowsWfpScreenState extends State<WindowsWfpScreen> {
  WfpStatusModel? _wfpStatus;
  bool _isLoading = true;

  final List<Map<String, dynamic>> _monitoredApps = [
    {
      'name': 'Google Chrome',
      'executable': 'chrome.exe',
      'category': 'Web Browser',
      'vector': 'Hardcoded Secure DNS (DoH)',
      'status': 'Intercepted & Enforced',
      'icon': Icons.public_rounded,
    },
    {
      'name': 'Microsoft Edge',
      'executable': 'msedge.exe',
      'category': 'Web Browser',
      'vector': 'System Private DNS Bypass',
      'status': 'Policy Enforced',
      'icon': Icons.language_rounded,
    },
    {
      'name': 'Mozilla Firefox',
      'executable': 'firefox.exe',
      'category': 'Web Browser',
      'vector': 'Cloudflare TRR / DoH Tunnel',
      'status': 'Canary Drop Active',
      'icon': Icons.tab_rounded,
    },
    {
      'name': 'Discord',
      'executable': 'Discord.exe',
      'category': 'Voice & Chat',
      'vector': 'UDP Gateway & WebSockets',
      'status': 'Locked During Focus',
      'icon': Icons.chat_bubble_rounded,
    },
    {
      'name': 'Steam',
      'executable': 'steam.exe',
      'category': 'Gaming Network',
      'vector': 'Direct IP Game Servers',
      'status': 'Locked During Focus',
      'icon': Icons.sports_esports_rounded,
    },
  ];

  @override
  void initState() {
    super.initState();
    _loadStatus();
  }

  Future<void> _loadStatus() async {
    setState(() => _isLoading = true);
    final s = await FocusRouterService.getWfpStatus();
    if (mounted) {
      setState(() {
        _wfpStatus = s;
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
        title: const Text('Windows WFP Protection Driver'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            onPressed: _loadStatus,
            tooltip: 'Refresh WFP Status',
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
                  // WFP Kernel Status Card
                  _buildWfpDriverCard(palette, theme),
                  const SizedBox(height: 20),

                  // Conditional Uninstallation Law Posture
                  _buildConditionalLawCard(palette, theme),
                  const SizedBox(height: 20),

                  // Per-Application Interception List
                  _buildAppInterceptorSection(palette, theme),
                  const SizedBox(height: 20),

                  // OS Exemption Guarantee
                  _buildExemptionNotice(palette, theme),
                ],
              ),
            ),
    );
  }

  Widget _buildWfpDriverCard(WabiSabiPalette palette, ThemeData theme) {
    final s = _wfpStatus;
    if (s == null) return const SizedBox.shrink();

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
                  'KERNEL WFP ACTIVE',
                  style: TextStyle(color: Colors.green, fontWeight: FontWeight.bold, fontSize: 11),
                ),
              ),
              const Spacer(),
              Text(
                'Sublayers: ${s.sublayersRegistered}',
                style: TextStyle(color: palette.mutedInk, fontSize: 12),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            'Windows Filtering Platform Callout Driver',
            style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 4),
          Text(
            'Intercepts outbound traffic in ALE_AUTH_CONNECT_V4/V6 and DATAGRAM_DATA layers before packets reach the network adapter.',
            style: TextStyle(color: palette.mutedInk, fontSize: 12),
          ),
          const Divider(height: 24),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _metricTile('Active Filters', '${s.totalFiltersInstalled}', palette),
              _metricTile('Intercept Layers', 'ALE + Data', palette),
              _metricTile('Bypasses Blocked', '${s.auditLogCount}', palette),
            ],
          ),
        ],
      ),
    );
  }

  Widget _metricTile(String label, String value, WabiSabiPalette palette) {
    return Column(
      children: [
        Text(value, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
        const SizedBox(height: 2),
        Text(label, style: TextStyle(color: palette.mutedInk, fontSize: 11)),
      ],
    );
  }

  Widget _buildConditionalLawCard(WabiSabiPalette palette, ThemeData theme) {
    final s = _wfpStatus;
    final canUninstall = s?.canUninstall ?? true;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: canUninstall ? Colors.blue.withOpacity(0.08) : Colors.amber.withOpacity(0.1),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: canUninstall ? Colors.blue.withOpacity(0.3) : Colors.amber.withOpacity(0.4)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            canUninstall ? Icons.check_circle_outline_rounded : Icons.lock_rounded,
            color: canUninstall ? Colors.blue : Colors.amber.shade800,
            size: 22,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  canUninstall ? 'Normal Mode: Clean Uninstallation Permitted' : 'Active Focus: Service Uninstallation Locked',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                    color: canUninstall ? Colors.blue.shade900 : Colors.amber.shade900,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  canUninstall
                      ? 'No active focus timer. The Windows service and WFP sublayers can be stopped or removed with zero friction.'
                      : 'Active focus session in progress (${s?.remainingTimerSeconds ?? 0}s remaining). Service stop (sc stop) and uninstallation are strictly locked.',
                  style: TextStyle(fontSize: 11, color: palette.ink.withOpacity(0.8), height: 1.3),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAppInterceptorSection(WabiSabiPalette palette, ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Targeted Application Bypasses',
          style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 4),
        Text(
          'Monitors and prevents desktop applications from evading local DNS via proprietary DoH or direct socket connections.',
          style: TextStyle(color: palette.mutedInk, fontSize: 12),
        ),
        const SizedBox(height: 12),
        ..._monitoredApps.map((app) {
          return Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: palette.canvas,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: palette.border),
            ),
            child: Row(
              children: [
                CircleAvatar(
                  backgroundColor: palette.surface,
                  radius: 18,
                  child: Icon(app['icon'] as IconData, color: palette.ink, size: 18),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(app['name'] as String, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                          const SizedBox(width: 6),
                          Text('(${app['executable']})', style: TextStyle(color: palette.mutedInk, fontSize: 10, fontFamily: 'monospace')),
                        ],
                      ),
                      Text(app['vector'] as String, style: TextStyle(color: palette.mutedInk, fontSize: 11)),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: palette.strictAccent.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    app['status'] as String,
                    style: TextStyle(color: palette.strictAccent, fontWeight: FontWeight.bold, fontSize: 10),
                  ),
                ),
              ],
            ),
          );
        }),
      ],
    );
  }

  Widget _buildExemptionNotice(WabiSabiPalette palette, ThemeData theme) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.verified_user_rounded, color: palette.strictAccent, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Windows Update (svchost.exe), network DHCP (ports 67/68), loopback, and emergency telecom connections are strictly exempt and will never be blocked by WFP sublayers.',
              style: TextStyle(color: palette.mutedInk, fontSize: 11, height: 1.35),
            ),
          ),
        ],
      ),
    );
  }
}
