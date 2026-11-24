import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../backend/blocker_service.dart';
import '../backend/mdm_service.dart';
import '../backend/vpn_service.dart';
import '../models/enums.dart';
import '../state_management/providers.dart';
import 'screens/onboarding/onboarding_screen.dart';
import 'tabs/allowlist_tab.dart';
import 'tabs/denylist_tab.dart';
import 'theme/wabi_sabi_theme.dart';

/// Clean, tactile, and decluttered "More" screen with inline toggles and concise descriptions.
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
    if (!value && strictState.isStrict) {
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
    if (!value && strictState.isStrict) {
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
    if (!value && strictState.isStrict) {
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
      if (strictState.isStrict) {
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
      if (strictState.isStrict) {
        _showStrictLockWarning();
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Deactivate Device Admin in Android Security settings.'),
          duration: Duration(seconds: 2),
        ),
      );
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

  @override
  Widget build(BuildContext context) {
    final palette = widget.palette;
    final securityState = ref.watch(securityProvider);
    final privacyState = ref.watch(privacyProvider);
    final strictState = ref.watch(strictModeProvider);
    final themeMode = ref.watch(themeModeProvider);

    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
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
                  if (!val && strictState.isStrict) {
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
                  if (!val && strictState.isStrict) {
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
                subtitle: 'Stops intrusive web ads, analytics scripts, and tracking.',
                value: privacyState[PrivacyFeature.disguisedTrackers] ?? true,
                onChanged: (val) {
                  if (!val && strictState.isStrict) {
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
                iconColor: palette.safeAccent,
                title: 'Anti-VPN Bypass',
                subtitle: 'Enforces site and app blocks even if another VPN connects.',
                value: _antiVpnBypass,
                onChanged: _toggleAntiVpn,
              ),
            ],
          ),

          const SizedBox(height: 20),

          // Section 2: Distraction & Feed Killers
          _sectionHeader('DISTRACTION & FEED KILLERS', palette),
          _cardGroup(
            palette: palette,
            children: [
              _toggleRow(
                palette: palette,
                icon: Icons.video_library_rounded,
                iconColor: const Color(0xFFFF0000),
                title: 'YouTube Shorts Blocker',
                subtitle: 'Hides and intercepts short-form video feeds on YouTube.',
                value: _youtubeShorts,
                onChanged: _toggleYoutubeShorts,
              ),
              _divider(palette),
              _toggleRow(
                palette: palette,
                icon: Icons.camera_alt_rounded,
                iconColor: const Color(0xFFE1306C),
                title: 'Instagram Reels Blocker',
                subtitle: 'Closes Reels immediately to stop endless video scrolling.',
                value: _instagramReels,
                onChanged: _toggleInstagramReels,
              ),
              _divider(palette),
              _toggleRow(
                palette: palette,
                icon: Icons.accessibility_new_rounded,
                iconColor: palette.safeAccent,
                title: 'Accessibility App Blocker',
                subtitle: 'Instantly closes restricted apps the moment they open.',
                value: _isAccessibilityActive,
                onChanged: _toggleAccessibility,
              ),
            ],
          ),

          const SizedBox(height: 20),

          // Section 3: Focus & Device Security
          _sectionHeader('FOCUS & DEVICE SECURITY', palette),
          _cardGroup(
            palette: palette,
            children: [
              _toggleRow(
                palette: palette,
                icon: Icons.lock_rounded,
                iconColor: palette.strictAccent,
                title: 'Strict Mode Lock',
                subtitle: 'Locks filters and settings so you cannot disable them during focus.',
                value: strictState.isStrict,
                onChanged: (val) {
                  ref.read(strictModeProvider.notifier).set(val, durationMinutes: 30);
                },
              ),
              _divider(palette),
              _toggleRow(
                palette: palette,
                icon: Icons.admin_panel_settings_rounded,
                iconColor: palette.strictAccent,
                title: 'Anti-Uninstall Shield',
                subtitle: 'Prevents uninstalling FocusDNS while focus sessions are active.',
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

          const SizedBox(height: 28),
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
