import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../backend/macos_ebpf_service.dart';
import 'theme/wabi_sabi_theme.dart';

/// Screen displaying macOS NetworkExtension (DNSProxy & Content Filter) posture.
class MacOsProxyScreen extends StatefulWidget {
  const MacOsProxyScreen({super.key});

  @override
  State<MacOsProxyScreen> createState() => _MacOsProxyScreenState();
}

class _MacOsProxyScreenState extends State<MacOsProxyScreen> {
  MacOsExtensionStatus? _status;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadStatus();
  }

  Future<void> _loadStatus() async {
    setState(() => _isLoading = true);
    final s = await FocusMacOsEbpfService.getMacExtensionStatus();
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
        title: const Text('macOS Network Extensions'),
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
                  // Extension Health Card
                  _buildExtensionHeaderCard(palette, theme),
                  const SizedBox(height: 20),

                  // Conditional Uninstallation Posture
                  _buildConditionalPostureCard(palette, theme),
                  const SizedBox(height: 20),

                  // Apple Keychain & Secure Enclave Section
                  _buildKeychainSection(palette, theme),
                  const SizedBox(height: 20),

                  // MDM Profile Download & CLI Installation
                  _buildMobileConfigSection(palette, theme),
                ],
              ),
            ),
    );
  }

  Widget _buildExtensionHeaderCard(WabiSabiPalette palette, ThemeData theme) {
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
                  color: Colors.blue.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Text(
                  'SYSTEM EXTENSION ACTIVE',
                  style: TextStyle(color: Colors.blue, fontWeight: FontWeight.bold, fontSize: 11),
                ),
              ),
              const Spacer(),
              Text(
                'macOS Ventura / Sonoma / Sequoia',
                style: TextStyle(color: palette.mutedInk, fontSize: 12),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            'System-Wide NEDNSProxy & Content Filter',
            style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 4),
          Text(
            'Captures all operating system DNS flows and terminates rogue DoH/DoT bypass sockets.',
            style: TextStyle(color: palette.mutedInk, fontSize: 12),
          ),
          const Divider(height: 24),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _metricTile('UDP Flows', '${s.totalUdpFlows}', palette),
              _metricTile('TCP Flows', '${s.totalTcpFlows}', palette),
              _metricTile('Bypasses Blocked', '${s.blockedBypasses}', palette),
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
                      ? 'LOCKED: Active Focus Session (${mins.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')})'
                      : 'Normal Mode: Clean Uninstallation Permitted',
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
                ? 'System Extension and MDM profile removal are cryptographically disallowed (PayloadRemovalDisallowed = True). Attempted launchctl unload will be rejected.'
                : 'FocusGuard DNS protection is idle. You may stop the system extension or remove profiles with 0 friction.',
            style: TextStyle(fontSize: 12, color: palette.mutedInk),
          ),
        ],
      ),
    );
  }

  Widget _buildKeychainSection(WabiSabiPalette palette, ThemeData theme) {
    final s = _status;
    if (s == null) return const SizedBox.shrink();

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
          Row(
            children: [
              Icon(Icons.vpn_key_rounded, size: 20, color: palette.ink),
              const SizedBox(width: 8),
              Text(
                'Apple Keychain & Secure Enclave',
                style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
              ),
              const Spacer(),
              if (s.isKeychainTokenSecured)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.green.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Text(
                    'HARDWARE SECURED',
                    style: TextStyle(color: Colors.green, fontSize: 10, fontWeight: FontWeight.bold),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Device authentication tokens and policy signing keys are isolated in the Apple Silicon Secure Enclave and cannot be extracted from user-space memory.',
            style: TextStyle(fontSize: 12, color: palette.mutedInk),
          ),
        ],
      ),
    );
  }

  Widget _buildMobileConfigSection(WabiSabiPalette palette, ThemeData theme) {
    const installCmd = 'sudo profiles install -path FocusGuard.mobileconfig';

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
            '1-Click MDM Profile Deployment',
            style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 6),
          Text(
            'Installs pre-approved system extension entitlements across all macOS user accounts.',
            style: TextStyle(fontSize: 12, color: palette.mutedInk),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: palette.surface,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: palette.border),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    installCmd,
                    style: TextStyle(fontFamily: 'monospace', fontSize: 12, color: palette.ink),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.copy_rounded, size: 18),
                  onPressed: () => _copyCommand(context, installCmd, 'macOS profile command copied to clipboard.'),
                  tooltip: 'Copy Command',
                ),
              ],
            ),
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
