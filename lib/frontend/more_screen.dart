import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../backend/mdm_service.dart';
import '../state_management/providers.dart';
import 'tabs/allowlist_tab.dart';
import 'tabs/denylist_tab.dart';
import 'tabs/logs_tab.dart';
import 'tabs/privacy_tab.dart';
import 'tabs/security_tab.dart';
import 'tabs/settings_tab.dart';
import 'tabs/setup_tab.dart';
import 'auth/views/device_session_manager.dart';
import 'theme/wabi_sabi_theme.dart';
import 'widgets/routine_focus_card.dart';
import 'widgets/per_app_timer_card.dart';
import 'widgets/surgical_filter_card.dart';
import 'widgets/longitudinal_analytics_card.dart';
import 'screens/routine_focus_studio_screen.dart';
import 'screens/per_app_manager_screen.dart';
import 'screens/battery_shield_screen.dart';
import 'screens/surgical_feed_studio_screen.dart';
import 'screens/longitudinal_analytics_dashboard_screen.dart';
import 'screens/fleet/fleet_orchestration_master_screen.dart';
import 'screens/fleet/browser_extension_pairing_screen.dart';
import 'screens/profile/profile_hub_screen.dart';
import 'screens/profile/accountability_partner_screen.dart';
import 'screens/analytics/longitudinal_analytics_master_screen.dart';

/// Secondary screens reachable from the "More" tab.
class MoreTab extends ConsumerWidget {
  final WabiSabiPalette palette;
  const MoreTab({super.key, required this.palette});

  static const _groups = <_MoreGroup>[
    _MoreGroup(
      'NETWORK & PROTECTION',
      [
        _MoreItem('Setup', 'VPN and app blocker permissions', Icons.tune_rounded, 'setup'),
        _MoreItem('Security & Privacy', 'Threat intelligence, trackers & ad blocking', Icons.shield_outlined, 'security_privacy'),
        _MoreItem('Allowlist', 'Bypass rules & always allowed domains', Icons.check_circle_outline_rounded, 'allowlist'),
        _MoreItem('Denylist', 'Custom blocked domains & wildcards', Icons.block_rounded, 'denylist'),
      ],
    ),
    _MoreGroup(
      'ANTI-DOOMSCROLL ECOSYSTEM',
      [
        _MoreItem('Focus Routine and Breaks', 'Automate focus blocks and mindful breaks throughout your day.', Icons.all_inclusive_rounded, 'routine'),
        _MoreItem('Zero-Battery Shield', 'Kernel blocking I/O & Doze exemption (<1.2%/day)', Icons.battery_charging_full_rounded, 'battery_shield'),
        _MoreItem('Longitudinal Analytics', 'Daily, weekly, monthly & yearly focus habits', Icons.insights_rounded, 'longitudinal'),
      ],
    ),
    _MoreGroup(
      'SYSTEM & PREFERENCES',
      [
        _MoreItem('Account & Security', 'Phone number, active sessions & devices', Icons.phonelink_lock_rounded, 'account'),
        _MoreItem('Settings', 'Theme appearance, DNS profile & logs', Icons.settings_outlined, 'settings'),
        _MoreItem('Accountability Partner Vault', 'Guardian verification, emergency requests & trust', Icons.people_alt_outlined, 'partner_vault'),
        _MoreItem('Browser Extension Studio', 'Chrome, Brave, Edge & Firefox Manifest V3 pairing', Icons.extension_rounded, 'extension_pairing'),
        _MoreItem('Device Fleet Console', 'Multi-device lock broadcast & node telemetry', Icons.devices_other_rounded, 'fleet'),
      ],
    ),
  ];

  Widget _bodyFor(String id) {
    switch (id) {
      case 'routine':
        return const RoutineFocusCard();
      case 'app_timers':
        return const PerAppTimerCard();
      case 'battery_shield':
        return const BatteryShieldScreen();
      case 'feed_killer':
        return const SurgicalFilterCard();
      case 'longitudinal':
        return const LongitudinalAnalyticsCard();
      case 'setup':
        return const SetupTab();
      case 'security_privacy':
        return const SecurityPrivacyTab();
      case 'security':
        return const SecurityTab();
      case 'privacy':
        return const PrivacyTab();
      case 'allowlist':
        return const AllowlistTab();
      case 'denylist':
        return const DenylistTab();
      case 'settings':
        return const SettingsTab();
      case 'account':
        return const DeviceSessionManagerView();
      default:
        return const LogsTab();
    }
  }

