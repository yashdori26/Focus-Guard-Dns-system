import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../state_management/providers.dart';
import '../theme/wabi_sabi_theme.dart';
import '../screens/per_app_manager_screen.dart';
import 'app_logo.dart';

class PerAppTimerCard extends ConsumerWidget {
  const PerAppTimerCard({super.key});

  String _formatRemaining(int seconds) {
    final h = seconds ~/ 3600;
    final m = (seconds % 3600) ~/ 60;
    final s = seconds % 60;
    if (h > 0) {
      return '${h}h ${m}m ${s}s';
    }
    return '${m}m ${s}s';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final appTimers = ref.watch(perAppTimersProvider);
    final palette = WabiSabiPalette.of(context);

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: palette.border, width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Independent App Timers',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: palette.ink,
                        letterSpacing: -0.3,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Allocate custom lockout durations per app (e.g. Insta 8h, YouTube 2h)',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 12,
                        color: palette.mutedInk,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: palette.canvas,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: palette.border),
                ),
                child: Text(
                  '${appTimers.values.where((t) => t.isLocked).length} RUNNING',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: palette.ink,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),

          ...appTimers.values.map((timerItem) {
            return Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: palette.canvas,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: timerItem.isLocked ? palette.strictAccent.withOpacity(0.5) : palette.border,
                ),
              ),
              child: Row(
                children: [
                  AppLogo(
                    appName: timerItem.appName,
                    packageName: timerItem.packages.isNotEmpty ? timerItem.packages.first : timerItem.appId,
                    size: 28,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          timerItem.appName,
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: palette.ink,
                          ),
                        ),
                        Text(
                          timerItem.isLocked
                              ? '🔒 Locked: ${_formatRemaining(timerItem.remainingSeconds)} left'
                              : 'Preset: ${timerItem.allocatedMinutes ~/ 60}h (${timerItem.allocatedMinutes}m)',
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 11,
                            color: timerItem.isLocked ? palette.strictAccent : palette.mutedInk,
                            fontWeight: timerItem.isLocked ? FontWeight.bold : FontWeight.normal,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (timerItem.isLocked)
                    Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: palette.strictAccent.withOpacity(0.12),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(Icons.lock_rounded, size: 16, color: palette.strictAccent),
                    )
                  else
                    ElevatedButton(
                      onPressed: () {
                        ref.read(perAppTimersProvider.notifier).startAppLock(timerItem.appId);
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: palette.ink,
                        foregroundColor: palette.canvas,
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                      child: Text(
                        'LOCK ${timerItem.allocatedMinutes ~/ 60}H',
                        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                      ),
                    ),
                ],
              ),
            );
          }),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const PerAppManagerScreen()),
                );
              },
              icon: const Icon(Icons.tune_rounded, size: 16),
              label: const Text('MANAGE ALL APPS & CATEGORIES'),
              style: OutlinedButton.styleFrom(
                foregroundColor: palette.ink,
                side: BorderSide(color: palette.border),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                padding: const EdgeInsets.symmetric(vertical: 10),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
