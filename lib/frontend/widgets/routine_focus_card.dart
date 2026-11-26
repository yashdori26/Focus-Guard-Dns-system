import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../backend/blocker_service.dart';
import '../../state_management/providers.dart';
import '../theme/wabi_sabi_theme.dart';
import '../screens/routine_focus_studio_screen.dart';

class RoutineFocusCard extends ConsumerWidget {
  const RoutineFocusCard({super.key});

  String _formatTime(int seconds) {
    final m = seconds ~/ 60;
    final s = seconds % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final routine = ref.watch(routineFocusProvider);
    final palette = WabiSabiPalette.of(context);

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: routine.isActive ? palette.strictAccent.withOpacity(0.5) : palette.border,
          width: routine.isActive ? 1.5 : 1.0,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: routine.isBreak
                      ? const Color(0xFF10B981).withOpacity(0.15)
                      : palette.strictAccent.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  routine.isBreak ? Icons.coffee_rounded : Icons.all_inclusive_rounded,
                  color: routine.isBreak ? const Color(0xFF10B981) : palette.strictAccent,
                  size: 22,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Anti-Doomscroll Routine',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: palette.ink,
                      ),
                    ),
                    Text(
                      routine.isActive
                          ? '${routine.phaseLabel} • Cycle ${routine.currentCycle}/${routine.config.totalCycles}'
                          : 'Auto-switches Focus ↔ Micro-Break with instant app closure',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 12,
                        color: palette.mutedInk,
                      ),
                    ),
                  ],
                ),
              ),
              if (routine.isActive)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: routine.isBreak
                        ? const Color(0xFF10B981).withOpacity(0.2)
                        : palette.strictAccent.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    _formatTime(routine.remainingSeconds),
                    style: GoogleFonts.jetBrainsMono(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      color: routine.isBreak ? const Color(0xFF10B981) : palette.strictAccent,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 14),

          if (!routine.isActive) ...[
            // Config Row: Session (mins), Break (mins), Cycles
            Row(
              children: [
                _buildConfigChip(
                  label: 'Session Timer',
                  value: '${routine.config.sessionMinutes}m',
                  onTap: () => _showPicker(
                    context,
                    title: 'Session Duration',
                    values: [25, 45, 50, 60, 90, 120],
                    current: routine.config.sessionMinutes,
                    onSelect: (v) => ref.read(routineFocusProvider.notifier).updateConfig(sessionMinutes: v),
                  ),
                  palette: palette,
                ),
                const SizedBox(width: 8),
                _buildConfigChip(
                  label: 'Break Timer',
                  value: '${routine.config.breakMinutes}m',
                  onTap: () => _showPicker(
                    context,
                    title: 'Break Duration (Max 30m)',
                    values: [5, 10, 15, 20, 30],
                    current: routine.config.breakMinutes,
                    onSelect: (v) => ref.read(routineFocusProvider.notifier).updateConfig(breakMinutes: v),
                  ),
                  palette: palette,
                ),
                const SizedBox(width: 8),
                _buildConfigChip(
                  label: 'Sessions',
                  value: '${routine.config.totalCycles} cycles',
                  onTap: () => _showPicker(
                    context,
                    title: 'Total Cycles',
                    values: [2, 3, 4, 5, 6],
                    current: routine.config.totalCycles,
                    onSelect: (v) => ref.read(routineFocusProvider.notifier).updateConfig(totalCycles: v),
                  ),
                  palette: palette,
                ),
              ],
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    key: const Key('start_routine_normal_button'),
                    onPressed: () {
                      ref.read(routineFocusProvider.notifier).startRoutine(strict: false);
                      ref.read(protectionProvider.notifier).set(true);
                    },
                    icon: const Icon(Icons.play_arrow_rounded, size: 18),
                    label: const Text('Apply Normally', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: palette.ink,
                      foregroundColor: palette.canvas,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ElevatedButton.icon(
                    key: const Key('start_routine_strict_button'),
                    onPressed: () {
                      ref.read(strictModeProvider.notifier).set(false, force: true);
                      FocusDnsBlockerManager.setStrictMode(false);
                      ref.read(routineFocusProvider.notifier).startRoutine(strict: true);
                      ref.read(protectionProvider.notifier).set(true);
                    },
                    icon: const Icon(Icons.lock_rounded, size: 16),
                    label: const Text('Apply Strictly', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF991B1B),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const RoutineFocusStudioScreen()),
                  );
                },
                icon: const Icon(Icons.fullscreen_rounded, size: 18),
                label: const Text('OPEN FULLSCREEN STUDIO'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: palette.ink,
                  side: BorderSide(color: palette.border),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  padding: const EdgeInsets.symmetric(vertical: 10),
                ),
              ),
            ),
          ] else ...[
            // 3-Column live telemetry: Session Timer, Break Timer, Number of Sessions
            Row(
              children: [
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
                    decoration: BoxDecoration(
                      color: routine.isFocus
                          ? (routine.isStrict ? const Color(0xFF991B1B).withOpacity(0.08) : palette.strictAccent.withOpacity(0.08))
                          : palette.canvas,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: routine.isFocus
                            ? (routine.isStrict ? const Color(0xFF991B1B) : palette.strictAccent)
                            : palette.border,
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'SESSION TIMER',
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 9.5,
                            fontWeight: FontWeight.w700,
                            color: routine.isFocus
                                ? (routine.isStrict ? const Color(0xFF991B1B) : palette.strictAccent)
                                : palette.mutedInk,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          routine.isFocus ? _formatTime(routine.remainingSeconds) : '${routine.config.sessionMinutes}m',
                          style: GoogleFonts.jetBrainsMono(
                            fontSize: 13,
                            fontWeight: FontWeight.w800,
                            color: routine.isFocus
                                ? (routine.isStrict ? const Color(0xFF991B1B) : palette.strictAccent)
                                : palette.ink,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
                    decoration: BoxDecoration(
                      color: routine.isBreak
                          ? const Color(0xFF10B981).withOpacity(0.08)
                          : palette.canvas,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: routine.isBreak ? const Color(0xFF10B981) : palette.border,
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'BREAK TIMER',
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 9.5,
                            fontWeight: FontWeight.w700,
                            color: routine.isBreak ? const Color(0xFF10B981) : palette.mutedInk,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          routine.isBreak ? _formatTime(routine.remainingSeconds) : '${routine.config.breakMinutes}m',
                          style: GoogleFonts.jetBrainsMono(
                            fontSize: 13,
                            fontWeight: FontWeight.w800,
                            color: routine.isBreak ? const Color(0xFF10B981) : palette.ink,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
                    decoration: BoxDecoration(
                      color: palette.canvas,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: palette.border),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'SESSIONS',
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 9.5,
                            fontWeight: FontWeight.w700,
                            color: palette.mutedInk,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${routine.currentCycle} of ${routine.config.totalCycles}',
                          style: GoogleFonts.jetBrainsMono(
                            fontSize: 13,
                            fontWeight: FontWeight.w800,
                            color: palette.ink,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            // Active Progress Bar & Info
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                value: routine.isFocus
                    ? (1.0 - (routine.remainingSeconds / (routine.config.sessionMinutes * 60))).clamp(0.0, 1.0)
                    : (1.0 - (routine.remainingSeconds / (routine.config.breakMinutes * 60))).clamp(0.0, 1.0),
                backgroundColor: palette.canvas,
                valueColor: AlwaysStoppedAnimation(
                  routine.isBreak ? const Color(0xFF10B981) : (routine.isStrict ? const Color(0xFF991B1B) : palette.strictAccent),
                ),
                minHeight: 6,
              ),
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    routine.isStrict
                        ? '🔒 Strictly locked. Changes & pausing disabled.'
                        : (routine.isBreak
                            ? '⚠️ Apps will force-close at break end!'
                            : '🔒 Apps blocked. Break starts automatically.'),
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 11.5,
                      color: routine.isStrict
                          ? const Color(0xFFB91C1C)
                          : (routine.isBreak ? const Color(0xFF10B981) : palette.mutedInk),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                if (!routine.isStrict)
                  TextButton(
                    onPressed: () => ref.read(routineFocusProvider.notifier).cancelRoutine(),
                    style: TextButton.styleFrom(
                      foregroundColor: palette.mutedInk,
                      padding: EdgeInsets.zero,
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    child: const Text('Stop Routine', style: TextStyle(fontSize: 11)),
                  )
                else
                  const Padding(
                    padding: EdgeInsets.only(left: 4),
                    child: Icon(Icons.lock, size: 14, color: Color(0xFFB91C1C)),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildConfigChip({
    required String label,
    required String value,
    required VoidCallback onTap,
    required WabiSabiPalette palette,
  }) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
          decoration: BoxDecoration(
            color: palette.canvas,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: palette.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: GoogleFonts.plusJakartaSans(fontSize: 10, color: palette.mutedInk),
              ),
              const SizedBox(height: 2),
              Text(
                value,
                style: GoogleFonts.plusJakartaSans(fontSize: 13, fontWeight: FontWeight.bold, color: palette.ink),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showPicker(
    BuildContext context, {
    required String title,
    required List<int> values,
    required int current,
    required ValueChanged<int> onSelect,
  }) {
    final palette = WabiSabiPalette.of(context);
    final textController = TextEditingController(text: '$current');
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: palette.canvas,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(18))),
      builder: (ctx) {
        return Padding(
          padding: EdgeInsets.only(
            left: 20,
            right: 20,
            top: 20,
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 20,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: GoogleFonts.plusJakartaSans(fontSize: 16, fontWeight: FontWeight.bold, color: palette.ink)),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: textController,
                      keyboardType: TextInputType.number,
                      autofocus: true,
                      style: GoogleFonts.jetBrainsMono(fontSize: 15, fontWeight: FontWeight.bold, color: palette.ink),
                      decoration: InputDecoration(
                        labelText: 'Type custom number',
                        labelStyle: TextStyle(color: palette.mutedInk, fontSize: 13),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    onPressed: () {
                      final val = int.tryParse(textController.text.trim());
                      if (val != null && val > 0) {
                        onSelect(val);
                      }
                      Navigator.pop(ctx);
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: palette.ink,
                      foregroundColor: palette.canvas,
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    child: const Text('Set'),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Text('Quick Presets:', style: GoogleFonts.plusJakartaSans(fontSize: 12, color: palette.mutedInk)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: values.map((val) {
                  final sel = val == current;
                  return ChoiceChip(
                    label: Text('$val'),
                    selected: sel,
                    selectedColor: palette.ink,
                    labelStyle: TextStyle(
                      color: sel ? palette.canvas : palette.ink,
                      fontWeight: FontWeight.bold,
                    ),
                    onSelected: (_) {
                      onSelect(val);
                      Navigator.pop(ctx);
                    },
                  );
                }).toList(),
              ),
            ],
          ),
        );
      },
    );
  }
}
