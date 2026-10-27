import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../state_management/providers.dart';
import '../theme/wabi_sabi_theme.dart';
import '../ui_helpers.dart';

class SetupTab extends ConsumerWidget {
  const SetupTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final setup = ref.watch(setupProvider);
    final vpn = ref.watch(vpnProvider);
    final strictState = ref.watch(strictModeProvider);
    final blocker = ref.watch(blockerProvider);
    final palette = WabiSabiPalette.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        secCard(
          'Endpoints',
          'Configure your device, browser, or router to route DNS queries to your profile.',
          action: IconButton(
            icon: Icon(
              Icons.refresh_rounded,
              size: 18,
              color: setup.isLoading ? palette.mutedInk : palette.ink,
            ),
            tooltip: 'Refresh Endpoints',
            onPressed: setup.isLoading
                ? null
                : () {
                    ref.read(setupProvider.notifier).refresh();
                  },
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _endpointField(
                context,
                label: 'Profile ID',
                value: setup.profileId,
                subtitle: 'Unique identifier for your rules and policies',
                palette: palette,
              ),
              const SizedBox(height: 12),
              _endpointField(
                context,
                label: 'DNS-over-HTTPS (DoH)',
                value: setup.dohUrl,
                subtitle: 'Recommended for Chrome, Firefox, Safari & Windows 11',
                palette: palette,
              ),
              const SizedBox(height: 12),
              _endpointField(
                context,
                label: 'DNS-over-TLS (DoT) / Private DNS',
                value: setup.dotHostname,
                subtitle: 'Built into Android 9+ (Settings > Network > Private DNS) and Apple profiles',
                palette: palette,
              ),
              const SizedBox(height: 12),
              _endpointField(
                context,
                label: 'IPv4 Anycast',
                value: setup.ipv4Endpoints.join('\n'),
                subtitle: 'For home Wi-Fi routers and traditional DNS settings',
                palette: palette,
              ),
              const SizedBox(height: 12),
              _endpointField(
                context,
                label: 'IPv6 Anycast',
                value: setup.ipv6Endpoints.join('\n'),
                subtitle: 'For IPv6-native connections and dual-stack routers',
                palette: palette,
              ),
            ],
          ),
        ),
        secCard(
          'Linked IP',
          'Link your current external IP to apply profile filters to this network without device-level software.',
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: palette.canvas,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: palette.border),
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
                        Text(
                          'CURRENT NETWORK IP',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 0.5,
                            color: palette.mutedInk,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          setup.currentClientIp ?? 'Detecting client IP...',
                          style: TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: palette.ink,
                          ),
                        ),
                      ],
                    ),
                    _buildMatchBadge(setup, palette),
                  ],
                ),
                const SizedBox(height: 12),
                Divider(height: 1, thickness: 1, color: palette.border),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'PROFILE LINKED IP',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 0.5,
                              color: palette.mutedInk,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            setup.linkedIp,
                            style: TextStyle(
                              fontFamily: 'monospace',
                              fontSize: 13,
                              color: setup.linkedIp == 'No IP linked'
                                  ? palette.mutedInk
                                  : palette.ink,
                            ),
                          ),
                        ],
                      ),
                    ),
                    ElevatedButton(
                      onPressed: setup.isUpdatingIp
                          ? null
                          : () async {
                              final success = await ref
                                  .read(setupProvider.notifier)
                                  .updateLinkedIp();
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(
                                      success
                                          ? 'IP address linked successfully!'
                                          : 'Failed to link IP. Check network.',
                                    ),
                                    backgroundColor: palette.surface,
                                    duration: const Duration(seconds: 2),
                                  ),
                                );
                              }
                            },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: palette.ink,
                        foregroundColor: palette.canvas,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 8),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      child: setup.isUpdatingIp
                          ? SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor:
                                    AlwaysStoppedAnimation<Color>(palette.canvas),
                              ),
                            )
                          : Text(
                              setup.isMatched ? 'REFRESH LINK' : 'UPDATE IP',
                              style: const TextStyle(
                                  fontSize: 11, fontWeight: FontWeight.bold),
                            ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        secCard(
          'Local Device VPN (DNS Only)',
          'Route device DNS queries directly to FocusDNS via a local tun interface. Web, streaming, and game traffic bypasses the VPN completely.',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  color: palette.canvas,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: vpn.isRunning
                        ? palette.ink
                        : palette.border,
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Row(
                        children: [
                          Container(
                            width: 10,
                            height: 10,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: vpn.isRunning
                                  ? palette.ink
                                  : palette.mutedInk,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  vpn.isRunning ? 'VPN Active' : 'VPN Disconnected',
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.bold,
                                    color: palette.ink,
                                  ),
                                ),
                                Text(
                                  !vpn.isBackendReachable
                                      ? '⚠️ Backend Unreachable (Fail-Closed)'
                                      : vpn.isRunning
                                          ? 'Capturing 10.254.1.2/32'
                                          : 'DNS not redirected',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: !vpn.isBackendReachable
                                        ? palette.strictAccent
                                        : palette.mutedInk,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton(
                      onPressed: vpn.isPreparing
                          ? null
                          : () async {
                              if (vpn.isRunning) {
                                if (strictState.isStrict) {
                                  if (context.mounted) {
                                    final mins = (strictState.remainingSeconds / 60).ceil();
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text(
                                          strictState.remainingSeconds > 0
                                              ? '🔒 Strict Mode is active ($mins min remaining). Disconnecting VPN is locked.'
                                              : '🔒 Strict Mode is active. Disconnecting VPN is locked.',
                                        ),
                                        backgroundColor: palette.surface,
                                      ),
                                    );
                                  }
                                  return;
                                }
                                await ref.read(vpnProvider.notifier).stop();
                              } else {
                                await ref.read(vpnProvider.notifier).start(profileId: setup.profileId);
                              }
                            },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: vpn.isRunning
                            ? palette.strictAccent
                            : palette.ink,
                        foregroundColor: vpn.isRunning
                            ? Colors.white
                            : palette.canvas,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 8),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      child: Text(
                        vpn.isPreparing
                            ? '...'
                            : vpn.isRunning
                                ? 'DISCONNECT'
                                : 'ACTIVATE VPN',
                        style: const TextStyle(
                            fontSize: 11, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              Text(
                '💡 Tip: Android "Private DNS" must be set to "Off" or "Automatic". Force-stop apps after blocking to clear OS socket cache.',
                style: TextStyle(fontSize: 11, color: palette.mutedInk),
              ),
            ],
          ),
        ),
        secCard(
          'Native App Blocker (Accessibility)',
          'Monitors foreground app launches on device. Closes blocked apps instantly, prevents evasion with third-party VPNs, and guards system settings.',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  color: palette.canvas,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: blocker.isEnabled
                        ? palette.ink
                        : palette.border,
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Row(
                        children: [
                          Container(
                            width: 10,
                            height: 10,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: blocker.isEnabled
                                  ? palette.ink
                                  : palette.mutedInk,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  blocker.isEnabled ? 'App Blocker Active' : 'Blocker Disabled',
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.bold,
                                    color: palette.ink,
                                  ),
                                ),
                                Text(
                                  blocker.isEnabled
                                      ? 'Accessibility service connected'
                                      : 'Requires Accessibility permission',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: palette.mutedInk,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton(
                      onPressed: () {
                        ref.read(blockerProvider.notifier).openSettings();
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: blocker.isEnabled
                            ? palette.surface
                            : palette.ink,
                        foregroundColor: blocker.isEnabled
                            ? palette.ink
                            : palette.canvas,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                          side: blocker.isEnabled ? BorderSide(color: palette.border) : BorderSide.none,
                        ),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 8),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      child: Text(
                        blocker.isEnabled ? 'SETTINGS' : 'ENABLE BLOCKER',
                        style: const TextStyle(
                            fontSize: 11, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      '📱 Android 13+: If the toggle is greyed out, tap App Info > ⋮ > "Allow restricted settings" first.',
                      style: TextStyle(fontSize: 11, color: palette.mutedInk),
                    ),
                  ),
                  const SizedBox(width: 8),
                  TextButton(
                    onPressed: () {
                      ref.read(blockerProvider.notifier).openAppSettings();
                    },
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    child: Text(
                      'APP INFO',
                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: palette.ink),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildMatchBadge(SetupState setup, WabiSabiPalette palette) {
    if (setup.isMatched) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: palette.surface,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: palette.ink),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.check_circle_outline, size: 12, color: palette.ink),
            const SizedBox(width: 4),
            Text(
              'ACTIVE MATCH',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.bold,
                color: palette.ink,
              ),
            ),
          ],
        ),
      );
    }

    if (setup.linkedIp == 'No IP linked') {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: palette.surface,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: palette.border),
        ),
        child: Text(
          'UNLINKED',
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.bold,
            color: palette.mutedInk,
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: palette.border),
      ),
      child: Text(
        'DIFFERENT NETWORK',
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.bold,
          color: palette.mutedInk,
        ),
      ),
    );
  }

  Widget _endpointField(
    BuildContext context, {
    required String label,
    required String value,
    String? subtitle,
    required WabiSabiPalette palette,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                color: palette.mutedInk,
              ),
            ),
            IconButton(
              icon: Icon(Icons.copy_rounded, size: 14, color: palette.mutedInk),
              tooltip: 'Copy $label',
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
              splashRadius: 16,
              onPressed: () {
                Clipboard.setData(ClipboardData(text: value));
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('$label copied to clipboard'),
                    backgroundColor: palette.surface,
                    duration: const Duration(seconds: 1),
                  ),
                );
              },
            ),
          ],
        ),
        if (subtitle != null) ...[
          Text(
            subtitle,
            style: TextStyle(fontSize: 10, color: palette.subtleInk),
          ),
          const SizedBox(height: 4),
        ],
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: palette.canvas,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: palette.border),
          ),
          child: SelectableText(
            value,
            style: TextStyle(
              fontFamily: 'monospace',
              fontSize: 12.5,
              color: palette.ink,
            ),
          ),
        ),
      ],
    );
  }
}
