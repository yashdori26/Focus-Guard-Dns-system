import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../backend/macos_ebpf_service.dart';
import 'theme/wabi_sabi_theme.dart';

/// Screen displaying Linux eBPF/XDP kernel firewall and Asuswrt/DD-WRT router integrations.
class LinuxEbpfScreen extends StatefulWidget {
  const LinuxEbpfScreen({super.key});

  @override
  State<LinuxEbpfScreen> createState() => _LinuxEbpfScreenState();
}

class _LinuxEbpfScreenState extends State<LinuxEbpfScreen> with SingleTickerProviderStateMixin {
  EbpfRouterStatus? _status;
  bool _isLoading = true;
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadStatus();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadStatus() async {
    setState(() => _isLoading = true);
    final s = await FocusMacOsEbpfService.getEbpfStatus();
    if (mounted) {
      setState(() {
        _status = s;
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
        title: const Text('Linux eBPF & Router Drivers'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            onPressed: _loadStatus,
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
                  // Kernel eBPF Banner Card
                  _buildEbpfHeaderCard(palette, theme),
                  const SizedBox(height: 20),

                  // Conditional Uninstallation Card
                  _buildConditionalPostureCard(palette, theme),
                  const SizedBox(height: 20),

                  // Router Firmware Suite Tabs (Asuswrt-Merlin & DD-WRT)
                  _buildRouterSuiteSection(palette, theme),
                ],
              ),
            ),
    );
  }

  Widget _buildEbpfHeaderCard(WabiSabiPalette palette, ThemeData theme) {
    final s = _status;
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
                  color: Colors.orange.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Text(
                  'eBPF / XDP IN-KERNEL ACTIVE',
                  style: TextStyle(color: Colors.deepOrange, fontWeight: FontWeight.bold, fontSize: 11),
                ),
              ),
              const Spacer(),
              Text(
                'Interface: ${s.attachedInterface}',
                style: TextStyle(color: palette.mutedInk, fontSize: 12),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            'Zero-Overhead Linux Kernel Packet Filter',
            style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 4),
          Text(
            'Attaches to cgroup/connect4 and cgroup/skb_egress to intercept port 53 and drop rogue DoH/DoT.',
            style: TextStyle(color: palette.mutedInk, fontSize: 12),
          ),
          const Divider(height: 24),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _metricTile('Redirected', '${s.queriesRedirected}', palette),
              _metricTile('DoH Drops', '${s.dohDrops}', palette),
              _metricTile('DoT Drops', '${s.dotDrops}', palette),
              _metricTile('Rogue IPs', '${s.rogueIpsCount}', palette),
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
                      ? 'LOCKED: Kernel Map Teardown Forbidden (${mins.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')})'
                      : 'Normal Mode: Clean Map Unpinning Permitted',
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
                ? 'eBPF cgroup hooks cannot be detached while a focus lock or countdown timer is running. Attempted unpinning returns EPERM.'
                : 'Linux eBPF kernel hooks are idle and can be cleanly unloaded without side effects.',
            style: TextStyle(fontSize: 12, color: palette.mutedInk),
          ),
        ],
      ),
    );
  }

  Widget _buildRouterSuiteSection(WabiSabiPalette palette, ThemeData theme) {
    final asusCmd = FocusMacOsEbpfService.getAsuswrtInstallScript('profile_home_primary');
    final ddwrtCmd = FocusMacOsEbpfService.getDdWrtInstallScript('profile_home_primary');

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
            'Asuswrt-Merlin & DD-WRT Drivers',
            style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 4),
          Text(
            'Flashable router JFFS and NVRAM firewall scripts.',
            style: TextStyle(fontSize: 12, color: palette.mutedInk),
          ),
          const SizedBox(height: 14),
          TabBar(
            controller: _tabController,
            labelColor: palette.ink,
            unselectedLabelColor: palette.mutedInk,
            indicatorColor: palette.strictAccent,
            tabs: const [
              Tab(text: 'Asuswrt-Merlin (JFFS)'),
              Tab(text: 'DD-WRT (NVRAM)'),
            ],
          ),
          const SizedBox(height: 14),
          SizedBox(
            height: 130,
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildInstallTab(asusCmd, 'Asuswrt-Merlin curl command copied.', palette),
                _buildInstallTab(ddwrtCmd, 'DD-WRT nvram command copied.', palette),
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
            '• Auto-restarts dnsmasq & mounts anti-tamper watchdog',
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
