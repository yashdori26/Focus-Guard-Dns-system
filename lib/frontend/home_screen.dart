import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../state_management/providers.dart';
import 'profile_settings_sheet.dart';
import 'theme/wabi_sabi_theme.dart';
import 'more_screen.dart';
import 'tabs/deep_focus_tab.dart';
import 'tabs/logs_tab.dart';
import 'widgets.dart';

class FocusDNSHomeScreen extends ConsumerStatefulWidget {
  const FocusDNSHomeScreen({super.key});

  @override
  ConsumerState<FocusDNSHomeScreen> createState() => _FocusDNSHomeScreenState();
}

class _FocusDNSHomeScreenState extends ConsumerState<FocusDNSHomeScreen> {
  bool _showLogs = false;
  int _currentPage = 0;
  String _selectedFilter = '7d';
  String? _urlOverlay;

  @override
  void initState() {
    super.initState();
    _handleQueryParams();
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
      if (params.containsKey('dialog') && params['dialog'] == 'strict') {
        _urlOverlay = 'strict_dialog';
      } else if (params.containsKey('sheet') && params['sheet'] == 'profile') {
        _urlOverlay = 'profile_sheet';
      }
    } catch (_) {}
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
              padding: const EdgeInsets.symmetric(horizontal: 24.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  if (_currentPage == 0)
                    GestureDetector(
                      key: const Key('header_profile_pill'),
                      behavior: HitTestBehavior.opaque,
                      onTap: _openAllProfileSettingsSheet,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: palette.surface,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: palette.border),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 7,
                              height: 7,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: isProtectionOn ? palette.ink : palette.mutedInk,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              'My First Profile',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: palette.ink,
                                letterSpacing: -0.2,
                              ),
                            ),
                            const SizedBox(width: 4),
                            Icon(Icons.keyboard_arrow_down_rounded, size: 15, color: palette.mutedInk),
                          ],
                        ),
                      ),
                    )
                  else
                    Text(
                      titles[_currentPage],
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: palette.ink,
                        letterSpacing: -0.4,
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
                            shape: BoxShape.circle,
                            color: palette.surface,
                            border: Border.all(color: palette.border),
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
        onTap: () => setState(() => _currentPage = index),
        child: SizedBox(
          height: 60,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              AnimatedScale(
                scale: selected ? 1.14 : 1.0,
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeOutBack,
                child: Icon(
                  icon,
                  size: 22,
                  color: selected ? palette.ink : palette.mutedInk,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                label,
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 11,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  color: selected ? palette.ink : palette.mutedInk,
                  letterSpacing: -0.1,
                ),
              ),
              const SizedBox(height: 2),
              AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeOutCubic,
                width: selected ? 12 : 0,
                height: 2,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(1),
                  color: palette.ink,
                ),
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
        border: Border(top: BorderSide(color: palette.border)),
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
    Widget seg(String label, bool logs) {
      final sel = _showLogs == logs;
      return Expanded(
        child: GestureDetector(
          onTap: () => setState(() => _showLogs = logs),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOutCubic,
            padding: const EdgeInsets.symmetric(vertical: 10),
            decoration: BoxDecoration(
              color: sel ? palette.ink : Colors.transparent,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Center(
              child: Text(
                label,
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: sel ? palette.canvas : palette.mutedInk,
                  letterSpacing: -0.1,
                ),
              ),
            ),
          ),
        ),
      );
    }

    return Column(
      children: [
        Container(
          margin: const EdgeInsets.fromLTRB(20, 0, 20, 12),
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: palette.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: palette.border),
          ),
          child: Row(children: [seg('Analytics', false), seg('Logs', true)]),
        ),
        Expanded(
          child: _showLogs
              ? const SingleChildScrollView(
                  padding: EdgeInsets.all(20),
                  child: LogsTab(),
                )
              : _buildPage2Analytics(palette),
        ),
      ],
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

  void _showStrictModeDisclaimerDialog(BuildContext context) {
    final palette = WabiSabiPalette.of(context);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return StrictModeDisclaimerSheetContent(
          onCancel: () => Navigator.pop(ctx),
          onConfirm: (selectedMinutes) async {
            Navigator.pop(ctx);
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

  // PAGE 1: PROTECTION (WABI-SABI CHARCOAL EXTREME MINIMALISM)
  Widget _buildPage1Protection(
    bool isProtectionOn,
    StrictModeState strictState,
    VpnState vpn,
    BlockerState blocker,
    WabiSabiPalette palette,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24.0),
      child: Column(
        children: [
          Expanded(
            child: Center(
              child: SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // CIRCULAR INK SEAL MASTER SWITCH
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
                            await ref.read(vpnProvider.notifier).start(profileId: profileId);
                          } else {
                            await ref.read(vpnProvider.notifier).stop();
                          }
                        }
                      },
                      child: Container(
                        width: 160,
                        height: 160,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: strictState.isStrict
                              ? palette.sealStrict
                              : isProtectionOn
                                  ? palette.sealActive
                                  : palette.surface.withOpacity(0.4),
                          border: Border.all(
                            color: strictState.isStrict
                                ? palette.strictAccent
                                : isProtectionOn
                                    ? palette.sealActive
                                    : palette.border,
                            width: strictState.isStrict ? 2.5 : 2.0,
                          ),
                          boxShadow: strictState.isStrict
                              ? [
                                  BoxShadow(
                                    color: palette.strictAccent.withOpacity(0.12),
                                    blurRadius: 24,
                                    spreadRadius: 2,
                                  ),
                                ]
                              : null,
                        ),
                        child: strictState.isStrict
                            ? Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.lock_rounded, size: 28, color: palette.strictAccent),
                                  if (strictState.remainingSeconds > 0) ...[
                                    const SizedBox(height: 6),
                                    Text(
                                      _formatRemaining(strictState.remainingSeconds),
                                      style: TextStyle(
                                        fontSize: 20,
                                        fontWeight: FontWeight.w800,
                                        color: palette.ink,
                                        letterSpacing: 0.5,
                                      ),
                                    ),
                                  ],
                                  const SizedBox(height: 4),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: palette.strictAccent.withOpacity(0.14),
                                      borderRadius: BorderRadius.circular(4),
                                      border: Border.all(
                                        color: palette.strictAccent.withOpacity(0.3),
                                        width: 0.8,
                                      ),
                                    ),
                                    child: Text(
                                      'LOCKED',
                                      style: TextStyle(
                                        fontSize: 9,
                                        fontWeight: FontWeight.w900,
                                        color: palette.strictAccent,
                                        letterSpacing: 1.5,
                                      ),
                                    ),
                                  ),
                                ],
                              )
                            : Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    isProtectionOn ? Icons.shield : Icons.shield_outlined,
                                    size: 52,
                                    color: isProtectionOn
                                        ? palette.sealActiveText
                                        : palette.mutedInk,
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    isProtectionOn ? 'ACTIVE' : 'IDLE',
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                      letterSpacing: 1.2,
                                      color: isProtectionOn
                                          ? palette.sealActiveText
                                          : palette.mutedInk,
                                    ),
                                  ),
                                  if (!isProtectionOn) ...[
                                    const SizedBox(height: 3),
                                    Text(
                                      'TAP TO RESUME',
                                      style: TextStyle(
                                        fontSize: 9,
                                        fontWeight: FontWeight.w700,
                                        letterSpacing: 0.8,
                                        color: palette.subtleInk,
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                      ),
                    ),
                    const SizedBox(height: 22),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (strictState.isStrict) ...[
                          Icon(Icons.lock, size: 20, color: palette.strictAccent),
                          const SizedBox(width: 8),
                        ],
                        Text(
                          strictState.isStrict
                              ? 'Protection Locked'
                              : isProtectionOn
                                  ? 'Protection Active'
                                  : 'Protection Paused',
                          style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                            color: strictState.isStrict
                                ? palette.ink
                                : isProtectionOn
                                    ? palette.ink
                                    : palette.mutedInk,
                            letterSpacing: -0.3,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      strictState.isStrict
                          ? 'Strict Mode active until timer ends.'
                          : isProtectionOn
                              ? 'Tap seal to pause protection.'
                              : 'Tap seal to resume protection.',
                      style: TextStyle(fontSize: 13, color: palette.mutedInk),
                    ),
                    if (strictState.isStrict) ...[
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
                        decoration: BoxDecoration(
                          color: palette.surface,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: palette.strictAccent.withOpacity(0.3)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.timer_outlined, size: 15, color: palette.strictAccent),
                            const SizedBox(width: 8),
                            Text(
                              strictState.remainingSeconds > 0
                                  ? 'Time Remaining: ${_formatRemaining(strictState.remainingSeconds)}'
                                  : 'Strict Mode Active',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: palette.ink,
                                letterSpacing: 0.3,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],

                    // UNBOXED CLEAN MICRO-TELEMETRY STRIP (addresses empty space critique)
                    Container(
                      margin: const EdgeInsets.symmetric(vertical: 20),
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      decoration: BoxDecoration(
                        color: palette.surface,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: palette.border),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          _buildMicroStat('1,420', 'BLOCKED TODAY', palette),
                          Container(height: 24, width: 1, color: palette.border),
                          _buildMicroStat('28.4%', 'THREAT RATIO', palette),
                          Container(height: 24, width: 1, color: palette.border),
                          _buildMicroStat('14ms', 'DOH LATENCY', palette),
                        ],
                      ),
                    ),

                    // MINIMAL MODE SELECTOR CAPSULE (NORMAL / STRICT)
                    Container(
                      width: double.infinity,
                      constraints: const BoxConstraints(maxWidth: 320),
                      padding: const EdgeInsets.all(3),
                      decoration: BoxDecoration(
                        color: palette.surface,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: palette.border),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: GestureDetector(
                              key: const Key('normal_mode_button'),
                              behavior: HitTestBehavior.opaque,
                              onTap: () {
                                if (strictState.isStrict) {
                                  ScaffoldMessenger.of(context).clearSnackBars();
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text('⏳ Strict Mode locked for ${_formatRemaining(strictState.remainingSeconds)}. Cannot switch to Normal Mode until timer expires.'),
                                      duration: const Duration(seconds: 3),
                                    ),
                                  );
                                  return;
                                }
                                ref.read(strictModeProvider.notifier).set(false);
                              },
                              child: Container(
                                padding: const EdgeInsets.symmetric(vertical: 9),
                                decoration: BoxDecoration(
                                  color: !strictState.isStrict
                                      ? palette.ink
                                      : Colors.transparent,
                                  borderRadius: BorderRadius.circular(9),
                                ),
                                child: Center(
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      if (!strictState.isStrict) ...[
                                        Container(
                                          width: 5,
                                          height: 5,
                                          decoration: BoxDecoration(
                                            shape: BoxShape.circle,
                                            color: palette.canvas,
                                          ),
                                        ),
                                        const SizedBox(width: 6),
                                      ],
                                      Text(
                                        'Normal',
                                        style: TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.bold,
                                          color: !strictState.isStrict
                                              ? palette.canvas
                                              : palette.mutedInk,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 4),
                          Expanded(
                            child: GestureDetector(
                              key: const Key('strict_mode_button'),
                              behavior: HitTestBehavior.opaque,
                              onTap: () {
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
                                _showStrictModeDisclaimerDialog(context);
                              },
                              child: Container(
                                padding: const EdgeInsets.symmetric(vertical: 9),
                                decoration: BoxDecoration(
                                  color: strictState.isStrict
                                      ? palette.strictAccent
                                      : palette.strictAccent.withOpacity(0.08),
                                  borderRadius: BorderRadius.circular(9),
                                  border: Border.all(
                                    color: strictState.isStrict
                                        ? palette.strictAccent
                                        : palette.strictAccent.withOpacity(0.35),
                                    width: 1.0,
                                  ),
                                ),
                                child: Center(
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        strictState.isStrict ? Icons.lock : Icons.lock_outline,
                                        size: 13,
                                        color: strictState.isStrict ? Colors.white : palette.strictAccent,
                                      ),
                                      const SizedBox(width: 5),
                                      Text(
                                        'Strict',
                                        style: TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.bold,
                                          color: strictState.isStrict ? Colors.white : palette.ink,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 22),

                    // ACCESSIBILITY WARNING BANNER IF MOBILE & DISABLED
                    if (!kIsWeb && strictState.isStrict && !blocker.isEnabled) ...[
                      const SizedBox(height: 16),
                      Container(
                        margin: const EdgeInsets.symmetric(horizontal: 16),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: palette.surface,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: palette.strictAccent.withOpacity(0.5)),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.shield_outlined, color: palette.strictAccent, size: 20),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                'Strict Mode: App Blocker disabled. Enable in Accessibility to prevent evasion.',
                                style: TextStyle(fontSize: 12, color: palette.ink),
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
                              ),
                              child: const Text('Fix', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),

          const SizedBox(height: 12),
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
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w800,
            color: palette.ink,
            letterSpacing: -0.3,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: TextStyle(
            fontSize: 9,
            fontWeight: FontWeight.bold,
            letterSpacing: 0.8,
            color: palette.mutedInk,
          ),
        ),
      ],
    );
  }

  // PAGE 2: ANALYTICS (WABI-SABI EXTREME MINIMALISM)
  Widget _buildPage2Analytics(WabiSabiPalette palette) {
    String totalQueriesText = "14,566";
    String blockedQueriesText = "779 (5%) blocked";

    if (_selectedFilter == '24h') {
      totalQueriesText = "33";
      blockedQueriesText = "0 (0%) blocked";
    } else if (_selectedFilter == '30d') {
      totalQueriesText = "66,190";
      blockedQueriesText = "2,732 (4%) blocked";
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20.0),
      child: Column(
        children: [
          // TOTAL QUERIES BARE METRIC CONTAINER
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: palette.surface,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: palette.border, width: 1),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'TOTAL QUERIES',
                      style: GoogleFonts.plusJakartaSans(
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
                            duration: const Duration(milliseconds: 200),
                            curve: Curves.easeOutCubic,
                            margin: const EdgeInsets.only(left: 6),
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: isSel ? palette.ink : Colors.transparent,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              filter,
                              style: GoogleFonts.plusJakartaSans(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
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
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 34,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -1,
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
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 13,
                      color: palette.strictAccent,
                      fontWeight: FontWeight.w700,
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
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // LIVE QUERY ACTIVITY
          Expanded(
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: palette.surface,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: palette.border, width: 1),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'RECENT QUERIES',
                        style: GoogleFonts.plusJakartaSans(
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
                              color: palette.strictAccent,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            'Encrypted DoH',
                            style: GoogleFonts.plusJakartaSans(
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
                  Expanded(
                    child: ListView(
                      children: const [
                        QueryLogItem(
                          subdomain: 'api.',
                          domain: 'instagram.com',
                          timeAgo: 'Just now',
                          iconText: 'IG',
                        ),
                        QueryLogItem(
                          subdomain: 'rr1---sn-oxu.',
                          domain: 'googlevideo.com',
                          timeAgo: '2s ago',
                          iconText: 'YT',
                        ),
                        QueryLogItem(
                          subdomain: 'telemetry.',
                          domain: 'tiktokv.com',
                          timeAgo: '5s ago',
                          iconText: 'TT',
                          isBlocked: true,
                        ),
                        QueryLogItem(
                          subdomain: 'adservice.',
                          domain: 'google.com',
                          timeAgo: '12s ago',
                          iconText: 'AD',
                          isBlocked: true,
                        ),
                        QueryLogItem(
                          subdomain: 'gateway.',
                          domain: 'discord.gg',
                          timeAgo: '28s ago',
                          iconText: 'DC',
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}

class StrictModeDisclaimerSheetContent extends StatefulWidget {
  final VoidCallback onCancel;
  final ValueChanged<int> onConfirm;
  final WabiSabiPalette? palette;

  const StrictModeDisclaimerSheetContent({
    super.key,
    required this.onCancel,
    required this.onConfirm,
    this.palette,
  });

  @override
  State<StrictModeDisclaimerSheetContent> createState() =>
      _StrictModeDisclaimerSheetContentState();
}

class _StrictModeDisclaimerSheetContentState
    extends State<StrictModeDisclaimerSheetContent> {
  int _selectedMinutes = 30;
  final List<int> _presets = const [15, 30, 45, 60, 120, 240, 480];

  @override
  Widget build(BuildContext context) {
    final palette = widget.palette ?? WabiSabiPalette.of(context);

    return Container(
      decoration: BoxDecoration(
        color: palette.canvas,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        border: Border(
          top: BorderSide(color: palette.border, width: 1),
          left: BorderSide(color: palette.border, width: 1),
          right: BorderSide(color: palette.border, width: 1),
        ),
      ),
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
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
          const SizedBox(height: 18),
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: palette.surface,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: palette.border),
                ),
                child: Icon(Icons.lock_outline,
                    color: palette.strictAccent, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Activate Strict Mode',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: palette.ink,
                        letterSpacing: -0.3,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Unbreakable Focus Session',
                      style: TextStyle(fontSize: 12, color: palette.mutedInk),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: palette.surface,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: palette.border),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.info_outline, color: palette.strictAccent, size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'In Strict Mode you cannot access any blocked apps or categories until or unless the timer runs out so choose wisely.',
                    style: TextStyle(
                      fontSize: 13,
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
                Icon(Icons.shield_outlined, size: 15, color: palette.mutedInk),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Locks VPN disconnect, enforces Deep Focus apps & blocks evasion.',
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
          const SizedBox(height: 18),
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
                labelStyle: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: isSelected ? palette.canvas : palette.ink,
                ),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8)),
                side: BorderSide(
                  color: isSelected ? palette.ink : palette.border,
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 14),
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              activeTrackColor: palette.ink,
              inactiveTrackColor: palette.border,
              thumbColor: palette.ink,
              overlayColor: palette.ink.withOpacity(0.12),
              trackHeight: 3,
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
                    side: BorderSide(color: palette.border),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                  child: const Text('Cancel',
                      style:
                          TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 2,
                child: ElevatedButton(
                  onPressed: () => widget.onConfirm(_selectedMinutes),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: palette.ink,
                    foregroundColor: palette.canvas,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                  child: const Text(
                    'Lock In Strict Mode',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

