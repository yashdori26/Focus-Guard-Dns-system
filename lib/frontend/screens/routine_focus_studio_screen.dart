import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../backend/blocker_service.dart';
import '../../engine/routine/routine_state_machine.dart';
import '../../state_management/providers.dart';
import '../theme/wabi_sabi_theme.dart';

/// Riverpod provider for the industrial-grade RoutineStateMachine.
final routineEngineProvider = ChangeNotifierProvider<RoutineStateMachine>((ref) {
  return RoutineStateMachine(
    onPhaseTransition: (oldPhase, newPhase) {
      if (newPhase == RoutinePhaseState.focusSession || newPhase == RoutinePhaseState.preparationGrace) {
        ref.read(protectionProvider.notifier).set(true);
        final vpn = ref.read(vpnProvider);
        if (!vpn.isRunning) {
          final profileId = ref.read(setupProvider).profileId;
          ref.read(vpnProvider.notifier).start(profileId: profileId);
        }
      }
    },
    onForegroundAppKill: () async {
      await FocusDnsBlockerManager.closeActiveBlockedApp();
    },
  );
});

/// Dedicated full-screen studio for managing and running anti-doomscroll focus routines.
class RoutineFocusStudioScreen extends ConsumerStatefulWidget {
  const RoutineFocusStudioScreen({super.key});

  @override
  ConsumerState<RoutineFocusStudioScreen> createState() => _RoutineFocusStudioScreenState();
}

