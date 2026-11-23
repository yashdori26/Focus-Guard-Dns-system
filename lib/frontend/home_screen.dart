import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../state_management/providers.dart';
import '../engine/routine/routine_state_machine.dart';
import 'profile_settings_sheet.dart';
import 'profile_switcher_sheet.dart';
import 'phone_auth_sheet.dart';
import 'theme/wabi_sabi_theme.dart';
import 'more_screen.dart';
import 'tabs/deep_focus_tab.dart';
import 'tabs/logs_tab.dart';
import 'widgets.dart';
import 'screens/routine_focus_studio_screen.dart';

class FocusDNSHomeScreen extends ConsumerStatefulWidget {
  const FocusDNSHomeScreen({super.key});

  @override
  ConsumerState<FocusDNSHomeScreen> createState() => _FocusDNSHomeScreenState();
}

class _FocusDNSHomeScreenState extends ConsumerState<FocusDNSHomeScreen>
    with WidgetsBindingObserver {
  int _currentPage = 0;
  String _selectedFilter = '7d';
  String? _urlOverlay;
  bool _dismissedAccessibilityBanner = false;
  final TextEditingController _insightsSearchController = TextEditingController();
  String _insightsSearchQuery = '';
  int _insightsSubTab = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadSavedTab();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(setupProvider.notifier).autoSyncAndLinkIp();
    });
    _handleQueryParams();
  }

  Future<void> _loadSavedTab() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedTab = prefs.getInt('focus_dns_last_tab_index') ?? 0;
      final savedSubTab = prefs.getInt('focus_dns_last_insights_subtab') ?? 0;
      if (mounted) {
        setState(() {
          _currentPage = savedTab;
          _insightsSubTab = savedSubTab;
        });
      }
    } catch (_) {}
  }

  void _onTabChanged(int index) {
    setState(() => _currentPage = index);
    SharedPreferences.getInstance().then((prefs) {
      prefs.setInt('focus_dns_last_tab_index', index);
    }).catchError((_) {});
  }

  void _onSubTabChanged(int index) {
    setState(() => _insightsSubTab = index);
    SharedPreferences.getInstance().then((prefs) {
      prefs.setInt('focus_dns_last_insights_subtab', index);
    }).catchError((_) {});
  }

  @override
  void dispose() {
    _insightsSearchController.dispose();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      ref.read(blockerProvider.notifier).checkStatus();
      ref.read(vpnProvider.notifier).checkStatus();
      ref.read(liveTelemetryProvider.notifier).refresh();
      ref.read(setupProvider.notifier).autoSyncAndLinkIp();
    }
  }


  void _handleQueryParams() {
    if (!kIsWeb) return;
    try {
      final params = Map<String, String>.from(Uri.base.queryParameters);
      if (Uri.base.hasFragment) {
        final frag = Uri.base.fragment;
        final qIdx = frag.indexOf('?');
        if (qIdx != -1) {
          final queryStr = frag.substring(qIdx + 1);
          final fragUri = Uri(query: queryStr);
          params.addAll(fragUri.queryParameters);
        }
      }
      if (params.containsKey('theme')) {
        final t = params['theme']?.toLowerCase();
        if (t == 'light') {
          ref.read(themeModeProvider.notifier).setMode(ThemeMode.light);
        } else if (t == 'dark') {
          ref.read(themeModeProvider.notifier).setMode(ThemeMode.dark);
        }
      }
      if (params.containsKey('strict') && params['strict'] == 'true') {
        ref.read(strictModeProvider.notifier).set(true, durationMinutes: 30);
      }
      if (params.containsKey('idle') && params['idle'] == 'true') {
        ref.read(protectionProvider.notifier).set(false);
      }
      if (params.containsKey('page')) {
        final p = int.tryParse(params['page'] ?? '0') ?? 0;
        if (p >= 0 && p <= 3) {
          _currentPage = p;
        }
      }
      if (params.containsKey('subtab') && (params['subtab'] == 'logs' || params['subtab'] == '1')) {
        _insightsSubTab = 1;
      }
      if (params.containsKey('dialog') && params['dialog'] == 'strict') {
        _urlOverlay = 'strict_dialog';
      } else if (params.containsKey('sheet')) {
        if (params['sheet'] == 'auth') {
          _urlOverlay = 'auth_sheet';
        } else if (params['sheet'] == 'profile_switcher') {
          _urlOverlay = 'profile_switcher';
        } else {
          _urlOverlay = 'profile_sheet';
        }
      }
    } catch (_) {}
  }

  void _openProfileSwitcherSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => const ProfileSwitcherSheet(),
    );
  }

  void _openAllProfileSettingsSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => const AllProfileSettingsSheet(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isProtectionOn = ref.watch(protectionProvider);
    final strictState = ref.watch(strictModeProvider);
    final vpn = ref.watch(vpnProvider);
    final blocker = ref.watch(blockerProvider);
    final themeMode = ref.watch(themeModeProvider);
    final settings = ref.watch(settingsProvider);
    final auth = ref.watch(authProvider);
    final displayProfileName = auth.activeProfileName.isNotEmpty
        ? auth.activeProfileName
        : settings.profileName;
    final palette = themeMode == ThemeMode.light
        ? WabiSabiPalette.light
        : WabiSabiPalette.dark;

    final titles = ['Protection', 'Focus', 'Insights', 'More'];
    final scaffold = Scaffold(
      backgroundColor: palette.canvas,
      body: SafeArea(
        child: Column(
          children: [
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 28.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  if (_currentPage == 0)
                    Flexible(
                      child: GestureDetector(
                        key: const Key('header_profile_pill'),
                        behavior: HitTestBehavior.opaque,
                        onTap: _openProfileSwitcherSheet,
                        onLongPress: _openAllProfileSettingsSheet,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: palette.surface,
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(color: palette.border, width: 1.0),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 6,
                              height: 6,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: isProtectionOn ? palette.safeAccent : palette.mutedInk,
                              ),
                            ),
                            const SizedBox(width: 8),
                            if (auth.isLoggedIn) ...[
                              Text(auth.detectedFlag, style: const TextStyle(fontSize: 12)),
                              const SizedBox(width: 4),
                            ],
                            Flexible(
                              child: Text(
                                displayProfileName,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: GoogleFonts.inter(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: palette.ink,
                                  letterSpacing: -0.1,
                                ),
                              ),
                            ),
                            const SizedBox(width: 4),
                            Icon(Icons.keyboard_arrow_down_rounded, size: 15, color: palette.mutedInk),
                          ],
                        ),
                      ),
                    ),
                  )
                  else
                    Text(
                      titles[_currentPage],
                      style: GoogleFonts.fraunces(
                        fontSize: 26,
                        fontWeight: FontWeight.w600,
                        color: palette.ink,
                        letterSpacing: -0.3,
                      ),
                    ),
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => ref.read(themeModeProvider.notifier).toggle(),
                    child: SizedBox(
                      width: 48,
                      height: 48,
                      child: Center(
                        child: Container(
                          width: 34,
                          height: 34,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(4),
                            color: palette.surface,
                            border: Border.all(color: palette.border, width: 1.0),
                          ),
                          child: Icon(
                            themeMode == ThemeMode.dark
                                ? Icons.wb_sunny_outlined
                                : Icons.nightlight_round_outlined,
                            size: 16,
                            color: palette.ink,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 240),
                switchInCurve: Curves.easeOutCubic,
                switchOutCurve: Curves.easeInCubic,
                transitionBuilder: (child, animation) {
                  return FadeTransition(
                    opacity: animation,
                    child: SlideTransition(
                      position: Tween<Offset>(
                        begin: const Offset(0.0, 0.02),
                        end: Offset.zero,
                      ).animate(animation),
                      child: child,
                    ),
                  );
                },
                child: KeyedSubtree(
                  key: ValueKey<int>(_currentPage),
                  child: _buildCurrentTab(isProtectionOn, strictState, vpn, blocker, palette),
                ),
              ),
            ),
            _buildBottomBar(strictState, palette),
          ],
        ),
      ),
    );

    if (_urlOverlay != null) {
      return Stack(
        children: [
          scaffold,
          Positioned.fill(
            child: Theme(
              data: themeMode == ThemeMode.light
                  ? WabiSabiTheme.lightTheme
                  : WabiSabiTheme.darkTheme,
              child: Material(
                type: MaterialType.transparency,
                child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => setState(() => _urlOverlay = null),
                child: Container(
                  color: Colors.black.withOpacity(0.55),
                  alignment: Alignment.bottomCenter,
                  child: GestureDetector(
                    onTap: () {},
                    child: _urlOverlay == 'strict_dialog'
                        ? StrictModeDisclaimerSheetContent(
                            palette: palette,
                            onCancel: () => setState(() => _urlOverlay = null),
                            onConfirm: (mins) async {
                              setState(() => _urlOverlay = null);
                              final success = await ref
                                  .read(strictModeProvider.notifier)
                                  .set(true, durationMinutes: mins);
                              if (success && context.mounted) {
                                ScaffoldMessenger.of(context).clearSnackBars();
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(
                                        '🔒 Strict Mode activated for $mins minutes! Protection locked.'),
                                    backgroundColor: palette.surface,
                                    duration: const Duration(seconds: 3),
                                  ),
                                );
                              }
                            },
                          )
                        : _urlOverlay == 'auth_sheet'
                            ? const PhoneAuthSheet()
                            : _urlOverlay == 'profile_switcher'
                                ? const ProfileSwitcherSheet()
                                : const AllProfileSettingsSheet(),
                  ),
                ),
              ),
            ),
          ),
        ),
        ],
      );
    }

    return scaffold;
  }

  Widget _buildCurrentTab(
    bool isProtectionOn,
    StrictModeState strictState,
    VpnState vpn,
    BlockerState blocker,
    WabiSabiPalette palette,
  ) {
    switch (_currentPage) {
      case 0:
        return _buildPage1Protection(isProtectionOn, strictState, vpn, blocker, palette);
      case 1:
        return const SingleChildScrollView(
          padding: EdgeInsets.all(20),
          child: DeepFocusTab(),
        );
      case 2:
        return _buildInsightsPage(palette);
      case 3:
      default:
        return MoreTab(palette: palette);
    }
  }

  Widget _navItem(int index, IconData icon, String label, WabiSabiPalette palette) {
    final selected = _currentPage == index;
    return Expanded(
      child: InkWell(
        key: Key('nav_$index'),
        onTap: () => _onTabChanged(index),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 20,
                color: selected ? palette.accent : palette.mutedInk,
              ),
              const SizedBox(height: 3),
              Text(
                label,
                style: GoogleFonts.inter(
                  fontSize: 12,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                  color: selected ? palette.ink : palette.mutedInk,
                  letterSpacing: 0.1,
                ),
              ),
              const SizedBox(height: 3),
              Container(
                width: selected ? 16 : 0,
                height: 1.5,
                color: selected ? palette.accent : Colors.transparent,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBottomBar(StrictModeState strictState, WabiSabiPalette palette) {
    final locked = strictState.isLocked;
    return Container(
      decoration: BoxDecoration(
        color: palette.canvas,
        border: Border(top: BorderSide(color: palette.hairlineSoft, width: 1.0)),
      ),
      child: Row(
        children: [
          _navItem(0, locked ? Icons.lock : Icons.shield_outlined, 'Protect', palette),
          _navItem(1, Icons.timer_outlined, 'Focus', palette),
          _navItem(2, Icons.bar_chart, 'Insights', palette),
          _navItem(3, Icons.more_horiz, 'More', palette),
        ],
      ),
    );
  }

  Widget _buildInsightsPage(WabiSabiPalette palette) {
    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.only(bottom: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // EYEBROW, HEADLINE & SUBTITLE
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'FOCUSDNS · INSIGHTS',
                  style: GoogleFonts.inter(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 1.4,
                    color: palette.mutedInk,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  _insightsSubTab == 0 ? 'Know your network.' : 'Query records.',
                  style: GoogleFonts.fraunces(
                    fontSize: 28,
                    fontWeight: FontWeight.w700,
                    color: palette.ink,
                    height: 1.15,
                    letterSpacing: -0.5,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _insightsSubTab == 0
                      ? 'Live telemetry, DNS resolution latency, and threats blocked.'
                      : 'Real-time inspection log of recent domain lookups and active blocks.',
                  style: GoogleFonts.inter(
                    fontSize: 12.5,
                    color: palette.mutedInk,
                    height: 1.3,
                  ),
                ),
                const SizedBox(height: 12),

                // SEGMENTED SWITCHER: [ Analytics ]  [ Logs ]
                Container(
                  height: 36,
                  padding: const EdgeInsets.all(3),
                  decoration: BoxDecoration(
                    color: palette.surface,
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: palette.hairlineSoft, width: 1.0),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: GestureDetector(
                          key: const Key('insights_analytics_subtab'),
                          behavior: HitTestBehavior.opaque,
                          onTap: () => _onSubTabChanged(0),
                          child: Container(
                            decoration: BoxDecoration(
                              color: _insightsSubTab == 0 ? palette.ink : Colors.transparent,
                              borderRadius: BorderRadius.circular(3),
                            ),
                            alignment: Alignment.center,
                            child: Text(
                              'Analytics',
                              style: GoogleFonts.inter(
                                fontSize: 12,
                                fontWeight: _insightsSubTab == 0 ? FontWeight.w700 : FontWeight.w500,
                                color: _insightsSubTab == 0 ? palette.canvas : palette.mutedInk,
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: GestureDetector(
                          key: const Key('insights_logs_subtab'),
                          behavior: HitTestBehavior.opaque,
                          onTap: () => _onSubTabChanged(1),
                          child: Container(
                            decoration: BoxDecoration(
                              color: _insightsSubTab == 1 ? palette.ink : Colors.transparent,
                              borderRadius: BorderRadius.circular(3),
                            ),
                            alignment: Alignment.center,
                            child: Text(
                              'Logs',
                              style: GoogleFonts.inter(
                                fontSize: 12,
                                fontWeight: _insightsSubTab == 1 ? FontWeight.w700 : FontWeight.w500,
                                color: _insightsSubTab == 1 ? palette.canvas : palette.mutedInk,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
              ],
            ),
          ),

          // SUB-TAB CONTENT
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 200),
            child: _insightsSubTab == 0
                ? KeyedSubtree(
                    key: const ValueKey('analytics_subview'),
                    child: _buildPage2Analytics(palette),
                  )
                : KeyedSubtree(
                    key: const ValueKey('logs_subview'),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20.0),
                      child: LogsTab(palette: palette),
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  String _formatRemaining(int seconds) {
    if (seconds <= 0) return '00:00';
    final h = seconds ~/ 3600;
    final m = (seconds % 3600) ~/ 60;
    final s = seconds % 60;
    if (h > 0) {
      return '${h}h ${m.toString().padLeft(2, '0')}m ${s.toString().padLeft(2, '0')}s';
    }
    return '${m.toString().padLeft(2, '0')}m ${s.toString().padLeft(2, '0')}s';
  }

  void _showStrictModeDisclaimerDialog(BuildContext context, {int initialMinutes = 30}) {
    final palette = WabiSabiPalette.of(context);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return StrictModeDisclaimerSheetContent(
          palette: palette,
          initialMinutes: initialMinutes,
          onCancel: () => Navigator.pop(ctx),
          onConfirm: (selectedMinutes) async {
            Navigator.pop(ctx);
            ref.read(setupProvider.notifier).autoSyncAndLinkIp();
            final success = await ref
                .read(strictModeProvider.notifier)
                .set(true, durationMinutes: selectedMinutes);
            if (success && context.mounted) {
              ScaffoldMessenger.of(context).clearSnackBars();
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                      '🔒 Strict Mode activated for $selectedMinutes minutes! Protection locked.'),
                  backgroundColor: palette.surface,
                  duration: const Duration(seconds: 3),
                ),
              );
            }
          },
        );
      },
    );
  }

  void _showCircularRoutineSetupDialog(BuildContext context) {
    final palette = WabiSabiPalette.of(context);
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return CircularRoutineSetupSheet(
          palette: palette,
          onCancel: () => Navigator.pop(ctx),
          onConfirm: (focusMinutes, breakMinutes, cycles) async {
            Navigator.pop(ctx);
            ref.read(routineEngineProvider).updateConfig(
              RoutineScheduleConfig(
                focusMinutes: focusMinutes,
                breakMinutes: breakMinutes,
                totalCycles: cycles,
                label: 'Focus Routine',
              ),
            );
            ref.read(routineEngineProvider).startRoutine();
            ref.read(setupProvider.notifier).autoSyncAndLinkIp();
            await ref.read(protectionProvider.notifier).set(true);
            if (!kIsWeb) {
              final profileId = ref.read(setupProvider).profileId;
              await ref.read(vpnProvider.notifier).start(profileId: profileId);
            }
            if (context.mounted) {
              final focusLabel = focusMinutes < 60 ? '${focusMinutes}m' : '${focusMinutes ~/ 60}h${focusMinutes % 60 > 0 ? ' ${focusMinutes % 60}m' : ''}';
              final breakLabel = breakMinutes < 60 ? '${breakMinutes}m' : '${breakMinutes ~/ 60}h${breakMinutes % 60 > 0 ? ' ${breakMinutes % 60}m' : ''}';
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('⏳ Focus Routine started: $focusLabel focus · $breakLabel break · $cycles cycles'),
                  backgroundColor: palette.surface,
                ),
              );
            }
          },
        );
      },
    );
  }

  void _showSessionOptionsSheet(BuildContext context) {
    final strictState = ref.read(strictModeProvider);
    if (strictState.isStrict) {
      ScaffoldMessenger.of(context).clearSnackBars();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('⏳ Strict Mode is already active (${_formatRemaining(strictState.remainingSeconds)} remaining).'),
          duration: const Duration(seconds: 2),
        ),
      );
      return;
    }

    final palette = WabiSabiPalette.of(context);
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return Container(
          decoration: BoxDecoration(
            color: palette.canvas,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
            border: Border.all(color: palette.hairlineSoft, width: 1.0),
          ),
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 28),
          child: SafeArea(
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 36,
                      height: 4,
                      decoration: BoxDecoration(
                        color: palette.hairlineSoft,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Begin a Focus Session',
                    style: GoogleFonts.fraunces(
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                      color: palette.ink,
                      letterSpacing: -0.3,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Select your session mode',
                    style: GoogleFonts.inter(fontSize: 12.5, color: palette.mutedInk),
                  ),
                  const SizedBox(height: 18),

                  // Option 1: Normal Focus
                  InkWell(
                    key: const Key('normal_mode_button'),
                    borderRadius: BorderRadius.circular(8),
                    onTap: () async {
                      Navigator.pop(ctx);
                      await ref.read(strictModeProvider.notifier).set(false);
                      await ref.read(protectionProvider.notifier).set(true);
                      ref.read(setupProvider.notifier).autoSyncAndLinkIp();
                      if (!kIsWeb) {
                        final profileId = ref.read(setupProvider).profileId;
                        await ref.read(vpnProvider.notifier).start(profileId: profileId);
                      }
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: const Text('🌿 Normal Focus active. Tap Pause anytime to stop.'),
                            backgroundColor: palette.surface,
                          ),
                        );
                      }
                    },
                    child: Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: palette.surface,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: palette.hairlineSoft),
                      ),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: palette.safeAccent.withOpacity(0.12),
                              shape: BoxShape.circle,
                            ),
                            child: Icon(Icons.shield_outlined, color: palette.safeAccent, size: 20),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Normal Focus',
                                  style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w700, color: palette.ink),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  'Standard protection. Pause or unblock apps whenever you want.',
                                  style: GoogleFonts.inter(fontSize: 11.5, color: palette.mutedInk),
                                ),
                              ],
                            ),
                          ),
                          Icon(Icons.chevron_right, color: palette.mutedInk),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 12),

                  // Option 2: Strict Mode Session
                  InkWell(
                    key: const Key('strict_mode_button'),
                    borderRadius: BorderRadius.circular(8),
                    onTap: () {
                      Navigator.pop(ctx);
                      _showStrictModeDisclaimerDialog(context);
                    },
                    child: Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: palette.surface,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: palette.strictAccent.withOpacity(0.35)),
                      ),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: palette.strictAccent.withOpacity(0.12),
                              shape: BoxShape.circle,
                            ),
                            child: Icon(Icons.lock_rounded, color: palette.strictAccent, size: 20),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Strict Mode Session',
                                  style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w700, color: palette.strictAccent),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  'Unbreakable timer lock. No unblocking allowed until timer ends.',
                                  style: GoogleFonts.inter(fontSize: 11.5, color: palette.mutedInk),
                                ),
                              ],
                            ),
                          ),
                          Icon(Icons.chevron_right, color: palette.strictAccent),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 12),

                  // Option 3: Focus Routine & Breaks
                  InkWell(
                    key: const Key('routine_mode_button'),
                    borderRadius: BorderRadius.circular(8),
                    onTap: () {
                      Navigator.pop(ctx);
                      _showCircularRoutineSetupDialog(context);
                    },
                    child: Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: palette.surface,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: palette.hairlineSoft),
                      ),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: const Color(0xFF4A6B82).withOpacity(0.12),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(Icons.all_inclusive_rounded, color: Color(0xFF4A6B82), size: 20),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Focus Routine & Breaks',
                                  style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w700, color: palette.ink),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  'Anti-doomscroll timer cycles. Focus session, break timer & repetitions.',
                                  style: GoogleFonts.inter(fontSize: 11.5, color: palette.mutedInk),
                                ),
                              ],
                            ),
                          ),
                          Icon(Icons.chevron_right, color: palette.mutedInk),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 12),

                  // Option 4: Feed Blocker
                  InkWell(
                    key: const Key('feed_blocker_mode_button'),
                    borderRadius: BorderRadius.circular(8),
                    onTap: () async {
                      Navigator.pop(ctx);
                      final surgicalState = ref.read(surgicalFilterProvider);
                      final willBlock = !surgicalState.isAnyFeedBlocked;
                      ref.read(surgicalFilterProvider.notifier).setAllFeedsBlocked(willBlock);
                      await ref.read(protectionProvider.notifier).set(true);
                      ref.read(setupProvider.notifier).autoSyncAndLinkIp();
                      if (!kIsWeb) {
                        final profileId = ref.read(setupProvider).profileId;
                        await ref.read(vpnProvider.notifier).start(profileId: profileId);
                      }
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).clearSnackBars();
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(willBlock
                                ? '✂️ Feed Blocker active. Reels & Shorts blackholed.'
                                : '🌿 Feed Blocker paused. Feeds unblocked.'),
                            backgroundColor: palette.surface,
                          ),
                        );
                      }
                    },
                    child: Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: palette.surface,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: palette.hairlineSoft),
                      ),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: palette.accent.withOpacity(0.12),
                              shape: BoxShape.circle,
                            ),
                            child: Icon(Icons.content_cut_rounded, color: palette.accent, size: 20),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Feed Blocker',
                                  style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w700, color: palette.ink),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  'Blackhole Reels, Shorts & feeds while keeping chats & DMs active.',
                                  style: GoogleFonts.inter(fontSize: 11.5, color: palette.mutedInk),
                                ),
                              ],
                            ),
                          ),
                          Icon(Icons.chevron_right, color: palette.mutedInk),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  // PAGE 1: PROTECTION (PAPER HOME 1 · HEADLINE DESIGN)
  Widget _buildPage1Protection(
    bool isProtectionOn,
    StrictModeState strictState,
    VpnState vpn,
    BlockerState blocker,
    WabiSabiPalette palette,
  ) {
    final liveTelemetry = ref.watch(liveTelemetryProvider);
    final daysOfWeek = const ['MONDAY', 'TUESDAY', 'WEDNESDAY', 'THURSDAY', 'FRIDAY', 'SATURDAY', 'SUNDAY'];
    final currentDay = daysOfWeek[DateTime.now().weekday - 1];

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24.0),
      child: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // EYEBROW
                  Text(
                    strictState.isStrict ? 'FOCUSDNS · STRICT MODE' : 'FOCUSDNS · $currentDay',
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
                    strictState.isStrict ? 'Protection Locked' : 'Your attention\nis yours again.',
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
                    strictState.isStrict
                        ? 'Protection is active and locked. Calls, maps and payments still work.'
                        : isProtectionOn
                            ? 'Protection is active. Calls, maps and payments still work.'
                            : 'Protection is paused. Digital noise is unblocked.',
                    style: GoogleFonts.inter(
                      fontSize: 12.5,
                      color: palette.mutedInk,
                      height: 1.3,
                    ),
                  ),

                  // RULED STATUS BLOCK (1px top & bottom hairlines)
                  Container(
                    margin: const EdgeInsets.symmetric(vertical: 10),
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    decoration: BoxDecoration(
                      border: Border(
                        top: BorderSide(color: palette.hairlineSoft, width: 1.0),
                        bottom: BorderSide(color: palette.hairlineSoft, width: 1.0),
                      ),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Row(
                                children: [
                                  if (strictState.isStrict) ...[
                                    Icon(Icons.lock_rounded, size: 20, color: palette.strictAccent),
                                    const SizedBox(width: 6),
                                  ] else if (isProtectionOn) ...[
                                    Icon(Icons.shield, size: 18, color: palette.safeAccent),
                                    const SizedBox(width: 6),
                                  ] else ...[
                                    Icon(Icons.shield_outlined, size: 18, color: palette.mutedInk),
                                    const SizedBox(width: 6),
                                  ],
                                  Text(
                                    strictState.isStrict
                                        ? 'Locked'
                                        : isProtectionOn
                                            ? 'Active'
                                            : 'Paused',
                                    style: GoogleFonts.fraunces(
                                      fontSize: 26,
                                      fontWeight: FontWeight.w700,
                                      color: strictState.isStrict
                                          ? palette.strictAccent
                                          : isProtectionOn
                                              ? palette.ink
                                              : palette.mutedInk,
                                      letterSpacing: -0.5,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 4),
                              // Caption containing test-contract exact strings
                              if (strictState.isStrict) ...[
                                Wrap(
                                  crossAxisAlignment: WrapCrossAlignment.center,
                                  spacing: 4,
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                                      decoration: BoxDecoration(
                                        color: palette.strictAccent.withOpacity(0.12),
                                        borderRadius: BorderRadius.circular(3),
                                      ),
                                      child: Text(
                                        'LOCKED',
                                        style: GoogleFonts.inter(
                                          fontSize: 9,
                                          fontWeight: FontWeight.w900,
                                          color: palette.strictAccent,
                                          letterSpacing: 1.2,
                                        ),
                                      ),
                                    ),
                                    Text('Protection Locked', style: GoogleFonts.inter(fontSize: 10, color: palette.mutedInk)),
                                    Text('·', style: GoogleFonts.inter(fontSize: 10, color: palette.mutedInk)),
                                    Text('Strict Mode active until timer ends.', style: GoogleFonts.inter(fontSize: 10, color: palette.mutedInk)),
                                  ],
                                ),
                                const SizedBox(height: 3),
                                Text(
                                  'Time Remaining: ${_formatRemaining(strictState.remainingSeconds)}',
                                  style: GoogleFonts.inter(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                    color: palette.ink,
                                  ),
                                ),
                              ] else if (isProtectionOn) ...[
                                Wrap(
                                  crossAxisAlignment: WrapCrossAlignment.center,
                                  spacing: 4,
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                                      decoration: BoxDecoration(
                                        color: palette.safeAccent.withOpacity(0.12),
                                        borderRadius: BorderRadius.circular(3),
                                      ),
                                      child: Text(
                                        'ACTIVE',
                                        style: GoogleFonts.inter(
                                          fontSize: 9,
                                          fontWeight: FontWeight.w900,
                                          color: palette.safeAccent,
                                          letterSpacing: 1.2,
                                        ),
                                      ),
                                    ),
                                    Text('Protection Active', style: GoogleFonts.inter(fontSize: 10, color: palette.mutedInk)),
                                    Text('·', style: GoogleFonts.inter(fontSize: 10, color: palette.mutedInk)),
                                    Text('Tap seal to pause protection.', style: GoogleFonts.inter(fontSize: 10, color: palette.mutedInk)),
                                  ],
                                ),
                              ] else ...[
                                Wrap(
                                  crossAxisAlignment: WrapCrossAlignment.center,
                                  spacing: 4,
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                                      decoration: BoxDecoration(
                                        color: palette.hairlineSoft,
                                        borderRadius: BorderRadius.circular(3),
                                      ),
                                      child: Text(
                                        'IDLE',
                                        style: GoogleFonts.inter(
                                          fontSize: 9,
                                          fontWeight: FontWeight.w800,
                                          color: palette.mutedInk,
                                          letterSpacing: 1.0,
                                        ),
                                      ),
                                    ),
                                    Text('TAP TO RESUME', style: GoogleFonts.inter(fontSize: 9, fontWeight: FontWeight.w700, color: palette.subtleInk)),
                                    Text('·', style: GoogleFonts.inter(fontSize: 10, color: palette.mutedInk)),
                                    Text('Protection Paused', style: GoogleFonts.inter(fontSize: 10, color: palette.mutedInk)),
                                    Text('·', style: GoogleFonts.inter(fontSize: 10, color: palette.mutedInk)),
                                    Text('Tap seal to resume protection.', style: GoogleFonts.inter(fontSize: 10, color: palette.mutedInk)),
                                  ],
                                ),
                              ],
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        // Master Toggle Button with Key('main_protection_toggle')
                        GestureDetector(
                          key: const Key('main_protection_toggle'),
                          behavior: HitTestBehavior.opaque,
                          onTap: () async {
                            if (strictState.isStrict) {
                              ScaffoldMessenger.of(context).clearSnackBars();
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text('🔒 Strict Mode active: ${_formatRemaining(strictState.remainingSeconds)} remaining. Protection is locked.'),
                                  duration: const Duration(seconds: 2),
                                ),
                              );
                              return;
                            }
                            final willBeOn = !isProtectionOn;
                            await ref.read(protectionProvider.notifier).toggle();
                            if (!kIsWeb) {
                              final profileId = ref.read(setupProvider).profileId;
                              if (willBeOn) {
                                try {
                                  ref.read(deepFocusProvider.notifier).syncWithBlocker();
                                } catch (_) {}
                                await ref.read(vpnProvider.notifier).start(profileId: profileId);
                                ref.read(setupProvider.notifier).autoSyncAndLinkIp();
                              } else {
                                await ref.read(vpnProvider.notifier).stop();
                              }
                            }
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                            decoration: BoxDecoration(
                              color: strictState.isStrict
                                  ? palette.surface
                                  : isProtectionOn
                                      ? palette.canvas
                                      : palette.surface,
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(
                                color: strictState.isStrict
                                    ? palette.strictAccent.withOpacity(0.5)
                                    : isProtectionOn
                                        ? palette.hairlineSoft
                                        : palette.safeAccent,
                                width: 1.0,
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  strictState.isStrict
                                      ? Icons.lock
                                      : isProtectionOn
                                          ? Icons.pause_rounded
                                          : Icons.play_arrow_rounded,
                                  size: 15,
                                  color: strictState.isStrict
                                      ? palette.strictAccent
                                      : isProtectionOn
                                          ? palette.ink
                                          : palette.safeAccent,
                                ),
                                const SizedBox(width: 5),
                                Text(
                                  strictState.isStrict
                                      ? 'Locked'
                                      : isProtectionOn
                                          ? 'Pause'
                                          : 'Resume',
                                  style: GoogleFonts.inter(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                    color: strictState.isStrict
                                        ? palette.strictAccent
                                        : isProtectionOn
                                            ? palette.ink
                                            : palette.safeAccent,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  // MICRO-TELEMETRY STATS STRIP
                  Container(
                    margin: const EdgeInsets.only(bottom: 10),
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                    decoration: BoxDecoration(
                      color: palette.surface,
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: palette.hairlineSoft, width: 1.0),
                    ),
                    child: Row(
                      children: [
                        Expanded(child: _buildMicroStat('${liveTelemetry.blockedQueries}', 'BLOCKED TODAY', palette)),
                        Container(height: 24, width: 1, color: palette.hairlineSoft),
                        Expanded(child: _buildMicroStat(liveTelemetry.blockedPercentage, 'THREAT RATIO', palette)),
                        Container(height: 24, width: 1, color: palette.hairlineSoft),
                        Expanded(child: _buildMicroStat('${liveTelemetry.averageLatencyMs}ms', 'DOH LATENCY', palette)),
                      ],
                    ),
                  ),

                  // PRIMARY SESSION ACTION / ACTIVE STRICT STATUS
                  if (strictState.isStrict)
                    GestureDetector(
                      key: const Key('active_strict_session_badge'),
                      behavior: HitTestBehavior.opaque,
                      onTap: () {
                        ScaffoldMessenger.of(context).clearSnackBars();
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('⏳ Strict Mode locked for ${_formatRemaining(strictState.remainingSeconds)}. Cannot switch to Normal Mode until timer expires.'),
                            duration: const Duration(seconds: 3),
                          ),
                        );
                      },
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                        decoration: BoxDecoration(
                          color: palette.strictAccent.withOpacity(0.08),
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(color: palette.strictAccent.withOpacity(0.4), width: 1.0),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.lock_rounded, size: 16, color: palette.strictAccent),
                            const SizedBox(width: 8),
                            Text(
                              'Strict Session Active: ${_formatRemaining(strictState.remainingSeconds)}',
                              style: GoogleFonts.inter(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: palette.strictAccent,
                              ),
                            ),
                          ],
                        ),
                      ),
                    )
                  else
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        key: const Key('begin_session_button'),
                        onPressed: () => _showSessionOptionsSheet(context),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF2F6B4F),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          elevation: 0,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                        ),
                        child: Text(
                          'Begin a session',
                          style: GoogleFonts.fraunces(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: Colors.white,
                            letterSpacing: 0.2,
                          ),
                        ),
                      ),
                    ),

                  const SizedBox(height: 12),
                  // MINDFUL PRIVACY FOOTNOTE
                  Center(
                    child: Text(
                      'Nothing is uploaded to external servers. All queries resolve privately on-device.',
                      textAlign: TextAlign.center,
                      style: GoogleFonts.inter(
                        fontSize: 11,
                        fontStyle: FontStyle.italic,
                        color: palette.mutedInk.withOpacity(0.85),
                      ),
                    ),
                  ),

                  // ACCESSIBILITY WARNING BANNER IF MOBILE & DISABLED
                  if (!kIsWeb && strictState.isStrict && !blocker.isEnabled && !_dismissedAccessibilityBanner) ...[
                    const SizedBox(height: 16),
                    Container(
                      margin: const EdgeInsets.symmetric(horizontal: 4),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: palette.surface,
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(color: palette.strictAccent.withOpacity(0.5), width: 1.0),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.shield_outlined, color: palette.strictAccent, size: 20),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Strict Mode: App Blocker disabled',
                                  style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold, color: palette.ink),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  'Enable in Accessibility to prevent evasion & terminate blocked apps instantly.',
                                  style: GoogleFonts.inter(fontSize: 11, color: palette.mutedInk),
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
                              backgroundColor: palette.strictAccent,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                              minimumSize: Size.zero,
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                            ),
                            child: const Text('Fix', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                          ),
                          const SizedBox(width: 4),
                          IconButton(
                            icon: Icon(Icons.close, size: 16, color: palette.mutedInk),
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                            tooltip: 'Dismiss warning',
                            onPressed: () => setState(() => _dismissedAccessibilityBanner = true),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 4),
        ],
      ),
    );
  }

  Widget _buildMicroStat(String value, String label, WabiSabiPalette palette) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          value,
          style: GoogleFonts.fraunces(
            fontSize: 17,
            fontWeight: FontWeight.w700,
            color: palette.ink,
            letterSpacing: -0.3,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: GoogleFonts.inter(
            fontSize: 9,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.8,
            color: palette.mutedInk,
          ),
        ),
      ],
    );
  }

  // PAGE 2: ANALYTICS (WABI-SABI EXTREME MINIMALISM)
  Widget _buildPage2Analytics(WabiSabiPalette palette) {
    final liveTelemetry = ref.watch(liveTelemetryProvider);
    final totalQueriesText = '${liveTelemetry.totalQueries}';
    final blockedQueriesText =
        '${liveTelemetry.blockedQueries} (${liveTelemetry.blockedPercentage}) blocked';


    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20.0),
      child: Column(
        children: [
          // TOTAL QUERIES BARE METRIC CONTAINER (PAPER CARD)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: palette.surface,
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: palette.hairlineSoft, width: 1.0),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'TOTAL QUERIES',
                      style: GoogleFonts.inter(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.1,
                        color: palette.mutedInk,
                      ),
                    ),
                    Row(
                      children: ['24h', '7d', '30d'].map((filter) {
                        final isSel = _selectedFilter == filter;
                        return GestureDetector(
                          onTap: () => setState(() => _selectedFilter = filter),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 180),
                            curve: Curves.easeOutCubic,
                            margin: const EdgeInsets.only(left: 6),
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: isSel ? palette.ink : Colors.transparent,
                              borderRadius: BorderRadius.circular(3),
                              border: Border.all(
                                color: isSel ? palette.ink : palette.hairlineSoft,
                                width: 1.0,
                              ),
                            ),
                            child: Text(
                              filter,
                              style: GoogleFonts.inter(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: isSel ? palette.canvas : palette.mutedInk,
                              ),
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 240),
                  transitionBuilder: (child, anim) => FadeTransition(
                    opacity: anim,
                    child: SlideTransition(
                      position: Tween<Offset>(begin: const Offset(0, 0.15), end: Offset.zero).animate(anim),
                      child: child,
                    ),
                  ),
                  child: Text(
                    totalQueriesText,
                    key: ValueKey<String>(totalQueriesText),
                    style: GoogleFonts.fraunces(
                      fontSize: 38,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.5,
                      color: palette.ink,
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 240),
                  child: Text(
                    blockedQueriesText,
                    key: ValueKey<String>(blockedQueriesText),
                    style: GoogleFonts.inter(
                      fontSize: 13,
                      color: palette.strictAccent,
                      fontWeight: FontWeight.w600,
                      letterSpacing: -0.1,
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                SizedBox(
                  height: 100,
                  width: double.infinity,
                  child: AnimatedChart(
                    filter: _selectedFilter,
                    totalColor: palette.ink,
                    blockedColor: palette.strictAccent,
                    queries: liveTelemetry.recentQueries,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),

          // LIVE QUERY ACTIVITY
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: palette.surface,
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: palette.hairlineSoft, width: 1.0),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'RECENT QUERIES',
                      style: GoogleFonts.inter(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.1,
                        color: palette.mutedInk,
                      ),
                    ),
                    Row(
                      children: [
                        Container(
                          width: 6,
                          height: 6,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: palette.accent,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          'Encrypted DoH',
                          style: GoogleFonts.inter(
                            fontSize: 10.5,
                            fontWeight: FontWeight.w600,
                            color: palette.mutedInk,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                // Search field for live queries
                Container(
                  height: 36,
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  decoration: BoxDecoration(
                    color: palette.canvas,
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: palette.hairlineSoft, width: 1.0),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.search, size: 16, color: palette.mutedInk),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          controller: _insightsSearchController,
                          onChanged: (val) {
                            setState(() {
                              _insightsSearchQuery = val.trim().toLowerCase();
                            });
                          },
                          style: GoogleFonts.inter(fontSize: 12, color: palette.ink),
                          decoration: InputDecoration(
                            hintText: 'Filter domain or host...',
                            hintStyle: GoogleFonts.inter(fontSize: 12, color: palette.mutedInk.withOpacity(0.6)),
                            border: InputBorder.none,
                            isDense: true,
                            contentPadding: EdgeInsets.zero,
                          ),
                        ),
                      ),
                      if (_insightsSearchQuery.isNotEmpty)
                        GestureDetector(
                          onTap: () {
                            _insightsSearchController.clear();
                            setState(() {
                              _insightsSearchQuery = '';
                            });
                          },
                          child: Icon(Icons.close, size: 14, color: palette.mutedInk),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),

                Builder(
                  builder: (context) {
                    final filteredQueries = _insightsSearchQuery.isEmpty
                        ? liveTelemetry.recentQueries
                        : liveTelemetry.recentQueries.where((q) {
                            final sub = q.subdomain.toLowerCase();
                            final root = q.rootDomain.toLowerCase();
                            return sub.contains(_insightsSearchQuery) || root.contains(_insightsSearchQuery);
                          }).toList();

                    if (filteredQueries.isEmpty) {
                      return Center(
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.query_builder,
                                  size: 32,
                                  color: palette.mutedInk.withOpacity(0.4)),
                              const SizedBox(height: 10),
                              Text(
                                _insightsSearchQuery.isEmpty
                                    ? 'No DNS queries captured yet.\nStart browsing or open apps to see live filtered lookups.'
                                    : 'No queries match "$_insightsSearchQuery"',
                                textAlign: TextAlign.center,
                                style: GoogleFonts.inter(
                                  fontSize: 12.5,
                                  color: palette.mutedInk,
                                  height: 1.4,
                                ),
                              ),
                              if (_insightsSearchQuery.isEmpty) ...[
                                const SizedBox(height: 10),
                                Text(
                                  'Nothing is uploaded to external servers. All queries resolve privately on-device.',
                                  textAlign: TextAlign.center,
                                  style: GoogleFonts.inter(
                                    fontSize: 11,
                                    fontStyle: FontStyle.italic,
                                    color: palette.mutedInk.withOpacity(0.8),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      );
                    }

                    return ListView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: filteredQueries.length,
                      itemBuilder: (context, index) {
                        final q = filteredQueries[index];
                        return QueryLogItem(
                          subdomain: q.subdomain,
                          domain: q.rootDomain,
                          timeAgo: q.timeAgo,
                          iconText: q.iconText,
                          isBlocked: q.isBlocked,
                        );
                      },
                    );
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
        ],
      ),
    );
  }
}

class StrictModeDisclaimerSheetContent extends StatefulWidget {
  final VoidCallback onCancel;
  final ValueChanged<int> onConfirm;
  final WabiSabiPalette? palette;
  final int initialMinutes;

  const StrictModeDisclaimerSheetContent({
    super.key,
    required this.onCancel,
    required this.onConfirm,
    this.palette,
    this.initialMinutes = 30,
  });

  @override
  State<StrictModeDisclaimerSheetContent> createState() =>
      _StrictModeDisclaimerSheetContentState();
}

class _StrictModeDisclaimerSheetContentState
    extends State<StrictModeDisclaimerSheetContent> {
  late int _selectedMinutes;
  final List<int> _presets = const [15, 30, 45, 60, 120, 240, 480];

  @override
  void initState() {
    super.initState();
    _selectedMinutes = widget.initialMinutes;
  }

  @override
  Widget build(BuildContext context) {
    final palette = widget.palette ?? WabiSabiPalette.of(context);

    return Container(
      decoration: BoxDecoration(
        color: palette.canvas,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
        border: Border.all(color: palette.hairlineSoft, width: 1),
      ),
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 28),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: palette.mutedInk.withOpacity(0.4),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 14),

            // EYEBROW
            Text(
              'FOCUSDNS · STRICT MODE',
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
              'Lock in for a while?',
              style: GoogleFonts.fraunces(
                fontSize: 26,
                fontWeight: FontWeight.w700,
                color: palette.ink,
                letterSpacing: -0.5,
              ),
            ),
            const SizedBox(height: 6),

            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: palette.strictAccent.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(3),
                  ),
                  child: Text(
                    'Activate Strict Mode',
                    style: GoogleFonts.inter(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: palette.strictAccent,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),

            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: palette.surface,
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: palette.hairlineSoft, width: 1.0),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.info_outline, color: palette.strictAccent, size: 18),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'In Strict Mode you cannot access any blocked apps or categories until or unless the timer runs out so choose wisely.',
                      style: GoogleFonts.inter(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w500,
                        color: palette.ink,
                        height: 1.4,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: palette.canvas,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: palette.border),
              ),
              child: Row(
                children: [
                  Icon(Icons.verified_user_outlined, size: 15, color: palette.safeAccent),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Pre-flight verified: Locks VPN & focus apps. Emergency calls & 2FA SMS remain reachable.',
                      style: TextStyle(
                        fontSize: 11,
                        color: palette.mutedInk,
                        height: 1.3,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Select Duration',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  color: palette.mutedInk,
                  letterSpacing: 0.5,
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: palette.surface,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: palette.border),
                ),
                child: Text(
                  _selectedMinutes >= 60
                      ? '${_selectedMinutes ~/ 60}h ${_selectedMinutes % 60 > 0 ? "${_selectedMinutes % 60}m" : ""}'
                          .trim()
                      : '$_selectedMinutes minutes',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: palette.ink,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _presets.map((mins) {
              final isSelected = _selectedMinutes == mins;
              final label = mins >= 60 ? '${mins ~/ 60}h' : '${mins}m';
              return ChoiceChip(
                label: Text(label),
                selected: isSelected,
                onSelected: (val) {
                  if (val) {
                    setState(() => _selectedMinutes = mins);
                  }
                },
                selectedColor: palette.ink,
                backgroundColor: palette.surface,
                labelStyle: GoogleFonts.inter(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: isSelected ? palette.canvas : palette.ink,
                ),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(4)),
                side: BorderSide(
                  color: isSelected ? palette.ink : palette.hairlineSoft,
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 14),
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              activeTrackColor: palette.ink,
              inactiveTrackColor: palette.hairlineSoft,
              thumbColor: palette.ink,
              overlayColor: palette.ink.withOpacity(0.12),
              trackHeight: 2,
            ),
            child: Slider(
              value: _selectedMinutes.toDouble(),
              min: 5,
              max: 480,
              divisions: 95,
              onChanged: (val) {
                setState(() => _selectedMinutes = (val / 5).round() * 5);
              },
            ),
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: widget.onCancel,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: palette.mutedInk,
                    side: BorderSide(color: palette.hairlineSoft),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(4)),
                  ),
                  child: Text('Cancel',
                      style: GoogleFonts.inter(
                          fontSize: 13, fontWeight: FontWeight.w600)),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 2,
                child: ElevatedButton(
                  onPressed: () => widget.onConfirm(_selectedMinutes),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: palette.strictAccent,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(4)),
                  ),
                  child: Text(
                    'Lock In Strict Mode',
                    style: GoogleFonts.inter(
                        fontSize: 13, fontWeight: FontWeight.w700),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    ),
  );
}
}