  void _open(BuildContext context, WidgetRef ref, _MoreItem item) {
    if (item.id == 'profile_hub') {
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ProfileHubWrapper()));
      return;
    }
    if (item.id == 'fleet') {
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => FleetOrchestrationMasterScreen(coordinator: ref.read(syncCoordinatorProvider))));
      return;
    }
    if (item.id == 'extension_pairing') {
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => const BrowserExtensionPairingScreen(userId: 'usr_master_warrior')));
      return;
    }
    if (item.id == 'partner_vault') {
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => const AccountabilityPartnerScreenWrapper()));
      return;
    }
    if (item.id == 'longitudinal_master') {
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => const LongitudinalAnalyticsMasterScreenWrapper()));
      return;
    }
    if (item.id == 'routine') {
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => const RoutineFocusStudioScreen()));
      return;
    }
    if (item.id == 'app_timers') {
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => const PerAppManagerScreen()));
      return;
    }
    if (item.id == 'feed_killer') {
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SurgicalFeedStudioScreen()));
      return;
    }
    if (item.id == 'longitudinal') {
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => const LongitudinalAnalyticsDashboardScreen()));
      return;
    }

    Navigator.of(context).push(
      PageRouteBuilder(
        transitionDuration: const Duration(milliseconds: 260),
        reverseTransitionDuration: const Duration(milliseconds: 200),
        pageBuilder: (context, animation, secondaryAnimation) => Scaffold(
          backgroundColor: palette.canvas,
          appBar: AppBar(
            backgroundColor: palette.canvas,
            elevation: 0,
            iconTheme: IconThemeData(color: palette.ink),
            title: Text(
              item.title,
              style: GoogleFonts.plusJakartaSans(
                color: palette.ink,
                fontSize: 18,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.3,
              ),
            ),
          ),
          body: SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: _bodyFor(item.id),
            ),
          ),
        ),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          final slide = Tween<Offset>(
            begin: const Offset(0.06, 0.0),
            end: Offset.zero,
          ).animate(CurvedAnimation(parent: animation, curve: Curves.easeOutCubic));

          return FadeTransition(
            opacity: animation,
            child: SlideTransition(position: slide, child: child),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strictState = ref.watch(strictModeProvider);

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 6, 20, 28),
      children: [
        // EYEBROW
        Text(
          'FOCUSDNS · MORE',
          style: GoogleFonts.inter(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            letterSpacing: 1.4,
            color: palette.mutedInk,
          ),
        ),
        const SizedBox(height: 6),

        // HERO HEADLINE
        Text(
          'Everything else.',
          style: GoogleFonts.fraunces(
            fontSize: 28,
            fontWeight: FontWeight.w700,
            color: palette.ink,
            height: 1.15,
            letterSpacing: -0.5,
          ),
        ),
        const SizedBox(height: 4),

        // SUBTITLE
        Text(
          'Setup, rules, routines and your account.',
          style: GoogleFonts.inter(
            fontSize: 12.5,
            color: palette.mutedInk,
            height: 1.3,
          ),
        ),
        const SizedBox(height: 10),

        for (final group in _groups) ...[
          Padding(
            padding: const EdgeInsets.only(left: 4, top: 14, bottom: 8),
            child: Text(
              group.header,
              style: GoogleFonts.inter(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                letterSpacing: 1.1,
                color: palette.mutedInk,
              ),
            ),
          ),
          Container(
            decoration: BoxDecoration(
              color: palette.surface,
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: palette.hairlineSoft, width: 1),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: Column(
                children: [
                  for (int i = 0; i < group.items.length; i++) ...[
                    _BouncingMoreTile(
                      item: group.items[i],
                      palette: palette,
                      onTap: () => _open(context, ref, group.items[i]),
                    ),
                    if (i < group.items.length - 1)
                      Divider(height: 1, thickness: 1, color: palette.hairlineSoft, indent: 64),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
        ],

        // APPLICATION REMOVAL
        // Core rule: The option to delete the app does NOT come when strict mode is active, only in normal mode.
        if (!strictState.isStrict) ...[
          Padding(
            padding: const EdgeInsets.only(left: 4, top: 14, bottom: 8),
            child: Text(
              'APPLICATION REMOVAL',
              style: GoogleFonts.inter(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                letterSpacing: 1.1,
                color: palette.mutedInk,
              ),
            ),
          ),
          InkWell(
            key: const Key('more_uninstall_app_tile'),
            borderRadius: BorderRadius.circular(4),
            onTap: () => _confirmUninstallApp(context, palette),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              decoration: BoxDecoration(
                color: palette.surface,
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: palette.strictAccent.withOpacity(0.3), width: 1),
              ),
              child: Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(4),
                      color: palette.strictAccent.withOpacity(0.12),
                    ),
                    child: Center(
                      child: Icon(Icons.delete_outline_rounded, color: palette.strictAccent, size: 20),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Uninstall FocusDNS',
                          style: GoogleFonts.inter(
                            color: palette.strictAccent,
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            letterSpacing: -0.2,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Clean uninstallation permitted in normal mode.',
                          style: GoogleFonts.inter(
                            color: palette.mutedInk,
                            fontSize: 12.5,
                            fontWeight: FontWeight.w400,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Icon(Icons.chevron_right_rounded, color: palette.strictAccent, size: 20),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
        ],

        Padding(
          padding: const EdgeInsets.symmetric(vertical: 20),
          child: Text(
            'Nothing is uploaded to external servers. All queries resolve privately on-device.',
            textAlign: TextAlign.center,
            style: GoogleFonts.inter(
              fontSize: 11.5,
              fontStyle: FontStyle.italic,
              color: palette.mutedInk.withOpacity(0.85),
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _confirmUninstallApp(BuildContext context, WabiSabiPalette palette) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: palette.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: Text(
          'Uninstall FocusDNS?',
          style: GoogleFonts.plusJakartaSans(
            color: palette.ink,
            fontSize: 17,
            fontWeight: FontWeight.bold,
          ),
        ),
        content: Text(
          'Normal mode is active. This will deactivate device administrator privileges and launch the system uninstaller.',
          style: GoogleFonts.plusJakartaSans(
            color: palette.mutedInk,
            fontSize: 13,
            height: 1.4,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('CANCEL', style: TextStyle(color: palette.mutedInk)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: palette.strictAccent,
              foregroundColor: palette.canvas,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            child: const Text('UNINSTALL', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    if (confirm == true && context.mounted) {
      final res = await FocusMdmManager.deactivateAndUninstall();
      if (!context.mounted) return;
      if (res['success'] != true) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: palette.surface,
            content: Text(
              res['reason']?.toString() ?? 'Failed to request uninstallation',
              style: TextStyle(color: palette.ink),
            ),
          ),
        );
      }
    }
  }
}

class _BouncingMoreTile extends StatefulWidget {
  final _MoreItem item;
  final WabiSabiPalette palette;
  final VoidCallback onTap;

  const _BouncingMoreTile({
    required this.item,
    required this.palette,
    required this.onTap,
  });

  @override
  State<_BouncingMoreTile> createState() => _BouncingMoreTileState();
}

class _BouncingMoreTileState extends State<_BouncingMoreTile> {
  bool _isPressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      key: Key('more_${widget.item.id}'),
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => setState(() => _isPressed = true),
      onTapUp: (_) {
        setState(() => _isPressed = false);
        widget.onTap();
      },
      onTapCancel: () => setState(() => _isPressed = false),
      child: AnimatedScale(
        scale: _isPressed ? 0.985 : 1.0,
        duration: const Duration(milliseconds: 120),
        curve: Curves.easeOutCubic,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          color: _isPressed ? widget.palette.border.withOpacity(0.3) : Colors.transparent,
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(4),
                  color: widget.palette.canvas,
                  border: Border.all(color: widget.palette.hairlineSoft, width: 1),
                ),
                child: Center(
                  child: Icon(widget.item.icon, color: widget.palette.ink, size: 20),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.item.title,
                      style: GoogleFonts.inter(
                        color: widget.palette.ink,
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        letterSpacing: -0.2,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      widget.item.subtitle,
                      style: GoogleFonts.inter(
                        color: widget.palette.mutedInk,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w400,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded, color: widget.palette.mutedInk, size: 20),
            ],
          ),
        ),
      ),
    );
  }
}

class _MoreGroup {
  final String header;
  final List<_MoreItem> items;
  const _MoreGroup(this.header, this.items);
}

class _MoreItem {
  final String title;
  final String subtitle;
  final IconData icon;
  final String id;
  const _MoreItem(this.title, this.subtitle, this.icon, this.id);
}

/// Seamless Riverpod wrapper for ProfileHubScreen
class ProfileHubWrapper extends ConsumerWidget {
  const ProfileHubWrapper({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(userProfileProvider);
    final coordinator = ref.watch(syncCoordinatorProvider);
    final storeAsync = ref.watch(analyticsStoreFutureProvider);
    final partnerAsync = ref.watch(partnerManagerFutureProvider);

    return storeAsync.when(
      data: (store) => partnerAsync.when(
        data: (partner) => ProfileHubScreen(
          initialProfile: profile,
          syncCoordinator: coordinator,
          partnerManager: partner,
          analyticsStore: store,
          onProfileUpdated: (p) => ref.read(userProfileProvider.notifier).updateProfile(p),
        ),
        loading: () => const Scaffold(
          backgroundColor: Color(0xFF0E0E12),
          body: Center(child: CircularProgressIndicator(color: Color(0xFF00E699))),
        ),
        error: (e, _) => Scaffold(
          backgroundColor: const Color(0xFF0E0E12),
          body: Center(child: Text('Error: $e', style: const TextStyle(color: Colors.white))),
        ),
      ),
      loading: () => const Scaffold(
        backgroundColor: Color(0xFF0E0E12),
        body: Center(child: CircularProgressIndicator(color: Color(0xFF00E699))),
      ),
      error: (e, _) => Scaffold(
        backgroundColor: const Color(0xFF0E0E12),
        body: Center(child: Text('Error: $e', style: const TextStyle(color: Colors.white))),
      ),
    );
  }
}

/// Seamless Riverpod wrapper for AccountabilityPartnerScreen
class AccountabilityPartnerScreenWrapper extends ConsumerWidget {
  const AccountabilityPartnerScreenWrapper({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final partnerAsync = ref.watch(partnerManagerFutureProvider);
    return partnerAsync.when(
      data: (partner) => AccountabilityPartnerScreen(manager: partner),
      loading: () => const Scaffold(
        backgroundColor: Color(0xFF0E0E12),
        body: Center(child: CircularProgressIndicator(color: Color(0xFF00E699))),
      ),
      error: (e, _) => Scaffold(
        backgroundColor: const Color(0xFF0E0E12),
        body: Center(child: Text('Error: $e', style: const TextStyle(color: Colors.white))),
      ),
    );
  }
}

/// Seamless Riverpod wrapper for LongitudinalAnalyticsMasterScreen
class LongitudinalAnalyticsMasterScreenWrapper extends ConsumerWidget {
  const LongitudinalAnalyticsMasterScreenWrapper({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final storeAsync = ref.watch(analyticsStoreFutureProvider);
    return storeAsync.when(
      data: (store) => LongitudinalAnalyticsMasterScreen(store: store),
      loading: () => const Scaffold(
        backgroundColor: Color(0xFF0E0E12),
        body: Center(child: CircularProgressIndicator(color: Color(0xFF00E699))),
      ),
      error: (e, _) => Scaffold(
        backgroundColor: const Color(0xFF0E0E12),
        body: Center(child: Text('Error: $e', style: const TextStyle(color: Colors.white))),
      ),
    );
  }
}

class SecurityPrivacyTab extends StatelessWidget {
  const SecurityPrivacyTab({super.key});

  @override
  Widget build(BuildContext context) {
    final palette = WabiSabiPalette.of(context);
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Text(
              'SECURITY RULES',
              style: GoogleFonts.inter(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.1,
                color: palette.mutedInk,
              ),
            ),
          ),
          const SecurityTab(),
          const SizedBox(height: 12),
          Divider(color: palette.hairlineSoft, height: 24),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Text(
              'PRIVACY & TRACKERS',
              style: GoogleFonts.inter(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.1,
                color: palette.mutedInk,
              ),
            ),
          ),
          const PrivacyTab(),
        ],
      ),
    );
  }
}

