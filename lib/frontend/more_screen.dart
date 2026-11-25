import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../backend/blocker_service.dart';
import '../backend/mdm_service.dart';
import '../backend/vpn_service.dart';
import '../models/enums.dart';
import '../services/auth_storage_service.dart';
import '../state_management/providers.dart';
import 'auth/email_auth_screen.dart';
import 'profile_settings_sheet.dart';
import 'profile_switcher_sheet.dart';
import 'screens/onboarding/onboarding_screen.dart';
import 'tabs/allowlist_tab.dart';
import 'tabs/denylist_tab.dart';
import 'theme/wabi_sabi_theme.dart';

/// Clean, tactile, and decluttered "More" screen with inline toggles,
/// top Profile Card, and Hinge-style Log Out & Delete Account controls.
class MoreTab extends ConsumerStatefulWidget {
  final WabiSabiPalette palette;
  const MoreTab({super.key, required this.palette});

  @override
  ConsumerState<MoreTab> createState() => _MoreTabState();
}

class _MoreTabState extends ConsumerState<MoreTab> with WidgetsBindingObserver {
  bool _antiVpnBypass = true;
  bool _youtubeShorts = false;
  bool _instagramReels = false;
  bool _isAccessibilityActive = false;
  bool _isDeviceAdminActive = false;
  bool _isBatteryImmune = false;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadLocalStates();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _loadLocalStates();
    }
  }

  Future<void> _loadLocalStates() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final antiVpn = prefs.getBool('focus_anti_vpn_bypass') ?? true;
      final yt = prefs.getBool('focus_block_yt_shorts') ?? false;
      final ig = prefs.getBool('focus_block_ig_reels') ?? false;

      final acc = await FocusDnsBlockerManager.isAccessibilityServiceEnabled();
      final admin = await FocusMdmManager.isDeviceAdminActive();
      final battery = await FocusDnsBlockerManager.isBatteryOptimizationIgnored();

      if (mounted) {
        setState(() {
          _antiVpnBypass = antiVpn;
          _youtubeShorts = yt;
          _instagramReels = ig;
          _isAccessibilityActive = acc;
          _isDeviceAdminActive = admin;
          _isBatteryImmune = battery;
          _isLoading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showStrictLockWarning() {
    final strictState = ref.read(strictModeProvider);
    final mins = (strictState.remainingSeconds / 60).ceil();
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          strictState.remainingSeconds > 0
              ? '🔒 Strict Mode is active ($mins min remaining). Cannot modify filters.'
              : '🔒 Strict Mode is active. Settings are locked until focus timer expires.',
          style: GoogleFonts.inter(fontSize: 12.5, color: Colors.white),
        ),
        backgroundColor: const Color(0xFF1E1E22),
        duration: const Duration(seconds: 3),
      ),
    );
  }

  Future<void> _toggleAntiVpn(bool value) async {
    final strictState = ref.read(strictModeProvider);
    if (!value && strictState.isStrict && strictState.remainingSeconds > 0) {
      _showStrictLockWarning();
      return;
    }
    setState(() => _antiVpnBypass = value);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('focus_anti_vpn_bypass', value);
    await FocusDnsVpnManager.updateSecuritySettings(antiVpnBypass: value);
  }

  Future<void> _toggleYoutubeShorts(bool value) async {
    final strictState = ref.read(strictModeProvider);
    if (!value && strictState.isStrict && strictState.remainingSeconds > 0) {
      _showStrictLockWarning();
      return;
    }
    setState(() => _youtubeShorts = value);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('focus_block_yt_shorts', value);
    await FocusDnsBlockerManager.setFeedFilters(
      instagramReels: _instagramReels,
      youtubeShorts: value,
    );
  }

  Future<void> _toggleInstagramReels(bool value) async {
    final strictState = ref.read(strictModeProvider);
    if (!value && strictState.isStrict && strictState.remainingSeconds > 0) {
      _showStrictLockWarning();
      return;
    }
    setState(() => _instagramReels = value);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('focus_block_ig_reels', value);
    await FocusDnsBlockerManager.setFeedFilters(
      instagramReels: value,
      youtubeShorts: _youtubeShorts,
    );
  }

  Future<void> _toggleAccessibility(bool value) async {
    if (value) {
      final enabled = await FocusDnsBlockerManager.isAccessibilityServiceEnabled();
      if (!enabled) {
        await FocusDnsBlockerManager.openAccessibilitySettings();
      }
      setState(() => _isAccessibilityActive = true);
    } else {
      final strictState = ref.read(strictModeProvider);
      if (strictState.isStrict && strictState.remainingSeconds > 0) {
        _showStrictLockWarning();
        return;
      }
      await FocusDnsBlockerManager.openAccessibilitySettings();
      setState(() => _isAccessibilityActive = false);
    }
  }

  Future<void> _toggleDeviceAdmin(bool value) async {
    if (value) {
      await FocusMdmManager.requestDeviceAdmin();
      final active = await FocusMdmManager.isDeviceAdminActive();
      setState(() => _isDeviceAdminActive = active);
    } else {
      final strictState = ref.read(strictModeProvider);
      // Tamper-Proof Lock is ONLY active during strict mode focus countdown sessions
      if (strictState.isStrict && strictState.remainingSeconds > 0) {
        _showStrictLockWarning();
        return;
      }
      final success = await FocusMdmManager.deactivateDeviceAdmin();
      final active = await FocusMdmManager.isDeviceAdminActive();
      setState(() => _isDeviceAdminActive = active);
      if (!success && active) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Deactivate Device Admin in Android Security settings.'),
            duration: Duration(seconds: 2),
          ),
        );
      }
    }
  }

  Future<void> _toggleBatteryImmunity(bool value) async {
    if (value) {
      await FocusDnsBlockerManager.requestIgnoreBatteryOptimizations();
      final immune = await FocusDnsBlockerManager.isBatteryOptimizationIgnored();
      setState(() => _isBatteryImmune = immune);
    }
  }

  void _openCustomRulesSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: widget.palette.canvas,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return DefaultTabController(
          length: 2,
          child: SizedBox(
            height: MediaQuery.of(context).size.height * 0.75,
            child: Column(
              children: [
                const SizedBox(height: 12),
                Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: widget.palette.border,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(height: 8),
                TabBar(
                  labelColor: widget.palette.ink,
                  unselectedLabelColor: widget.palette.mutedInk,
                  indicatorColor: widget.palette.ink,
                  indicatorWeight: 2.5,
                  labelStyle: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w700),
                  unselectedLabelStyle: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w500),
                  tabs: const [
                    Tab(text: 'Allowlist (Bypass)'),
                    Tab(text: 'Denylist (Blocked)'),
                  ],
                ),
                Divider(color: widget.palette.border, height: 1),
                const Expanded(
                  child: TabBarView(
                    children: [
                      SingleChildScrollView(padding: EdgeInsets.all(16), child: AllowlistTab()),
                      SingleChildScrollView(padding: EdgeInsets.all(16), child: DenylistTab()),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _clearLogs() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: widget.palette.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          'Clear Query Logs',
          style: GoogleFonts.fraunces(
            fontSize: 20,
            fontWeight: FontWeight.w700,
            color: widget.palette.ink,
          ),
        ),
        content: Text(
          'Delete all local DNS query history from this device? This action cannot be undone.',
          style: GoogleFonts.inter(
            fontSize: 13,
            color: widget.palette.mutedInk,
            height: 1.4,
          ),
        ),
        actionsPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(
              'Cancel',
              style: GoogleFonts.inter(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: widget.palette.mutedInk,
              ),
            ),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: widget.palette.strictAccent,
              foregroundColor: Colors.white,
              elevation: 0,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            child: Text(
              'Clear Logs',
              style: GoogleFonts.inter(
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await FocusDnsVpnManager.clearDbLogs();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('DNS query logs cleared successfully.')),
        );
      }
    }
  }

  void _showLogoutModal(BuildContext context, WabiSabiPalette palette) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) {
        return Container(
          decoration: BoxDecoration(
            color: palette.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            border: Border.all(color: palette.border, width: 1.0),
          ),
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: palette.border,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 24),
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: palette.canvas,
                  shape: BoxShape.circle,
                  border: Border.all(color: palette.border),
                ),
                child: Icon(Icons.logout_rounded, size: 26, color: palette.ink),
              ),
              const SizedBox(height: 16),
              Text(
                'Log out of FocusDNS?',
                style: GoogleFonts.fraunces(
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  color: palette.ink,
                  letterSpacing: -0.3,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Are you sure you want to log out? Your local preferences, rules, and blocker settings will remain safely saved on this device.',
                textAlign: TextAlign.center,
                style: GoogleFonts.inter(
                  fontSize: 13,
                  color: palette.mutedInk,
                  height: 1.45,
                ),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton(
                  key: const Key('confirm_logout_button'),
                  onPressed: () async {
                    Navigator.of(ctx).pop();
                    await ref.read(authProvider.notifier).logout();
                    if (context.mounted) {
                      Navigator.of(context).pushAndRemoveUntil(
                        MaterialPageRoute(builder: (_) => const EmailAuthScreen()),
                        (route) => false,
                      );
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: palette.ink,
                    foregroundColor: palette.canvas,
                    elevation: 0,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: Text(
                    'Log Out',
                    style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: OutlinedButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: palette.ink,
                    side: BorderSide(color: palette.border),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: Text(
                    'Cancel',
                    style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w600),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  void _showDeleteAccountModal(BuildContext context, WabiSabiPalette palette) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) {
        return Container(
          decoration: BoxDecoration(
            color: palette.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            border: Border.all(color: palette.border, width: 1.0),
          ),
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: palette.border,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 24),
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: Colors.red.withOpacity(0.1),
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.red.withOpacity(0.3)),
                ),
                child: const Icon(Icons.delete_forever_rounded, size: 28, color: Colors.red),
              ),
              const SizedBox(height: 16),
              Text(
                'Delete Account?',
                style: GoogleFonts.fraunces(
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  color: palette.ink,
                  letterSpacing: -0.3,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'This will permanently delete your account credentials, purge all saved profiles, stop the VPN tunnel, and reset on-device configurations.',
                textAlign: TextAlign.center,
                style: GoogleFonts.inter(
                  fontSize: 13,
                  color: palette.mutedInk,
                  height: 1.45,
                ),
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: palette.canvas,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: palette.border),
                ),
                child: Column(
                  children: [
                    _warningBullet('Wipes all local credentials & profiles', palette),
                    const SizedBox(height: 6),
                    _warningBullet('Stops active DNS protection & VPN', palette),
                    const SizedBox(height: 6),
                    _warningBullet('Clears on-device query history & custom rules', palette),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton(
                  key: const Key('confirm_delete_account_button'),
                  onPressed: () async {
                    Navigator.of(ctx).pop();
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
                    if (context.mounted) {
                      Navigator.of(context).pushAndRemoveUntil(
                        MaterialPageRoute(builder: (_) => const EmailAuthScreen()),
                        (route) => false,
                      );
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red.shade700,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: Text(
                    'Delete Account & Data',
                    style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: OutlinedButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: palette.ink,
                    side: BorderSide(color: palette.border),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: Text(
                    'Keep My Account',
                    style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w600),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _warningBullet(String text, WabiSabiPalette palette) {
    return Row(
      children: [
        const Icon(Icons.close_rounded, size: 14, color: Colors.red),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: GoogleFonts.inter(fontSize: 12, color: palette.ink, fontWeight: FontWeight.w500),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final palette = widget.palette;
    final securityState = ref.watch(securityProvider);
    final privacyState = ref.watch(privacyProvider);
    final strictState = ref.watch(strictModeProvider);
    final themeMode = ref.watch(themeModeProvider);
    final auth = ref.watch(authProvider);
    final settings = ref.watch(settingsProvider);
    final isProtectionOn = ref.watch(protectionProvider);

    final displayProfileName = auth.activeProfileName.isNotEmpty
        ? auth.activeProfileName
        : settings.profileName;

    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Top Profile Card
          GestureDetector(
            key: const Key('header_profile_pill'),
            behavior: HitTestBehavior.opaque,
            onTap: () {
              showModalBottomSheet(
                context: context,
                isScrollControlled: true,
                backgroundColor: Colors.transparent,
                builder: (context) => const ProfileSwitcherSheet(),
              );
            },
            onLongPress: () {
              showModalBottomSheet(
                context: context,
                isScrollControlled: true,
                backgroundColor: Colors.transparent,
                builder: (context) => const AllProfileSettingsSheet(),
              );
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              decoration: BoxDecoration(
                color: palette.surface,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: palette.border, width: 1.0),
              ),
              child: Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: palette.canvas,
                      shape: BoxShape.circle,
                      border: Border.all(color: palette.border, width: 1.0),
                    ),
                    child: Center(
                      child: Text(
                        auth.isLoggedIn && auth.detectedFlag.isNotEmpty
                            ? auth.detectedFlag
                            : '🛡️',
                        style: const TextStyle(fontSize: 18),
                      ),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              width: 7,
                              height: 7,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: isProtectionOn ? palette.safeAccent : palette.mutedInk,
                              ),
                            ),
                            const SizedBox(width: 6),
                            Text(
                              isProtectionOn ? 'PROTECTED' : 'PAUSED',
                              style: GoogleFonts.jetBrainsMono(
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 0.8,
                                color: isProtectionOn ? palette.safeAccent : palette.mutedInk,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text(
                          displayProfileName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.inter(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: palette.ink,
                            letterSpacing: -0.2,
                          ),
                        ),
                        if (auth.isLoggedIn && auth.email != null)
                          Text(
                            auth.email!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.inter(
                              fontSize: 12,
                              color: palette.mutedInk,
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: palette.canvas,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: palette.border, width: 0.8),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'Switch',
                          style: GoogleFonts.inter(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: palette.ink,
                          ),
                        ),
                        const SizedBox(width: 4),
                        Icon(Icons.unfold_more_rounded, size: 14, color: palette.mutedInk),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 20),

          // Section 1: Network & Filtering
          _sectionHeader('NETWORK & FILTERING', palette),
          _cardGroup(
            palette: palette,
            children: [
              _toggleRow(
                palette: palette,
                icon: Icons.shield_rounded,
                iconColor: palette.safeAccent,
                title: 'Threat Shield',
                subtitle: 'Blocks known malicious websites, phishing, and scam links.',
                value: securityState[SecurityFeature.threatIntel] ?? true,
                onChanged: (val) {
                  if (!val && strictState.isStrict && strictState.remainingSeconds > 0) {
                    _showStrictLockWarning();
                    return;
                  }
                  ref.read(securityProvider.notifier).toggle(SecurityFeature.threatIntel, val);
                },
              ),
              _divider(palette),
              _toggleRow(
                palette: palette,
                icon: Icons.filter_vintage_rounded,
                iconColor: palette.ink,
                title: 'SafeSearch Filter',
                subtitle: 'Forces Google and Bing to hide explicit adult results.',
                value: securityState[SecurityFeature.safesearch] ?? true,
                onChanged: (val) {
                  if (!val && strictState.isStrict && strictState.remainingSeconds > 0) {
                    _showStrictLockWarning();
                    return;
                  }
                  ref.read(securityProvider.notifier).toggle(SecurityFeature.safesearch, val);
                },
              ),
              _divider(palette),
              _toggleRow(
                palette: palette,
                icon: Icons.block_rounded,
                iconColor: palette.strictAccent,
                title: 'Ad & Tracker Blocker',
                subtitle: 'Sinkholes ads and data analytics scripts across all apps.',
                value: privacyState[PrivacyFeature.disguisedTrackers] ?? true,
                onChanged: (val) {
                  if (!val && strictState.isStrict && strictState.remainingSeconds > 0) {
                    _showStrictLockWarning();
                    return;
                  }
                  ref.read(privacyProvider.notifier).toggle(PrivacyFeature.disguisedTrackers, val);
                },
              ),
              _divider(palette),
              _toggleRow(
                palette: palette,
                icon: Icons.vpn_lock_rounded,
                iconColor: palette.ink,
                title: 'Anti-VPN Bypass',
                subtitle: 'Prevents secondary VPNs from circumnavigating FocusDNS.',
                value: _antiVpnBypass,
                onChanged: _toggleAntiVpn,
              ),
            ],
          ),

          const SizedBox(height: 20),

          // Section 2: Distraction & Feed Blockers
          _sectionHeader('DISTRACTIONS & SOCIAL FEEDS', palette),
          _cardGroup(
            palette: palette,
            children: [
              _toggleRow(
                palette: palette,
                icon: Icons.smart_display_rounded,
                iconColor: const Color(0xFFFF0000),
                title: 'Block YouTube Shorts',
                subtitle: 'Removes the short-form addictive video shelf from YouTube.',
                value: _youtubeShorts,
                onChanged: _toggleYoutubeShorts,
              ),
              _divider(palette),
              _toggleRow(
                palette: palette,
                icon: Icons.camera_alt_rounded,
                iconColor: const Color(0xFFE1306C),
                title: 'Block Instagram Reels',
                subtitle: 'Prevents infinite doomscrolling inside the Instagram app.',
                value: _instagramReels,
                onChanged: _toggleInstagramReels,
              ),
            ],
          ),

          const SizedBox(height: 20),

          // Section 3: Device Integrity & Android Permissions
          _sectionHeader('DEVICE INTEGRITY & PERMISSIONS', palette),
          _cardGroup(
            palette: palette,
            children: [
              _toggleRow(
                palette: palette,
                icon: Icons.accessibility_new_rounded,
                iconColor: palette.safeAccent,
                title: 'Accessibility Service',
                subtitle: 'Required to auto-close blocked applications immediately upon opening.',
                value: _isAccessibilityActive,
                onChanged: _toggleAccessibility,
              ),
              _divider(palette),
              _toggleRow(
                palette: palette,
                icon: Icons.admin_panel_settings_rounded,
                iconColor: palette.strictAccent,
                title: 'Anti-Uninstall Shield',
                subtitle: 'Locks uninstallation during active strict focus countdown timers.',
                value: _isDeviceAdminActive,
                onChanged: _toggleDeviceAdmin,
              ),
              _divider(palette),
              _toggleRow(
                palette: palette,
                icon: Icons.dark_mode_rounded,
                iconColor: palette.ink,
                title: 'Dark Theme',
                subtitle: 'Switches between Stone Paper and Charcoal Dark styles.',
                value: themeMode == ThemeMode.dark,
                onChanged: (val) {
                  ref.read(themeModeProvider.notifier).setMode(
                        val ? ThemeMode.dark : ThemeMode.light,
                      );
                },
              ),
              _divider(palette),
              _toggleRow(
                palette: palette,
                icon: Icons.battery_charging_full_rounded,
                iconColor: palette.safeAccent,
                title: 'Battery Saver Immunity',
                subtitle: 'Keeps filtering active in the background without Android Doze killing it.',
                value: _isBatteryImmune,
                onChanged: _toggleBatteryImmunity,
              ),
            ],
          ),

          const SizedBox(height: 20),

          // Section 4: Data & System Actions
          _sectionHeader('DATA & SYSTEM MANAGEMENT', palette),
          _cardGroup(
            palette: palette,
            children: [
              _actionRow(
                palette: palette,
                icon: Icons.list_alt_rounded,
                iconColor: palette.ink,
                title: 'Custom Domain Rules',
                subtitle: 'Add specific domains to your allowlist or denylist.',
                onTap: _openCustomRulesSheet,
              ),
              _divider(palette),
              _actionRow(
                palette: palette,
                icon: Icons.delete_outline_rounded,
                iconColor: palette.strictAccent,
                title: 'Clear Query Logs',
                subtitle: 'Wipe all local on-device DNS query history.',
                onTap: _clearLogs,
              ),
              _divider(palette),
              _actionRow(
                palette: palette,
                icon: Icons.restart_alt_rounded,
                iconColor: palette.ink,
                title: 'Re-run Setup Walkthrough',
                subtitle: 'Revisit the 3-step setup and local storage permissions.',
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const OnboardingScreen()),
                  );
                },
              ),
            ],
          ),

          const SizedBox(height: 20),

          // Section 5: Account Actions (Hinge Style)
          _sectionHeader('ACCOUNT ACTIONS', palette),
          _cardGroup(
            palette: palette,
            children: [
              _actionRow(
                palette: palette,
                icon: Icons.logout_rounded,
                iconColor: palette.ink,
                title: 'Log Out',
                subtitle: 'Sign out while safely keeping your local preferences.',
                onTap: () => _showLogoutModal(context, palette),
              ),
              _divider(palette),
              _actionRow(
                palette: palette,
                icon: Icons.delete_forever_rounded,
                iconColor: Colors.red,
                title: 'Delete Account',
                subtitle: 'Permanently erase all local profiles, rules, and data.',
                onTap: () => _showDeleteAccountModal(context, palette),
              ),
            ],
          ),

          const SizedBox(height: 36),
        ],
      ),
    );
  }

  Widget _sectionHeader(String title, WabiSabiPalette palette) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 8),
      child: Text(
        title,
        style: GoogleFonts.jetBrainsMono(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.2,
          color: palette.mutedInk,
        ),
      ),
    );
  }

  Widget _cardGroup({required WabiSabiPalette palette, required List<Widget> children}) {
    return Container(
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: palette.border, width: 1.0),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: children,
      ),
    );
  }

  Widget _divider(WabiSabiPalette palette) {
    return Divider(
      height: 1,
      thickness: 0.8,
      indent: 58,
      color: palette.hairlineSoft,
    );
  }

  Widget _toggleRow({
    required WabiSabiPalette palette,
    required IconData icon,
    Color? iconColor,
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: palette.canvas,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: palette.border, width: 0.9),
            ),
            child: Icon(icon, size: 17, color: iconColor ?? palette.accent),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  style: GoogleFonts.inter(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                    color: palette.ink,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: GoogleFonts.inter(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w400,
                    color: palette.mutedInk,
                    height: 1.25,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Switch(
            value: value,
            activeColor: palette.ink,
            activeTrackColor: palette.ink.withOpacity(0.35),
            inactiveThumbColor: palette.mutedInk,
            inactiveTrackColor: palette.canvas,
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }

  Widget _actionRow({
    required WabiSabiPalette palette,
    required IconData icon,
    Color? iconColor,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: palette.canvas,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: palette.border, width: 0.9),
              ),
              child: Icon(icon, size: 17, color: iconColor ?? palette.accent),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title,
                    style: GoogleFonts.inter(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w600,
                      color: palette.ink,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: GoogleFonts.inter(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w400,
                      color: palette.mutedInk,
                      height: 1.25,
                    ),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded, size: 18, color: palette.mutedInk),
          ],
        ),
      ),
    );
  }
}
