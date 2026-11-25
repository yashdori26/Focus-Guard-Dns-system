import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../backend/blocker_service.dart';
import '../../../backend/vpn_service.dart';
import '../../../services/auth_storage_service.dart';
import '../../../state_management/providers.dart';
import '../../auth/welcome_screen.dart';
import '../../theme/wabi_sabi_theme.dart';

/// Hinge-style delete flow: full screen, "Why are you leaving?" reasons,
/// then a final confirmation dialog. Deletion logic is FocusDNS's own.
class DeleteAccountScreen extends ConsumerStatefulWidget {
  const DeleteAccountScreen({super.key});

  @override
  ConsumerState<DeleteAccountScreen> createState() => _DeleteAccountScreenState();
}

class _DeleteAccountScreenState extends ConsumerState<DeleteAccountScreen> {
  static const List<String> _reasons = [
    'I no longer need FocusDNS',
    'Protection was too restrictive',
    'I am switching to another app',
    'Privacy concerns',
    'Something is not working',
    'Other',
  ];

  String? _selectedReason;
  bool _deleting = false;

  Future<void> _performDelete() async {
    setState(() => _deleting = true);
    await FocusDnsVpnManager.stopVpn();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('focus_onboarding_completed');
    await prefs.remove('focus_onboarding_name');
    await prefs.remove('focus_onboarding_step');
    await prefs.remove('focus_onboarding_cats');
    await prefs.remove('focus_perm_vpn');
    await prefs.remove('focus_perm_a11y');
    await prefs.remove('focus_perm_battery');
    try {
      await FocusDnsBlockerManager.putKv('focus_onboarding_completed', '0');
      await FocusDnsBlockerManager.putKv('focus_perm_vpn', '0');
      await FocusDnsBlockerManager.putKv('focus_perm_a11y', '0');
      await FocusDnsBlockerManager.putKv('focus_perm_battery', '0');
    } catch (_) {}
    await AuthStorageService.clearSession(preserveSavedCredentials: false);
    await AuthStorageService.clearAllProfiles();
    await ref.read(authProvider.notifier).logout();
    if (mounted) {
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const WelcomeScreen()),
        (route) => false,
      );
    }
  }

  void _confirm(WabiSabiPalette palette) {
    showDialog<void>(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: palette.surface,
        insetPadding: const EdgeInsets.symmetric(horizontal: 32),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        child: Padding(
          padding: const EdgeInsets.only(top: 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Column(
                  children: [
                    Text(
                      'Delete Account?',
                      textAlign: TextAlign.center,
                      style: GoogleFonts.fraunces(fontSize: 22, fontWeight: FontWeight.w700, color: palette.ink),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      'This permanently deletes your account, profiles, rules and on-device history, and stops DNS protection. This cannot be undone.',
                      textAlign: TextAlign.center,
                      style: GoogleFonts.inter(fontSize: 14, height: 1.45, color: palette.mutedInk),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 22),
              Divider(height: 1, thickness: 1, color: palette.hairlineSoft),
              SizedBox(
                width: double.infinity,
                height: 52,
                child: TextButton(
                  key: const Key('confirm_delete_account_button'),
                  onPressed: () {
                    Navigator.of(ctx).pop();
                    _performDelete();
                  },
                  child: Text('Delete Account & Data',
                      style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.w700, color: Colors.red.shade700)),
                ),
              ),
              Divider(height: 1, thickness: 1, color: palette.hairlineSoft),
              SizedBox(
                width: double.infinity,
                height: 52,
                child: TextButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  child: Text('Keep My Account',
                      style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.w600, color: palette.ink)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final themeMode = ref.watch(themeModeProvider);
    final palette = themeMode == ThemeMode.light ? WabiSabiPalette.light : WabiSabiPalette.dark;

    return Scaffold(
      backgroundColor: palette.canvas,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
              child: IconButton(
                key: const Key('delete_back_button'),
                onPressed: _deleting ? null : () => Navigator.of(context).pop(),
                icon: Icon(Icons.chevron_left_rounded, size: 32, color: palette.ink),
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Why are you leaving?',
                      style: GoogleFonts.fraunces(fontSize: 34, height: 1.12, fontWeight: FontWeight.w700, color: palette.ink, letterSpacing: -0.6),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      'Your answer stays on this device. Deleting removes your account, profiles, custom rules and query history.',
                      style: GoogleFonts.inter(fontSize: 14.5, height: 1.45, color: palette.mutedInk),
                    ),
                    const SizedBox(height: 22),
                    for (final r in _reasons) ...[
                      InkWell(
                        borderRadius: BorderRadius.circular(14),
                        onTap: () => setState(() => _selectedReason = r),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 160),
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: _selectedReason == r ? palette.ink : palette.border, width: _selectedReason == r ? 2 : 1.2),
                          ),
                          child: Row(
                            children: [
                              Expanded(child: Text(r, style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.w500, color: palette.ink))),
                              Container(
                                width: 22,
                                height: 22,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  border: Border.all(color: _selectedReason == r ? palette.ink : palette.border, width: 1.5),
                                  color: _selectedReason == r ? palette.ink : Colors.transparent,
                                ),
                                child: _selectedReason == r ? Icon(Icons.circle, size: 8, color: palette.canvas) : null,
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                    ],
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 20),
              child: SizedBox(
                width: double.infinity,
                height: 56,
                child: ElevatedButton(
                  key: const Key('delete_continue_button'),
                  onPressed: (_selectedReason == null || _deleting) ? null : () => _confirm(palette),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red.shade700,
                    foregroundColor: Colors.white,
                    disabledBackgroundColor: palette.border,
                    disabledForegroundColor: palette.mutedInk,
                    elevation: 0,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
                  ),
                  child: _deleting
                      ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.2, color: Colors.white))
                      : Text('Delete Account', style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.w700)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
