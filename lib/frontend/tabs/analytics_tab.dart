import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/enums.dart';
import '../../state_management/providers.dart';
import '../theme/wabi_sabi_theme.dart';
import '../widgets.dart';

class AnalyticsTab extends ConsumerWidget {
  const AnalyticsTab({super.key});

  String _formatCount(int number) {
    if (number < 1000) return number.toString();
    final str = number.toString();
    final result = StringBuffer();
    for (int i = 0; i < str.length; i++) {
      if (i > 0 && (str.length - i) % 3 == 0) {
        result.write(',');
      }
      result.write(str[i]);
    }
    return result.toString();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final filter = ref.watch(analyticsFilterProvider);
    final analytics = ref.watch(analyticsStateProvider);
    final palette = WabiSabiPalette.of(context);

    final String filterKey = filter == TimeFilter.hours24
        ? '24h'
        : filter == TimeFilter.days7
            ? '7d'
            : '30d';

    final totalText = _formatCount(analytics.totalQueries);
    final blockedText = '${_formatCount(analytics.blockedQueries)} (${analytics.blockedPercentage})';

    return RefreshIndicator(
      onRefresh: () => ref.read(analyticsStateProvider.notifier).refresh(),
      color: palette.ink,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        child: Column(
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
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
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
                      if (analytics.isLoading)
                        SizedBox(
                          width: 12,
                          height: 12,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: palette.mutedInk,
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    totalText,
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
                      '$blockedText blocked',
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
                  if (analytics.topBlockedDomains.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      child: Center(
                        child: Text(
                          analytics.totalQueries == 0
                              ? 'No DNS queries captured yet.\nStart browsing to record live analytics.'
                              : 'No domains blocked in this time window.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 12,
                            color: palette.mutedInk,
                            height: 1.4,
                          ),
                        ),
                      ),
                    )
                  else
                    for (int i = 0; i < analytics.topBlockedDomains.length; i++) ...[
                      if (i > 0) Divider(color: palette.border, height: 16),
                      _BlockedDomainRow(
                        analytics.topBlockedDomains[i].domain,
                        '${analytics.topBlockedDomains[i].count} queries',
                        analytics.topBlockedDomains[i].percentage,
                        palette,
                      ),
                    ],
                ],
              ),
            ),
          ],
        ),
      ),
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
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                domain,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
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
        ),
        const SizedBox(width: 8),
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