class _RoutineFocusStudioScreenState extends ConsumerState<RoutineFocusStudioScreen>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late AnimationController _pulseController;
  int _selectedFocusMinutes = 25;
  int _selectedBreakMinutes = 5;
  int _selectedCycles = 4;
  bool _isEngaging = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat(reverse: true);

    Future.microtask(() {
      ref.read(vpnProvider.notifier).checkStatus();
      ref.read(blockerProvider.notifier).checkStatus();
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      ref.read(vpnProvider.notifier).checkStatus();
      ref.read(blockerProvider.notifier).checkStatus();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _pulseController.dispose();
    super.dispose();
  }

  void _applyPreset(RoutineScheduleConfig preset) {
    setState(() {
      _selectedFocusMinutes = preset.focusMinutes;
      _selectedBreakMinutes = preset.breakMinutes.clamp(1, 30);
      _selectedCycles = preset.totalCycles;
    });

    ref.read(routineEngineProvider).updateConfig(
      RoutineScheduleConfig(
        focusMinutes: _selectedFocusMinutes,
        breakMinutes: _selectedBreakMinutes,
        totalCycles: _selectedCycles,
        label: preset.label,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final palette = WabiSabiPalette.of(context);
    final engine = ref.watch(routineEngineProvider);
    final snapshot = engine.snapshot;

    return Scaffold(
      backgroundColor: palette.canvas,
      appBar: AppBar(
        backgroundColor: palette.canvas,
        elevation: 0,
        iconTheme: IconThemeData(color: palette.ink),
        title: Text(
          'Focus Routine Studio',
          style: GoogleFonts.plusJakartaSans(
            color: palette.ink,
            fontSize: 18,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.3,
          ),
        ),
        actions: [
          Container(
            margin: const EdgeInsets.only(right: 16),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: snapshot.isRunning
                  ? (snapshot.isFocusActive ? palette.ink : palette.strictAccent).withOpacity(0.12)
                  : palette.surface,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: snapshot.isRunning ? palette.border : Colors.transparent,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: snapshot.isRunning
                        ? (snapshot.isFocusActive ? palette.ink : palette.strictAccent)
                        : palette.mutedInk,
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  snapshot.isRunning
                      ? (snapshot.isFocusActive ? 'FOCUSING' : 'BREAK')
                      : 'STANDBY',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.8,
                    color: palette.ink,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // 1. RADIAL CIRCULAR TIMER DISPLAY
              _buildRadialTimerDisplay(snapshot, palette),

              const SizedBox(height: 24),

              // 2. CYCLE PROGRESS INDICATOR
              _buildCycleDots(snapshot, palette),

              const SizedBox(height: 28),

              // 3. IF IDLE: PRESET & DURATION CONTROLS
              if (!snapshot.isRunning) ...[
                _buildPresetSelector(palette),
                const SizedBox(height: 20),
                _buildCustomConfigCard(palette),
                const SizedBox(height: 20),
                _buildShieldReadinessCard(palette),
                const SizedBox(height: 24),
                _buildStartButton(engine, palette),
              ] else ...[
                // ACTIVE ROUTINE CONTROLS & STATUS CARD
                _buildActiveStatusCard(snapshot, palette),
                const SizedBox(height: 20),
                _buildEmergencyCancelButton(engine, palette),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildRadialTimerDisplay(RoutineSnapshot snapshot, WabiSabiPalette palette) {
    final progress = snapshot.phaseProgress;
    final remainingSeconds = snapshot.remainingSecondsInPhase;
    final minutes = remainingSeconds ~/ 60;
    final seconds = remainingSeconds % 60;
    final timeStr = snapshot.isRunning
        ? '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}'
        : '${_selectedFocusMinutes.toString().padLeft(2, '0')}:00';

    final isUrgentGrace = snapshot.phase == RoutinePhaseState.breakExpiringGrace;

    return Center(
      child: AnimatedBuilder(
        animation: _pulseController,
        builder: (context, child) {
          final pulseVal = isUrgentGrace ? _pulseController.value * 6 : 0.0;

          return Container(
            width: 250,
            height: 250,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              boxShadow: isUrgentGrace
                  ? [
                      BoxShadow(
                        color: palette.strictAccent.withOpacity(0.3),
                        blurRadius: 16 + pulseVal,
                        spreadRadius: 4 + (pulseVal / 2),
                      )
                    ]
                  : [],
            ),
            child: CustomPaint(
              painter: _StudioTimerPainter(
                progress: progress,
                trackColor: palette.surface,
                progressColor: snapshot.isFocusActive
                    ? palette.ink
                    : (isUrgentGrace ? palette.strictAccent : const Color(0xFF27AE60)),
                strokeWidth: 14,
              ),
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      snapshot.statusMessage,
                      textAlign: TextAlign.center,
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.5,
                        color: isUrgentGrace ? palette.strictAccent : palette.mutedInk,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      timeStr,
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 48,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -1.5,
                        color: palette.ink,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      snapshot.isRunning
                          ? 'Cycle ${snapshot.currentCycle} of ${snapshot.config.totalCycles}'
                          : '${_selectedCycles} Cycles Planned',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: palette.mutedInk,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildCycleDots(RoutineSnapshot snapshot, WabiSabiPalette palette) {
    final total = snapshot.isRunning ? snapshot.config.totalCycles : _selectedCycles;
    final current = snapshot.currentCycle;

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(total, (index) {
        final cycleNum = index + 1;
        final isCompleted = snapshot.isRunning && cycleNum < current;
        final isCurrent = snapshot.isRunning && cycleNum == current;

        return AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          margin: const EdgeInsets.symmetric(horizontal: 4),
          width: isCurrent ? 28 : 10,
          height: 10,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(5),
            color: isCompleted
                ? palette.ink
                : (isCurrent
                    ? (snapshot.isFocusActive ? palette.ink : palette.strictAccent)
                    : palette.border),
          ),
        );
      }),
    );
  }

  Widget _buildPresetSelector(WabiSabiPalette palette) {
    final presets = [
      RoutineScheduleConfig.pomodoro,
      RoutineScheduleConfig.deepFlow,
      RoutineScheduleConfig.ultraNinety,
      RoutineScheduleConfig.marathonFourHour,
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'RECOMMENDED PROTOCOLS',
          style: GoogleFonts.plusJakartaSans(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.1,
            color: palette.mutedInk,
          ),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: presets.map((preset) {
            final isSelected = _selectedFocusMinutes == preset.focusMinutes &&
                _selectedBreakMinutes == preset.breakMinutes &&
                _selectedCycles == preset.totalCycles;

            return GestureDetector(
              onTap: () => _applyPreset(preset),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: isSelected ? palette.ink : palette.surface,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: isSelected ? palette.ink : palette.border,
                  ),
                ),
                child: Text(
                  preset.label,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: isSelected ? palette.canvas : palette.ink,
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  Widget _buildCustomConfigCard(WabiSabiPalette palette) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: palette.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'CUSTOM PROTOCOL TUNING',
            style: GoogleFonts.plusJakartaSans(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.1,
              color: palette.mutedInk,
            ),
          ),
          const SizedBox(height: 16),

          // Focus duration slider
          _buildSliderRow(
            label: 'Focus Session Duration',
            valueText: '$_selectedFocusMinutes min',
            value: _selectedFocusMinutes.toDouble(),
            min: 5,
            max: 180,
            divisions: 35,
            onChanged: (val) {
              setState(() => _selectedFocusMinutes = val.toInt());
            },
            palette: palette,
          ),

          const Divider(height: 24),

          // Break duration slider (STRICT 30m CLAMP)
          _buildSliderRow(
            label: 'Break Duration (Max 30m)',
            valueText: '$_selectedBreakMinutes min',
            value: _selectedBreakMinutes.toDouble(),
            min: 1,
            max: 30, // GUARANTEED CEILING
            divisions: 29,
            onChanged: (val) {
              setState(() => _selectedBreakMinutes = val.toInt().clamp(1, 30));
            },
            palette: palette,
          ),

          const Divider(height: 24),

          // Total cycles counter
          _buildSliderRow(
            label: 'Cycle Repetitions',
            valueText: '$_selectedCycles cycles',
            value: _selectedCycles.toDouble(),
            min: 1,
            max: 8,
            divisions: 7,
            onChanged: (val) {
              setState(() => _selectedCycles = val.toInt());
            },
            palette: palette,
          ),
        ],
      ),
    );
  }

  Widget _buildSliderRow({
    required String label,
    required String valueText,
    required double value,
    required double min,
    required double max,
    required int divisions,
    required ValueChanged<double> onChanged,
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
              style: GoogleFonts.plusJakartaSans(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: palette.ink,
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: palette.canvas,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: palette.border),
              ),
              child: Text(
                valueText,
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  color: palette.ink,
                ),
              ),
            ),
          ],
        ),
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            activeTrackColor: palette.ink,
            inactiveTrackColor: palette.border,
            thumbColor: palette.ink,
            overlayColor: palette.ink.withOpacity(0.1),
            trackHeight: 4,
          ),
          child: Slider(
            value: value,
            min: min,
            max: max,
            divisions: divisions,
            onChanged: onChanged,
          ),
        ),
      ],
    );
  }

  Widget _buildShieldReadinessCard(WabiSabiPalette palette) {
    final vpn = ref.watch(vpnProvider);
    final blocker = ref.watch(blockerProvider);
    final isProtected = ref.watch(protectionProvider);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: palette.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.health_and_safety_outlined, size: 18, color: palette.ink),
              const SizedBox(width: 8),
              Text(
                'Protection Readiness',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: palette.ink,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _buildReadinessRow(
            title: 'DNS Sinkhole Shield',
            subtitle: isProtected ? 'Protection Active' : 'Protection Paused (Unprotected)',
            isReady: isProtected,
            palette: palette,
            actionLabel: isProtected ? null : 'Resume',
            onAction: () => ref.read(protectionProvider.notifier).set(true),
          ),
          const Divider(height: 16),
          _buildReadinessRow(
            title: 'Local VPN Tunnel',
            subtitle: vpn.isRunning ? 'DNS Queries Intercepted' : 'VPN Disconnected',
            isReady: vpn.isRunning,
            palette: palette,
            actionLabel: vpn.isRunning ? null : 'Connect',
            onAction: () async {
              final profileId = ref.read(setupProvider).profileId;
              await ref.read(vpnProvider.notifier).start(profileId: profileId);
            },
          ),
          if (!kIsWeb && Platform.isAndroid) ...[
            const Divider(height: 16),
            _buildReadinessRow(
              title: 'Shorts & App Blocker',
              subtitle: blocker.isEnabled ? 'Accessibility Active' : 'Accessibility Disabled',
              isReady: blocker.isEnabled,
              palette: palette,
              actionLabel: blocker.isEnabled ? null : 'Enable',
              onAction: () => ref.read(blockerProvider.notifier).openSettings(),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildReadinessRow({
    required String title,
    required String subtitle,
    required bool isReady,
    required WabiSabiPalette palette,
    String? actionLabel,
    VoidCallback? onAction,
  }) {
    final statusColor = isReady ? const Color(0xFF27AE60) : palette.strictAccent;
    return Row(
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(shape: BoxShape.circle, color: statusColor),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: palette.ink,
                ),
              ),
              Text(
                subtitle,
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 11,
                  color: palette.mutedInk,
                ),
              ),
            ],
          ),
        ),
        if (actionLabel != null && onAction != null)
          TextButton(
            onPressed: onAction,
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: Text(
              actionLabel,
              style: GoogleFonts.plusJakartaSans(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: palette.ink,
              ),
            ),
          ),
      ],
    );
  }

  Future<void> _handleStartRoutine(RoutineStateMachine engine, WabiSabiPalette palette) async {
    setState(() => _isEngaging = true);
    try {
      // 1. Force enable protection
      await ref.read(protectionProvider.notifier).set(true);

      // 2. Link IP / sync with server
      ref.read(setupProvider.notifier).autoSyncAndLinkIp();

      // 3. Ensure VPN is started
      final vpnState = ref.read(vpnProvider);
      if (!vpnState.isRunning) {
        final profileId = ref.read(setupProvider).profileId;
        final vpnOk = await ref.read(vpnProvider.notifier).start(profileId: profileId);
        if (!vpnOk && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text('⚠️ VPN permission requested. Please accept the Android VPN dialog.'),
              backgroundColor: palette.strictAccent,
            ),
          );
        }
      }

      // 4. If on Android and accessibility blocker is disabled, prompt user
      if (!kIsWeb && Platform.isAndroid) {
        final bool isBlockerOn = await FocusDnsBlockerManager.isAccessibilityServiceEnabled();
        if (!isBlockerOn && mounted) {
          final proceed = await showDialog<bool>(
            context: context,
            builder: (ctx) {
              final pal = WabiSabiPalette.of(ctx);
              return AlertDialog(
                backgroundColor: pal.surface,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                title: Row(
                  children: [
                    Icon(Icons.shield_outlined, color: pal.strictAccent, size: 24),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Enable Shorts & App Blocker',
                        style: GoogleFonts.plusJakartaSans(
                          fontWeight: FontWeight.w700,
                          fontSize: 15,
                          color: pal.ink,
                        ),
                      ),
                    ),
                  ],
                ),
                content: Text(
                  'To instantly close YouTube Shorts and Instagram Reels during your Focus Routine, enable FocusDNS in Android Accessibility Settings.\n\nDNS protection & VPN are active.',
                  style: GoogleFonts.plusJakartaSans(fontSize: 12, color: pal.mutedInk, height: 1.4),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(ctx, true),
                    child: Text('Start (VPN Only)', style: TextStyle(color: pal.mutedInk)),
                  ),
                  ElevatedButton(
                    onPressed: () async {
                      Navigator.pop(ctx, true);
                      await FocusDnsBlockerManager.openAccessibilitySettings();
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: pal.ink,
                      foregroundColor: pal.canvas,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    child: const Text('Open Settings'),
                  ),
                ],
              );
            },
          );
          if (proceed != true) {
            return;
          }
        }
      }

      if (!mounted) return;

      engine.updateConfig(
        RoutineScheduleConfig(
          focusMinutes: _selectedFocusMinutes,
          breakMinutes: _selectedBreakMinutes.clamp(1, 30),
          totalCycles: _selectedCycles,
        ),
      );
      engine.startRoutine();
    } finally {
      if (mounted) {
        setState(() => _isEngaging = false);
      }
    }
  }

  Widget _buildStartButton(RoutineStateMachine engine, WabiSabiPalette palette) {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        onPressed: _isEngaging ? null : () => _handleStartRoutine(engine, palette),
        style: ElevatedButton.styleFrom(
          backgroundColor: palette.ink,
          foregroundColor: palette.canvas,
          padding: const EdgeInsets.symmetric(vertical: 16),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          elevation: 0,
        ),
        child: _isEngaging
            ? SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: palette.canvas,
                ),
              )
            : Text(
                'ENGAGE ANTI-DOOMSCROLL ROUTINE',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.5,
                ),
              ),
      ),
    );
  }

  Widget _buildActiveStatusCard(RoutineSnapshot snapshot, WabiSabiPalette palette) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: snapshot.phase == RoutinePhaseState.breakExpiringGrace
              ? palette.strictAccent
              : palette.border,
          width: snapshot.phase == RoutinePhaseState.breakExpiringGrace ? 2 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                snapshot.isFocusActive ? Icons.shield_rounded : Icons.access_time_filled_rounded,
                color: snapshot.isFocusActive ? palette.ink : palette.strictAccent,
                size: 20,
              ),
              const SizedBox(width: 8),
              Text(
                snapshot.isFocusActive ? 'Deep Focus Shield Active' : 'Break Grace Period',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: palette.ink,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            snapshot.isFocusActive
                ? 'All distracting social networks, infinite feeds and notifications are blocked. Zero bypass active.'
                : 'Enjoy your break. When the timer hits 0, FocusDNS will automatically close all foreground distracting apps.',
            style: GoogleFonts.plusJakartaSans(
              fontSize: 12,
              color: palette.mutedInk,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmergencyCancelButton(RoutineStateMachine engine, WabiSabiPalette palette) {
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton(
        onPressed: () {
          final success = engine.cancelRoutine();
          if (!success) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: const Text('Strict Lockout is Active! Routine cannot be canceled until finished.'),
                backgroundColor: palette.strictAccent,
              ),
            );
          }
        },
        style: OutlinedButton.styleFrom(
          side: BorderSide(color: palette.border),
          padding: const EdgeInsets.symmetric(vertical: 14),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
        child: Text(
          'ABORT ROUTINE',
          style: GoogleFonts.plusJakartaSans(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: palette.mutedInk,
          ),
        ),
      ),
    );
  }
}

class _StudioTimerPainter extends CustomPainter {
  final double progress;
  final Color trackColor;
  final Color progressColor;
  final double strokeWidth;

  const _StudioTimerPainter({
    required this.progress,
    required this.trackColor,
    required this.progressColor,
    required this.strokeWidth,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (size.width - strokeWidth) / 2;

    // Background track
    final trackPaint = Paint()
      ..color = trackColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth;

    canvas.drawCircle(center, radius, trackPaint);

    // Active progress arc
    final progressPaint = Paint()
      ..color = progressColor
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = strokeWidth;

    const startAngle = -math.pi / 2;
    final sweepAngle = 2 * math.pi * progress;

    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      startAngle,
      sweepAngle,
      false,
      progressPaint,
    );
  }

  @override
  bool shouldRepaint(covariant _StudioTimerPainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.progressColor != progressColor ||
        oldDelegate.trackColor != trackColor;
  }
}
