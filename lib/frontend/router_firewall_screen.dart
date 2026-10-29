import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../backend/router_service.dart';
import 'theme/wabi_sabi_theme.dart';

/// Screen managing whole-home router firewall integration and device profile mapping.
class RouterFirewallScreen extends StatefulWidget {
  const RouterFirewallScreen({super.key});

  @override
  State<RouterFirewallScreen> createState() => _RouterFirewallScreenState();
}

class _RouterFirewallScreenState extends State<RouterFirewallScreen> {
  RouterConfigModel? _routerConfig;
  List<HouseholdDeviceModel> _devices = [];
  bool _isLoading = true;
  String _selectedPlatform = 'OpenWrt';

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    final cfg = await FocusRouterService.getRouterStatus();
    final devs = await FocusRouterService.getConnectedDevices();
    if (mounted) {
      setState(() {
        _routerConfig = cfg;
        _devices = devs;
        _isLoading = false;
      });
    }
  }

  void _copyCommand(BuildContext context, String cmd) {
    Clipboard.setData(ClipboardData(text: cmd));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('Router install command copied to clipboard.'),
        backgroundColor: WabiSabiPalette.of(context).ink,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  void _showProfileDialog(HouseholdDeviceModel device) {
    final profiles = [
      {'id': 'profile_strict_kids', 'label': 'Strict Kids', 'desc': 'Blocks social, adult & enforces SafeSearch'},
      {'id': 'profile_deep_work', 'label': 'Deep Work', 'desc': 'Blocks news, shopping & social distraction'},
      {'id': 'profile_ad_free_iot', 'label': 'Ad-Free IoT', 'desc': 'Blocks smart TV telemetry & trackers'},
      {'id': 'profile_family_safe', 'label': 'Family Safe', 'desc': 'Standard malware & phishing shield'},
    ];

    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) {
        final palette = WabiSabiPalette.of(ctx);
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(20.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Assign Profile: ${device.hostname}',
                  style: Theme.of(ctx).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                ),
                Text(
                  'Hardware MAC: ${device.macAddress}',
                  style: TextStyle(fontSize: 12, color: palette.mutedInk),
                ),
                const SizedBox(height: 16),
                ...profiles.map((p) {
                  final isSelected = device.assignedProfile == p['id'];
                  return ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(p['label']!, style: const TextStyle(fontWeight: FontWeight.w600)),
                    subtitle: Text(p['desc']!, style: TextStyle(fontSize: 12, color: palette.mutedInk)),
                    trailing: isSelected ? Icon(Icons.check_circle_rounded, color: palette.strictAccent) : null,
                    onTap: () async {
                      Navigator.pop(ctx);
                      await FocusRouterService.assignDeviceProfile(device.macAddress, p['id']!);
                      _loadData();
                    },
                  );
                }),
              ],
            ),
          ),
        );
      },
    );
  }

  IconData _categoryIcon(String category) {
    switch (category.toLowerCase()) {
      case 'smarttv':
        return Icons.tv_rounded;
      case 'tablet':
        return Icons.tablet_mac_rounded;
      case 'laptop':
        return Icons.laptop_mac_rounded;
      case 'gamingconsole':
        return Icons.sports_esports_rounded;
      case 'iot':
        return Icons.router_rounded;
      default:
        return Icons.devices_rounded;
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = WabiSabiPalette.of(context);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Whole-Home Router Firewall'),
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
                  // Gateway Health Banner
                  _buildGatewayCard(palette, theme),
                  const SizedBox(height: 24),

                  // 1-Click Installation Code Section
                  _buildInstallScriptSection(palette, theme),
                  const SizedBox(height: 24),

                  // Connected Household Devices Section
                  _buildDeviceListSection(palette, theme),
                  const SizedBox(height: 24),

                  // Bypass & Fail-Safe Guarantee Card
                  _buildGuaranteeCard(palette, theme),
                ],
              ),
            ),
    );
  }

  Widget _buildGatewayCard(WabiSabiPalette palette, ThemeData theme) {
    final cfg = _routerConfig;
    if (cfg == null) return const SizedBox.shrink();

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
                  color: palette.strictAccent.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  cfg.platformType,
                  style: TextStyle(color: palette.strictAccent, fontWeight: FontWeight.bold, fontSize: 12),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                'v${cfg.firmwareVersion}',
                style: TextStyle(color: palette.mutedInk, fontSize: 12),
              ),
              const Spacer(),
              const Icon(Icons.check_circle_rounded, color: Colors.green, size: 16),
              const SizedBox(width: 4),
              const Text(
                'INTERCEPTING',
                style: TextStyle(color: Colors.green, fontWeight: FontWeight.bold, fontSize: 11),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            'Whole-Home Wi-Fi Gateway Protection',
            style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 4),
          Text(
            'All UDP/TCP Port 53 queries across LAN bridge interfaces are redirected to local FocusDNS daemon on port 5353.',
            style: TextStyle(color: palette.mutedInk, fontSize: 12),
          ),
          const Divider(height: 28),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _metricTile('24h Queries', '${cfg.queriesTotal}', palette),
              _metricTile('Cache Hit Ratio', '${(cfg.cacheHitRatio * 100).toInt()}%', palette),
              _metricTile('Bypasses Blocked', '${cfg.bypassesBlocked24h}', palette),
            ],
          ),
        ],
      ),
    );
  }

  Widget _metricTile(String label, String value, WabiSabiPalette palette) {
    return Column(
      children: [
        Text(value, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
        const SizedBox(height: 2),
        Text(label, style: TextStyle(color: palette.mutedInk, fontSize: 11)),
      ],
    );
  }

  Widget _buildInstallScriptSection(WabiSabiPalette palette, ThemeData theme) {
    final script = FocusRouterService.getInstallScript(
      _selectedPlatform,
      _routerConfig?.activeProfile ?? 'profile_home_primary',
    );

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
          Text(
            '1-Click Router Installation',
            style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 4),
          Text(
            'Run this single command via SSH inside your router terminal to install and configure FocusDNS instantly.',
            style: TextStyle(color: palette.mutedInk, fontSize: 12),
          ),
          const SizedBox(height: 14),
          Row(
            children: ['OpenWrt', 'pfSense', 'OPNSense'].map((p) {
              final isSel = _selectedPlatform == p;
              return Padding(
                padding: const EdgeInsets.only(right: 8.0),
                child: ChoiceChip(
                  label: Text(p),
                  selected: isSel,
                  onSelected: (_) => setState(() => _selectedPlatform = p),
                  selectedColor: palette.strictAccent,
                  labelStyle: TextStyle(
                    color: isSel ? Colors.white : palette.ink,
                    fontWeight: FontWeight.w600,
                    fontSize: 12,
                  ),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.black87,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    script,
                    style: const TextStyle(
                      color: Colors.lightGreenAccent,
                      fontFamily: 'monospace',
                      fontSize: 11,
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.copy_rounded, color: Colors.white70, size: 18),
                  tooltip: 'Copy Command',
                  onPressed: () => _copyCommand(context, script),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDeviceListSection(WabiSabiPalette palette, ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              'Household Devices (${_devices.length})',
              style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
            ),
            const Spacer(),
            Text(
              'Auto-Discovered via DHCP',
              style: TextStyle(color: palette.mutedInk, fontSize: 11),
            ),
          ],
        ),
        const SizedBox(height: 12),
        ..._devices.map((device) {
          return Container(
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: palette.canvas,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: palette.border),
            ),
            child: Row(
              children: [
                CircleAvatar(
                  backgroundColor: palette.surface,
                  child: Icon(_categoryIcon(device.deviceCategory), color: palette.ink, size: 20),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        device.hostname,
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                      ),
                      Text(
                        '${device.ipAddress} • ${device.macAddress}',
                        style: TextStyle(color: palette.mutedInk, fontSize: 11, fontFamily: 'monospace'),
                      ),
                    ],
                  ),
                ),
                InkWell(
                  onTap: () => _showProfileDialog(device),
                  borderRadius: BorderRadius.circular(20),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: palette.surface,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: palette.border),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          device.assignedProfile.replaceFirst('profile_', '').replaceAll('_', ' ').toUpperCase(),
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: palette.strictAccent,
                          ),
                        ),
                        const SizedBox(width: 4),
                        Icon(Icons.arrow_drop_down_rounded, size: 16, color: palette.strictAccent),
                      ],
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

  Widget _buildGuaranteeCard(WabiSabiPalette palette, ThemeData theme) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.shield_rounded, color: palette.strictAccent, size: 18),
              const SizedBox(width: 8),
              const Text(
                'Inviolable Anti-Bypass & Fail-Safe Laws',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            '• Rogue browser DoH (Cloudflare 1.1.1.1, Google 8.8.8.8) is blocked by firewall packet inspection.\n'
            '• Local LAN domain resolution (.lan, .local, router gateway) is guaranteed by fail-safe fallback.\n'
            '• Emergency VoIP dialing (911/112) is exempt from all bandwidth or filter drops.',
            style: TextStyle(color: palette.mutedInk, fontSize: 11, height: 1.4),
          ),
        ],
      ),
    );
  }
}