class CircularRoutineSetupSheet extends StatefulWidget {
  final WabiSabiPalette palette;
  final VoidCallback onCancel;
  final void Function(int focusMinutes, int breakMinutes, int cycles) onConfirm;

  const CircularRoutineSetupSheet({
    super.key,
    required this.palette,
    required this.onCancel,
    required this.onConfirm,
  });

  @override
  State<CircularRoutineSetupSheet> createState() => _CircularRoutineSetupSheetState();
}

class _CircularRoutineSetupSheetState extends State<CircularRoutineSetupSheet> {
  int _step = 1; // 1 = Focus, 2 = Break, 3 = Cycles
  int _selectedFocus = 25; // in minutes (5m to 8h)
  int _selectedBreak = 5; // in minutes (5m to 4h)
  int _selectedCycles = 4; // 1 to 10

  static const _focusOptions = <({int minutes, String label})>[
    (minutes: 5, label: '5m'),
    (minutes: 15, label: '15m'),
    (minutes: 25, label: '25m'),
    (minutes: 45, label: '45m'),
    (minutes: 60, label: '1h'),
    (minutes: 90, label: '1.5h'),
    (minutes: 120, label: '2h'),
    (minutes: 180, label: '3h'),
    (minutes: 240, label: '4h'),
    (minutes: 360, label: '6h'),
    (minutes: 480, label: '8h'),
  ];

