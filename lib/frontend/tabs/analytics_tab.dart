import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/enums.dart';
import '../../state_management/providers.dart';
import '../theme/wabi_sabi_theme.dart';
import '../widgets.dart';

class AnalyticsTab extends ConsumerWidget {
  const AnalyticsTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final filter = ref.watch(analyticsFilterProvider);
    final palette = WabiSabiPalette.of(context);

    String filterKey = '7d';
    String totalQueries = '14,566';
    String blockedQueries = '779 (5%)';

    switch (filter) {
      case TimeFilter.hours24:
        filterKey = '24h';
        totalQueries = '33';
        blockedQueries = '0 (0%)';
        break;
      case TimeFilter.days7:
        filterKey = '7d';
        totalQueries = '14,566';
        blockedQueries = '779 (5%)';
        break;
      case TimeFilter.days30:
        filterKey = '30d';
        totalQueries = '66,190';
        blockedQueries = '2,732 (4%)';
        break;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // MAIN METRICS CARD
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: palette.surface,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: palette.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'QUERIES TRAFFIC',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: palette.mutedInk,
                  letterSpacing: 0.5,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                totalQueries,
                style: TextStyle(
                  fontSize: 36,
                  fontWeight: FontWeight.w800,
                  color: palette.ink,
                  letterSpacing: -1.0,
                ),
              ),
              const SizedBox(height: 4),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: palette.canvas,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: palette.border),
                ),
                child: Text(
                  '$blockedQueries blocked',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: palette.strictAccent,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(
                height: 60,
                width: double.infinity,
                child: CustomPaint(
                  painter: ChartPainter(
                    filter: filterKey,
                    totalColor: palette.ink,
                    blockedColor: palette.strictAccent,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(3),
                decoration: BoxDecoration(
                  color: palette.canvas,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: palette.border),
                ),
                child: Row(
                  children: [
                    _filterPill(ref, '24 hours', TimeFilter.hours24, filter, palette),
                    _filterPill(ref, '7 days', TimeFilter.days7, filter, palette),
                    _filterPill(ref, '30 days', TimeFilter.days30, filter, palette),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // TOP BLOCKED DOMAINS CARD
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: palette.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: palette.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Top Blocked Domains',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: palette.ink,
                  letterSpacing: -0.2,
                ),
              ),
              const SizedBox(height: 12),
              _BlockedDomainRow('reddit.com (tracking)', '412 queries', '53%', palette),
              Divider(color: palette.border, height: 16),
              _BlockedDomainRow('appsflyersdk.com', '189 queries', '24%', palette),
              Divider(color: palette.border, height: 16),
              _BlockedDomainRow('tiktokv.com', '102 queries', '13%', palette),
              Divider(color: palette.border, height: 16),
              _BlockedDomainRow('segment.io', '76 queries', '10%', palette),
            ],
          ),
        ),
      ],
    );
  }

  Widget _filterPill(
    WidgetRef ref,
    String label,
    TimeFilter target,
    TimeFilter current,
    WabiSabiPalette palette,
  ) {
    final isSelected = current == target;
    return Expanded(
      child: GestureDetector(
        onTap: () {
          ref.read(analyticsFilterProvider.notifier).state = target;
        },
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 6),
          decoration: BoxDecoration(
            color: isSelected ? palette.ink : Colors.transparent,
            borderRadius: BorderRadius.circular(9),
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.bold,
              color: isSelected ? palette.canvas : palette.mutedInk,
            ),
          ),
        ),
      ),
    );
  }
}

class _BlockedDomainRow extends StatelessWidget {
  final String domain;
  final String count;
  final String percent;
  final WabiSabiPalette palette;

  const _BlockedDomainRow(this.domain, this.count, this.percent, this.palette);

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              domain,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: palette.ink,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              count,
              style: TextStyle(fontSize: 10, color: palette.mutedInk),
            ),
          ],
        ),
        Text(
          percent,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.bold,
            color: palette.strictAccent,
          ),
        ),
      ],
    );
  }
}
