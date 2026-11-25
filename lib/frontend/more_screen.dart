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
import 'auth/welcome_screen.dart';
import 'edit_profile_sheet.dart';
import 'widgets/motion.dart';
import 'screens/onboarding/onboarding_screen.dart';
import 'screens/profile/delete_account_screen.dart';
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
  int _cardIndex = 0;
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
                      'Log out of FocusDNS?',
                      textAlign: TextAlign.center,
                      style: GoogleFonts.fraunces(fontSize: 22, fontWeight: FontWeight.w700, color: palette.ink),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      'Your local preferences, rules, and blocker settings will remain safely saved on this device.',
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
                  key: const Key('confirm_logout_button'),
                  onPressed: () async {
                    Navigator.of(ctx).pop();
                    await ref.read(authProvider.notifier).logout();
                    if (context.mounted) {
                      Navigator.of(context).pushAndRemoveUntil(
                        MaterialPageRoute(builder: (_) => const WelcomeScreen()),
                        (route) => false,
                      );
                    }
                  },
                  child: Text('Log Out', style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.w700, color: palette.ink)),
                ),
              ),
              Divider(height: 1, thickness: 1, color: palette.hairlineSoft),
              SizedBox(
                width: double.infinity,
                height: 52,
                child: TextButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  child: Text('Cancel', style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.w500, color: palette.mutedInk)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showDeleteAccountModal(BuildContext context, WabiSabiPalette palette) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const DeleteAccountScreen()),
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
    _cardIndex = 0;

    final displayProfileName = auth.activeProfileName.isNotEmpty
        ? auth.activeProfileName
        : settings.profileName;

    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Top Profile (Instagram-style header)
          _buildInstagramProfile(palette, displayProfileName, isProtectionOn),

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
              _hingeRow(palette: palette, title: 'Log Out', onTap: () => _showLogoutModal(context, palette)),
              Divider(height: 1, thickness: 0.8, color: palette.hairlineSoft),
              _hingeRow(palette: palette, title: 'Delete Account', onTap: () => _showDeleteAccountModal(context, palette)),
            ],
          ),

          const SizedBox(height: 36),
        ],
      ),
    );
  }

  /// Plain list row (Hinge settings style): single label, chevron, no icon/subtitle.
  Widget _hingeRow({required WabiSabiPalette palette, required String title, required VoidCallback onTap}) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 17),
        child: Row(
          children: [
            Expanded(child: Text(title, style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.w500, color: palette.ink))),
            Icon(Icons.chevron_right_rounded, size: 22, color: palette.mutedInk),
          ],
        ),
      ),
    );
  }

  String _compact(int n) {
    if (n >= 1000000) return '${(n / 1000000).toStringAsFixed(1)}M';
    if (n >= 1000) return '${(n / 1000).toStringAsFixed(1)}K';
    return '$n';
  }

  Widget _statColumn(WabiSabiPalette palette, int value, String label) {
    return Expanded(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedCount(value: value, formatter: _compact, style: GoogleFonts.inter(fontSize: 18, fontWeight: FontWeight.w700, color: palette.ink)),
          const SizedBox(height: 2),
          Text(label, style: GoogleFonts.inter(fontSize: 13, color: palette.ink)),
        ],
      ),
    );
  }

  Widget _buildInstagramProfile(WabiSabiPalette palette, String name, bool isProtectionOn) {
    final auth = ref.watch(authProvider);
    final analytics = ref.watch(analyticsStateProvider);
    final deepFocus = ref.watch(deepFocusProvider);
    final initial = name.trim().isNotEmpty ? name.trim()[0].toUpperCase() : 'F';

    return FadeSlideIn(
      child: Column(
        key: const Key('header_profile_pill'),
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 400),
                width: 84,
                height: 84,
                padding: const EdgeInsets.all(3),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: isProtectionOn
                      ? const LinearGradient(
                          begin: Alignment.bottomLeft,
                          end: Alignment.topRight,
                          colors: [Color(0xFFFEDA75), Color(0xFFFA7E1E), Color(0xFFD62976), Color(0xFF962FBF), Color(0xFF4F5BD5)],
                        )
                      : null,
                  color: isProtectionOn ? null : palette.border,
                ),
                child: Container(
                  decoration: BoxDecoration(shape: BoxShape.circle, color: palette.canvas),
                  padding: const EdgeInsets.all(3),
                  child: Container(
                    decoration: BoxDecoration(shape: BoxShape.circle, color: palette.surface),
                    child: Center(child: Text(initial, style: GoogleFonts.fraunces(fontSize: 32, fontWeight: FontWeight.w700, color: palette.ink))),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              _statColumn(palette, analytics.blockedQueries, 'Blocked'),
              _statColumn(palette, deepFocus.websites.length, 'Sites & apps'),
              _statColumn(palette, deepFocus.categories.length, 'Categories'),
            ],
          ),
          const SizedBox(height: 12),
          Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.w800, color: palette.ink)),
          if (auth.isLoggedIn && auth.email != null)
            Text(auth.email!, maxLines: 1, overflow: TextOverflow.ellipsis, style: GoogleFonts.inter(fontSize: 13.5, color: palette.mutedInk)),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            height: 36,
            child: PressableScale(
              onTap: () => showModalBottomSheet(
                context: context,
                isScrollControlled: true,
                backgroundColor: Colors.transparent,
                builder: (context) => const EditProfileSheet(),
              ),
              child: Container(
                key: const Key('profile_edit_button'),
                alignment: Alignment.center,
                decoration: BoxDecoration(color: palette.surface, borderRadius: BorderRadius.circular(9), border: Border.all(color: palette.border, width: 0.8)),
                child: Text('Edit profile', style: GoogleFonts.inter(fontSize: 13.5, fontWeight: FontWeight.w600, color: palette.ink)),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(top: 14),
            child: Divider(height: 1, thickness: 0.8, color: palette.hairlineSoft),
          ),
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
    return FadeSlideIn(
      delay: FadeSlideIn.stagger(++_cardIndex, stepMs: 70),
      child: _cardBody(palette, children),
    );
  }

  Widget _cardBody(WabiSabiPalette palette, List<Widget> children) {
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