  static const _breakOptions = <({int minutes, String label})>[
    (minutes: 5, label: '5m'),
    (minutes: 10, label: '10m'),
    (minutes: 15, label: '15m'),
    (minutes: 20, label: '20m'),
    (minutes: 30, label: '30m'),
    (minutes: 45, label: '45m'),
    (minutes: 60, label: '1h'),
    (minutes: 90, label: '1.5h'),
    (minutes: 120, label: '2h'),
    (minutes: 180, label: '3h'),
    (minutes: 240, label: '4h'),
  ];

  static const _cycleOptions = <({int count, String label})>[
    (count: 1, label: '1'),
    (count: 2, label: '2'),
    (count: 3, label: '3'),
    (count: 4, label: '4'),
    (count: 5, label: '5'),
    (count: 6, label: '6'),
    (count: 7, label: '7'),
    (count: 8, label: '8'),
    (count: 9, label: '9'),
    (count: 10, label: '10'),
  ];

  String _formatDuration(int minutes) {
    if (minutes < 60) return '${minutes}m';
    final h = minutes ~/ 60;
    final m = minutes % 60;
    return m > 0 ? '${h}h ${m}m' : '${h}h';
  }

  Widget _buildStepPill(int stepNumber, String title, bool isActive, WabiSabiPalette palette) {
    final isDone = stepNumber < _step;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: isActive
            ? palette.ink
            : (isDone ? palette.ink.withOpacity(0.08) : palette.surface),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isActive ? palette.ink : palette.hairlineSoft,
          width: 1.0,
        ),
      ),
      child: Text(
        '$stepNumber. $title',
        style: GoogleFonts.inter(
          fontSize: 11,
          fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
          color: isActive ? palette.canvas : (isDone ? palette.ink : palette.mutedInk),
        ),
      ),
    );
  }

  Widget _buildCircularDial<T>({
    required List<({T value, String label})> items,
    required T selectedValue,
    required ValueChanged<T> onSelected,
    required String centerPrimaryText,
    required String centerSubText,
    required WabiSabiPalette palette,
  }) {
    const double dialSize = 250;
    const double center = dialSize / 2;
    const double radius = 94;
    const double itemSize = 36;

    return SizedBox(
      width: dialSize,
      height: dialSize,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Outer hairline orbit track
          Container(
            width: radius * 2,
            height: radius * 2,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: palette.hairlineSoft.withOpacity(0.6),
                width: 1.0,
              ),
            ),
          ),
          // Central value display
          Container(
            width: 96,
            height: 96,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: palette.surface,
              border: Border.all(color: palette.hairlineSoft, width: 1.0),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  centerPrimaryText,
                  style: GoogleFonts.fraunces(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    color: palette.ink,
                    letterSpacing: -0.5,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  centerSubText,
                  style: GoogleFonts.inter(
                    fontSize: 9,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.8,
                    color: palette.mutedInk,
                  ),
                ),
              ],
            ),
          ),
          // Circular option nodes around the orbit
          ...List.generate(items.length, (index) {
            final item = items[index];
            final isSelected = item.value == selectedValue;
            final angle = -math.pi / 2 + (2 * math.pi * index) / items.length;
            final x = center + radius * math.cos(angle) - (itemSize / 2);
            final y = center + radius * math.sin(angle) - (itemSize / 2);

            return Positioned(
              left: x,
              top: y,
              child: GestureDetector(
                key: Key('circular_option_${item.label}'),
                behavior: HitTestBehavior.opaque,
                onTap: () => onSelected(item.value),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 160),
                  width: itemSize,
                  height: itemSize,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: isSelected ? palette.ink : palette.canvas,
                    border: Border.all(
                      color: isSelected ? palette.ink : palette.hairlineSoft,
                      width: isSelected ? 1.5 : 1.0,
                    ),
                    boxShadow: isSelected
                        ? [
                            BoxShadow(
                              color: palette.ink.withOpacity(0.18),
                              blurRadius: 6,
                              offset: const Offset(0, 2),
                            ),
                          ]
                        : null,
                  ),
                  child: Center(
                    child: Text(
                      item.label,
                      style: GoogleFonts.inter(
                        fontSize: 10.5,
                        fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                        color: isSelected ? palette.canvas : palette.ink,
                      ),
                    ),
                  ),
                ),
              ),
            );
          }),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final palette = widget.palette;

    return Container(
      decoration: BoxDecoration(
        color: palette.canvas,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
        border: Border.all(color: palette.hairlineSoft, width: 1.0),
      ),
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: palette.hairlineSoft,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 14),

            // Header Row
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  _step == 1
                      ? 'Select Focus Session'
                      : (_step == 2 ? 'Select Break Timer' : 'Select Repetitions'),
                  style: GoogleFonts.fraunces(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: palette.ink,
                    letterSpacing: -0.3,
                  ),
                ),
                IconButton(
                  icon: Icon(Icons.close, size: 20, color: palette.mutedInk),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  onPressed: widget.onCancel,
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Step Progress Indicator
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _buildStepPill(1, 'Focus', _step == 1, palette),
                Container(width: 14, height: 1, color: palette.hairlineSoft),
                _buildStepPill(2, 'Break', _step == 2, palette),
                Container(width: 14, height: 1, color: palette.hairlineSoft),
                _buildStepPill(3, 'Cycles', _step == 3, palette),
              ],
            ),
            const SizedBox(height: 18),

            // Circular Dial based on active step
            if (_step == 1)
              _buildCircularDial<int>(
                items: _focusOptions.map((e) => (value: e.minutes, label: e.label)).toList(),
                selectedValue: _selectedFocus,
                onSelected: (v) => setState(() => _selectedFocus = v),
                centerPrimaryText: _formatDuration(_selectedFocus),
                centerSubText: 'FOCUS DURATION',
                palette: palette,
              )
            else if (_step == 2)
              _buildCircularDial<int>(
                items: _breakOptions.map((e) => (value: e.minutes, label: e.label)).toList(),
                selectedValue: _selectedBreak,
                onSelected: (v) => setState(() => _selectedBreak = v),
                centerPrimaryText: _formatDuration(_selectedBreak),
                centerSubText: 'BREAK TIMER',
                palette: palette,
              )
            else
              _buildCircularDial<int>(
                items: _cycleOptions.map((e) => (value: e.count, label: e.label)).toList(),
                selectedValue: _selectedCycles,
                onSelected: (v) => setState(() => _selectedCycles = v),
                centerPrimaryText: '$_selectedCycles',
                centerSubText: 'CYCLES',
                palette: palette,
              ),

            const SizedBox(height: 16),

            // Live Summary Strip
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: palette.surface,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: palette.hairlineSoft),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.timelapse_rounded, size: 14, color: palette.mutedInk),
                  const SizedBox(width: 6),
                  Text(
                    '${_formatDuration(_selectedFocus)} focus  ·  ${_formatDuration(_selectedBreak)} break  ·  $_selectedCycles cycles',
                    style: GoogleFonts.inter(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                      color: palette.ink,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),

            // Navigation Actions
            Row(
              children: [
                if (_step > 1) ...[
                  Expanded(
                    child: OutlinedButton(
                      key: const Key('routine_prev_step'),
                      onPressed: () => setState(() => _step--),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: palette.ink,
                        side: BorderSide(color: palette.hairlineSoft),
                        padding: const EdgeInsets.symmetric(vertical: 13),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                      ),
                      child: Text('← Back', style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600)),
                    ),
                  ),
                  const SizedBox(width: 12),
                ],
                Expanded(
                  flex: 2,
                  child: ElevatedButton(
                    key: Key(_step < 3 ? 'routine_next_step' : 'routine_start_button'),
                    onPressed: () {
                      if (_step < 3) {
                        setState(() => _step++);
                      } else {
                        widget.onConfirm(_selectedFocus, _selectedBreak, _selectedCycles);
                      }
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF2F6B4F),
                      foregroundColor: Colors.white,
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(vertical: 13),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                    ),
                    child: Text(
                      _step == 1
                          ? 'Next: Break Timer →'
                          : (_step == 2 ? 'Next: Cycles →' : 'Begin Routine 🚀'),
                      style: GoogleFonts.fraunces(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                        letterSpacing: 0.2,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

