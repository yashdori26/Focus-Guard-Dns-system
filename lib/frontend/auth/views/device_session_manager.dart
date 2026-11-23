import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../state_management/providers.dart';
import '../../theme/wabi_sabi_theme.dart';
import 'auth_audit_log_view.dart';
import 'auth_recovery_vault_view.dart';

class DeviceSessionManagerView extends ConsumerStatefulWidget {
  const DeviceSessionManagerView({super.key});

  @override
  ConsumerState<DeviceSessionManagerView> createState() => _DeviceSessionManagerViewState();
}

class _DeviceSessionManagerViewState extends ConsumerState<DeviceSessionManagerView> {
  List<Map<String, dynamic>> _sessions = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadSessions();
  }

  Future<void> _loadSessions() async {
    setState(() => _isLoading = true);
    final auth = ref.read(authProvider);
    final client = ref.read(apiClientProvider);

    if (auth.phoneNumber != null) {
      try {
        final res = await client.getUserProfiles(auth.phoneNumber!);
        // Also fetch active sessions from router
        if (mounted) {
          setState(() {
            _sessions = [
              {
                'device': 'This Web Client (Current)',
                'ip': auth.detectedIp,
                'location': '${auth.detectedFlag} ${auth.detectedCountryCode}',
                'is_current': true,
                'last_active': 'Active now',
              },
            ];
            _isLoading = false;
          });
        }
      } catch (_) {
        if (mounted) setState(() => _isLoading = false);
      }
    } else {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = WabiSabiPalette.of(context);
    final auth = ref.watch(authProvider);

    return Scaffold(
      backgroundColor: palette.canvas,
      appBar: AppBar(
        title: const Text('Device Sessions & Security', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        backgroundColor: palette.surface,
        foregroundColor: palette.ink,
        elevation: 0,
      ),
      body: SafeArea(
        child: _isLoading
            ? Center(child: CircularProgressIndicator(color: palette.ink))
            : ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  Text(
                    'AUTHENTICATED PHONE',
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 0.8, color: palette.mutedInk),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: palette.surface,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: palette.border),
                    ),
                    child: Row(
                      children: [
                        Text(auth.detectedFlag, style: const TextStyle(fontSize: 22)),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                auth.phoneNumber ?? 'No phone linked',
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.bold,
                                  color: palette.ink,
                                  fontFamily: 'JetBrains Mono',
                                ),
                              ),
                              Text(
                                'Cloud Multi-Profile Sync Enabled',
                                style: TextStyle(fontSize: 11, color: palette.mutedInk),
                              ),
                            ],
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: const Color(0xFF2ECC71).withOpacity(0.12),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: const Text(
                            'Active',
                            style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF27AE60)),
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 24),

                  Text(
                    'LOGGED IN DEVICES',
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 0.8, color: palette.mutedInk),
                  ),
                  const SizedBox(height: 8),

                  ..._sessions.map((s) {
                    final isCurrent = s['is_current'] == true;
                    return Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: palette.surface,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: isCurrent ? palette.ink.withOpacity(0.5) : palette.border,
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.devices_rounded, size: 20, color: palette.ink),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Text(
                                      s['device']?.toString() ?? '',
                                      style: TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.bold,
                                        color: palette.ink,
                                      ),
                                    ),
                                    if (isCurrent) ...[
                                      const SizedBox(width: 6),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                                        decoration: BoxDecoration(
                                          color: palette.ink.withOpacity(0.08),
                                          borderRadius: BorderRadius.circular(4),
                                        ),
                                        child: Text(
                                          'This Device',
                                          style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: palette.ink),
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  'IP: ${s['ip']} • ${s['location']} • ${s['last_active']}',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: palette.mutedInk,
                                    fontFamily: 'JetBrains Mono',
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    );
                  }),

                  const SizedBox(height: 20),

                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () {
                            final client = ref.read(apiClientProvider);
                            final phone = auth.phoneNumber;
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => AuthAuditLogView(
                                  apiClient: client,
                                  phoneNumber: phone,
                                ),
                              ),
                            );
                          },
                          icon: Icon(Icons.history_edu_rounded, size: 16, color: palette.ink),
                          label: Text('Forensic Audit', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: palette.ink)),
                          style: OutlinedButton.styleFrom(
                            side: BorderSide(color: palette.border),
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () {
                            final phone = auth.phoneNumber;
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => AuthRecoveryVaultView(
                                  phoneNumber: phone ?? '+1 (555) 019-2834',
                                ),
                              ),
                            );
                          },
                          icon: Icon(Icons.vpn_key_rounded, size: 16, color: palette.ink),
                          label: Text('Recovery Keys', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: palette.ink)),
                          style: OutlinedButton.styleFrom(
                            side: BorderSide(color: palette.border),
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 24),

                  OutlinedButton.icon(
                    onPressed: () async {
                      await ref.read(authProvider.notifier).logout();
                      if (context.mounted) {
                        Navigator.pop(context);
                      }
                    },
                    icon: const Icon(Icons.logout_rounded, size: 16),
                    label: const Text('Sign Out from This Device'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFFD32F2F),
                      side: const BorderSide(color: Color(0xFFE05252)),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}
