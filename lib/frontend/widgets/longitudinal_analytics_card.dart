import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../state_management/providers.dart';
import '../theme/wabi_sabi_theme.dart';

class LongitudinalAnalyticsCard extends ConsumerWidget {
  const LongitudinalAnalyticsCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final analytics = ref.watch(longitudinalAnalyticsProvider);
    final metrics = analytics.currentMetrics;
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
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'FOCUS & BREAK TRACKER',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.8,
                      color: palette.mutedInk,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Longitudinal Progress',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: palette.ink,
                      letterSpacing: -0.3,
                    ),
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: const Color(0xFF10B981).withOpacity(0.15),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  '${(metrics.complianceRate * 100).toInt()}% ADHERENCE',
                  style: GoogleFonts.jetBrainsMono(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: const Color(0xFF10B981),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),

          // TIMEFRAME SELECTOR (DAY, WEEK, MONTH, YEAR)
          Container(
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(
              color: palette.canvas,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: palette.border),
            ),
            child: Row(
              children: [
                _buildTimeframePill('Day', AnalyticsTimeframe.day, analytics.selectedTimeframe, ref, palette),
                _buildTimeframePill('Week', AnalyticsTimeframe.week, analytics.selectedTimeframe, ref, palette),
                _buildTimeframePill('Month', AnalyticsTimeframe.month, analytics.selectedTimeframe, ref, palette),
                _buildTimeframePill('Year', AnalyticsTimeframe.year, analytics.selectedTimeframe, ref, palette),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // METRIC TILES GRID
          Row(
            children: [
              _buildMetricTile(
                label: 'FOCUS TIME',
                value: '${metrics.totalFocusMinutes ~/ 60}h ${metrics.totalFocusMinutes % 60}m',
                sub: '${metrics.completedSessions} sessions',
                icon: Icons.timer_outlined,
                palette: palette,
              ),
              const SizedBox(width: 8),
              _buildMetricTile(
                label: 'SAVED TIME',
                value: '${metrics.totalSavedHours} hrs',
                sub: 'from doomscrolling',
                icon: Icons.hourglass_empty_rounded,
                palette: palette,
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              _buildMetricTile(
                label: 'BREAK DURATION',
                value: '${metrics.totalBreakMinutes} mins',
                sub: 'controlled breaks',
                icon: Icons.coffee_outlined,
                palette: palette,
              ),
              const SizedBox(width: 8),
              _buildMetricTile(
                label: 'BLOCKED ATTEMPTS',
                value: '${metrics.blockedLaunchesAttempted}',
                sub: '${metrics.blockedDnsQueries} DNS queries',
                icon: Icons.shield_outlined,
                palette: palette,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTimeframePill(
    String label,
    AnalyticsTimeframe timeframe,
    AnalyticsTimeframe current,
    WidgetRef ref,
    WabiSabiPalette palette,
  ) {
    final sel = timeframe == current;
    return Expanded(
      child: GestureDetector(
        onTap: () => ref.read(longitudinalAnalyticsProvider.notifier).selectTimeframe(timeframe),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 6),
          decoration: BoxDecoration(
            color: sel ? palette.ink : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: GoogleFonts.plusJakartaSans(
              fontSize: 11,
              fontWeight: FontWeight.bold,
              color: sel ? palette.canvas : palette.mutedInk,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMetricTile({
    required String label,
    required String value,
    required String sub,
    required IconData icon,
    required WabiSabiPalette palette,
  }) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: palette.canvas,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: palette.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 14, color: palette.mutedInk),
                const SizedBox(width: 6),
                Text(
                  label,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 9.5,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.5,
                    color: palette.mutedInk,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              value,
              style: GoogleFonts.jetBrainsMono(
                fontSize: 17,
                fontWeight: FontWeight.w800,
                color: palette.ink,
                letterSpacing: -0.5,
              ),
            ),
            Text(
              sub,
              style: GoogleFonts.plusJakartaSans(
                fontSize: 10,
                color: palette.mutedInk,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
