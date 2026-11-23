import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/enums.dart';
import '../../state_management/providers.dart';
import '../theme/wabi_sabi_theme.dart';
import '../ui_helpers.dart';
import '../mdm_shield_card.dart';

class SettingsTab extends ConsumerStatefulWidget {
  const SettingsTab({super.key});

  @override
  ConsumerState<SettingsTab> createState() => _SettingsTabState();
}

class _SettingsTabState extends ConsumerState<SettingsTab> {
  late TextEditingController _nameController;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(
      text: ref.read(settingsProvider).profileName,
    );
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider);
    final themeMode = ref.watch(themeModeProvider);
    final auth = ref.watch(authProvider);
    final palette = WabiSabiPalette.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // DEVICE ADMINISTRATOR & ANTI-UNINSTALL SHIELD
        const MdmShieldCard(),
        const SizedBox(height: 16),

        // THEME MODE SWITCHER
        secCard(
          'Appearance',
          'Switch between Warm Stone Paper (Light) and Charcoal Night (Dark).',
          child: Row(
            children: [
              Expanded(
                child: GestureDetector(
                  onTap: () => ref.read(themeModeProvider.notifier).setMode(ThemeMode.dark),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    decoration: BoxDecoration(
                      color: themeMode == ThemeMode.dark ? palette.ink : palette.canvas,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: palette.border),
                    ),
                    child: Center(
                      child: Text(
                        'Charcoal Dark',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: themeMode == ThemeMode.dark ? palette.canvas : palette.ink,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: GestureDetector(
                  onTap: () => ref.read(themeModeProvider.notifier).setMode(ThemeMode.light),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    decoration: BoxDecoration(
                      color: themeMode == ThemeMode.light ? palette.ink : palette.canvas,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: palette.border),
                    ),
                    child: Center(
                      child: Text(
                        'Stone Light',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: themeMode == ThemeMode.light ? palette.canvas : palette.ink,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),

        // EMAIL VERIFICATION (Requested by User)
        secCard(
          'Email Verification',
          'Verify your account email to protect DNS profiles, sync cloud rules and enable security recovery.',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: auth.isEmailVerified
                          ? palette.safeAccent.withOpacity(0.12)
                          : palette.strictAccent.withOpacity(0.12),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      auth.isEmailVerified
                          ? Icons.mark_email_read_rounded
                          : Icons.mail_outline_rounded,
                      size: 20,
                      color: auth.isEmailVerified
                          ? palette.safeAccent
                          : palette.strictAccent,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          auth.email ?? 'user@focusdns.net',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: palette.ink,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          auth.isEmailVerified ? 'Verified account' : 'Pending verification',
                          style: TextStyle(
                            fontSize: 11,
                            color: palette.mutedInk,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: auth.isEmailVerified
                          ? palette.safeAccent.withOpacity(0.12)
                          : palette.strictAccent.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                        color: auth.isEmailVerified
                            ? palette.safeAccent.withOpacity(0.3)
                            : palette.strictAccent.withOpacity(0.3),
                      ),
                    ),
                    child: Text(
                      auth.isEmailVerified ? 'VERIFIED ✓' : 'UNVERIFIED',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.8,
                        color: auth.isEmailVerified ? palette.safeAccent : palette.strictAccent,
                      ),
                    ),
                  ),
                ],
              ),
              if (!auth.isEmailVerified) ...[
                const SizedBox(height: 14),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    key: const Key('verify_email_settings_button'),
                    onPressed: () => _openVerificationModal(context, palette, auth),
                    icon: const Icon(Icons.verified_user_outlined, size: 16),
                    label: const Text('Verify Email Address', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: palette.ink,
                      foregroundColor: palette.canvas,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      elevation: 0,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),

        // PROFILE NAME
        secCard(
          'Profile Name',
          'Give your profile an identifiable name across your devices.',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: _nameController,
                style: TextStyle(fontSize: 14, color: palette.ink),
                onChanged: (val) {
                  ref.read(settingsProvider.notifier).updateProfileName(val);
                },
                decoration: InputDecoration(
                  filled: true,
                  fillColor: palette.canvas,
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(color: palette.border),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(color: palette.border),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(color: palette.ink),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                key: const Key('delete_all_profiles_button'),
                onPressed: () async {
                  await ref.read(authProvider.notifier).deleteAllProfiles();
                  _nameController.text = 'Local Shield';
                  ref.read(settingsProvider.notifier).updateProfileName('Local Shield');
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('All profiles deleted. Running in pure local mode.')),
                    );
                  }
                },
                icon: Icon(Icons.delete_sweep_rounded, size: 16, color: palette.strictAccent),
                label: Text('Delete All Profiles & Reset', style: TextStyle(color: palette.strictAccent, fontSize: 12, fontWeight: FontWeight.bold)),
                style: OutlinedButton.styleFrom(
                  side: BorderSide(color: palette.strictAccent.withOpacity(0.4)),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                ),
              ),
            ],
          ),
        ),

        // LOG RETENTION
        secCard(
          'Log Retention',
          'Choose how long DNS query logs are stored on FocusDNS servers.',
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            decoration: BoxDecoration(
              color: palette.canvas,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: palette.border),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: settings.logRetention,
                isExpanded: true,
                dropdownColor: palette.surface,
                style: TextStyle(fontSize: 13, color: palette.ink),
                icon: Icon(Icons.arrow_drop_down, color: palette.mutedInk),
                items: const [
                  DropdownMenuItem(value: '1 hour', child: Text('1 hour')),
                  DropdownMenuItem(value: '1 day', child: Text('1 day')),
                  DropdownMenuItem(value: '1 week', child: Text('1 week')),
                  DropdownMenuItem(value: '1 month', child: Text('1 month')),
                ],
                onChanged: (val) {
                  if (val != null) {
                    ref.read(settingsProvider.notifier).updateLogRetention(val);
                  }
                },
              ),
            ),
          ),
        ),

        // WEB3 DOMAINS
        secCard(
          'Web3 Domains',
          'Resolve decentralized blockchain domains natively without browser extensions.',
          child: Column(
            children: [
              switchRow(
                'Ethereum Name Service (ENS)',
                'Resolve .eth blockchain domains',
                settings.web3[Web3Feature.ens] ?? true,
                (val) => ref
                    .read(settingsProvider.notifier)
                    .toggleWeb3(Web3Feature.ens, val),
              ),
              Divider(color: palette.border, height: 16),
              switchRow(
                'Unstoppable Domains',
                'Resolve .crypto, .nft, .x, .wallet domains',
                settings.web3[Web3Feature.unstoppable] ?? true,
                (val) => ref
                    .read(settingsProvider.notifier)
                    .toggleWeb3(Web3Feature.unstoppable, val),
              ),
              Divider(color: palette.border, height: 16),
              switchRow(
                'IPFS Gateway',
                'Resolve decentralized IPFS web content natively',
                settings.web3[Web3Feature.ipfs] ?? true,
                (val) => ref
                    .read(settingsProvider.notifier)
                    .toggleWeb3(Web3Feature.ipfs, val),
              ),
            ],
          ),
        ),
      ],
    );
  }

  void _openVerificationModal(BuildContext context, WabiSabiPalette palette, AuthState auth) {
    final otpController = TextEditingController();
    String? localError;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: palette.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (modalCtx) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            final emailDisplay = auth.email ?? 'user@focusdns.net';
            final isLoading = ref.watch(authProvider).isLoading;

            return Padding(
              padding: EdgeInsets.only(
                left: 24,
                right: 24,
                top: 24,
                bottom: MediaQuery.of(modalCtx).viewInsets.bottom + 24,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Verify Email Address',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: palette.ink,
                        ),
                      ),
                      IconButton(
                        icon: Icon(Icons.close, color: palette.mutedInk, size: 20),
                        onPressed: () => Navigator.pop(modalCtx),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Enter the 4-digit code to verify $emailDisplay.',
                    style: TextStyle(fontSize: 13, color: palette.mutedInk),
                  ),
                  const SizedBox(height: 18),

                  if (localError != null) ...[
                    Container(
                      padding: const EdgeInsets.all(10),
                      margin: const EdgeInsets.only(bottom: 14),
                      decoration: BoxDecoration(
                        color: palette.strictAccent.withOpacity(0.08),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: palette.strictAccent.withOpacity(0.3)),
                      ),
                      child: Text(
                        localError!,
                        style: TextStyle(fontSize: 12, color: palette.strictAccent, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],

                  TextFormField(
                    key: const Key('settings_otp_input'),
                    controller: otpController,
                    keyboardType: TextInputType.number,
                    maxLength: 4,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 10.0,
                      color: palette.ink,
                    ),
                    decoration: InputDecoration(
                      counterText: '',
                      filled: true,
                      fillColor: palette.canvas,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: palette.border)),
                      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: palette.border)),
                      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: palette.ink, width: 1.5)),
                    ),
                  ),
                  const SizedBox(height: 12),

                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      InkWell(
                        key: const Key('settings_otp_autofill'),
                        onTap: () {
                          otpController.text = auth.devOtp ?? '1234';
                          setModalState(() => localError = null);
                        },
                        borderRadius: BorderRadius.circular(6),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(
                            color: palette.canvas,
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: palette.border),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.bolt_rounded, size: 14, color: palette.accent),
                              const SizedBox(width: 4),
                              Text('Auto-Fill (1234)', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: palette.ink)),
                            ],
                          ),
                        ),
                      ),
                      TextButton(
                        key: const Key('settings_otp_resend'),
                        onPressed: () async {
                          await ref.read(authProvider.notifier).sendEmailVerificationInSettings();
                          setModalState(() => localError = null);
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Verification code sent!')),
                          );
                        },
                        child: Text('Resend Code', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: palette.ink)),
                      ),
                    ],
                  ),

                  const SizedBox(height: 20),

                  SizedBox(
                    width: double.infinity,
                    height: 46,
                    child: ElevatedButton(
                      key: const Key('settings_otp_submit'),
                      onPressed: isLoading
                          ? null
                          : () async {
                              final code = otpController.text.trim();
                              if (code.length != 4) {
                                setModalState(() => localError = 'Please enter the 4-digit code.');
                                return;
                              }
                              final res = await ref.read(authProvider.notifier).verifyEmailInSettings(code);
                              if (res['success'] == true) {
                                Navigator.pop(modalCtx);
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('🎉 Email verified successfully!')),
                                );
                              } else {
                                setModalState(() => localError = res['error']?.toString() ?? 'Invalid code.');
                              }
                            },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: palette.ink,
                        foregroundColor: palette.canvas,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                      child: isLoading
                          ? SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: palette.canvas))
                          : const Text('Verify & Save', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}
