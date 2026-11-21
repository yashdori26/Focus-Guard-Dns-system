import 'package:flutter/material.dart';
import 'package:focus_dns/engine/per_app/catalog/app_definition.dart';
import 'package:focus_dns/engine/per_app/catalog/comprehensive_app_catalog.dart';
import 'package:focus_dns/engine/per_app/core/per_app_coordinator.dart';
import 'package:focus_dns/engine/per_app/models/app_lock_config.dart';
import 'package:focus_dns/engine/per_app/per_app_database.dart';

/// Screen managing daily screen-time allowances, quota bars, and midnight rollovers.
class DailyQuotaStudioScreen extends StatefulWidget {
  final PerAppCoordinator coordinator;

  const DailyQuotaStudioScreen({
    super.key,
    required this.coordinator,
  });

  @override
  State<DailyQuotaStudioScreen> createState() => _DailyQuotaStudioScreenState();
}

class _DailyQuotaStudioScreenState extends State<DailyQuotaStudioScreen> {
  @override
  void initState() {
    super.initState();
    widget.coordinator.addListener(_onUpdate);
  }

  void _onUpdate() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    widget.coordinator.removeListener(_onUpdate);
    super.dispose();
  }

  String _formatTimeUntilMidnight() {
    final now = DateTime.now();
    final midnight = DateTime(now.year, now.month, now.day + 1);
    final diff = midnight.difference(now);
    final hours = diff.inHours;
    final mins = diff.inMinutes % 60;
    return '${hours}h ${mins}m';
  }

  void _updateQuota(String appId, int newMinutes) async {
    await widget.coordinator.configureDailyQuota(appId, newMinutes);
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final quotaApps = widget.coordinator.configs.values
        .where((c) => c.mode == AppLockMode.dailyQuota)
        .toList();

    return Scaffold(
      backgroundColor: const Color(0xFF090D16),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0F172A),
        elevation: 0,
        title: const Text(
          'Daily Quota Allowances',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Midnight Rollover Card
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF1E293B), Color(0xFF0F172A)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.white10),
              ),
              child: Row(
                children: [
                  const Icon(Icons.nightlight_round, color: Color(0xFF60A5FA), size: 36),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Automatic Midnight Rollover',
                          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Quotas automatically refresh in ${_formatTimeUntilMidnight()}',
                          style: const TextStyle(color: Colors.white70, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            const Text(
              'Active App Quotas',
              style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),

            if (quotaApps.isEmpty) ...[
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: const Color(0xFF131B2E),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.white10),
                ),
                child: Center(
                  child: Column(
                    children: [
                      const Icon(Icons.hourglass_empty_rounded, color: Colors.white38, size: 48),
                      const SizedBox(height: 12),
                      const Text(
                        'No apps currently configured for daily quotas.',
                        style: TextStyle(color: Colors.white70, fontSize: 14),
                      ),
                      const SizedBox(height: 16),
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF3B82F6),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                        onPressed: () {
                          // Quick enable Instagram and YouTube with daily quotas
                          _updateQuota('instagram', 20);
                          _updateQuota('youtube', 45);
                        },
                        child: const Text('Add Top Apps to Quotas'),
                      ),
                    ],
                  ),
                ),
              ),
            ] else ...[
              ...quotaApps.map((cfg) {
                final def = widget.coordinator.catalog[cfg.appId] ??
                    AppDefinition(
                      id: cfg.appId,
                      name: cfg.appId,
                      primaryPackage: cfg.packageName,
                      networkDomains: const [],
                      category: AppCategory.social,
                      iconGlyph: '📱',
                      description: '',
                    );

                final usedMinutes = cfg.usedQuotaSecondsToday ~/ 60;
                final totalMinutes = cfg.dailyQuotaMinutes;
                final ratio = (usedMinutes / totalMinutes).clamp(0.0, 1.0);
                final isDepleted = cfg.isQuotaDepleted;

                return Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFF131B2E),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: isDepleted ? const Color(0xFFEF4444) : Colors.white10,
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(def.iconGlyph, style: const TextStyle(fontSize: 24)),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              def.name,
                              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15),
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: isDepleted
                                  ? const Color(0xFFEF4444).withValues(alpha: 0.2)
                                  : const Color(0xFF3B82F6).withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              isDepleted ? 'EXHAUSTED' : '$usedMinutes / $totalMinutes min',
                              style: TextStyle(
                                color: isDepleted ? const Color(0xFFEF4444) : const Color(0xFF60A5FA),
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          value: ratio,
                          minHeight: 8,
                          backgroundColor: Colors.white12,
                          valueColor: AlwaysStoppedAnimation<Color>(
                            isDepleted ? const Color(0xFFEF4444) : const Color(0xFF3B82F6),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          TextButton(
                            onPressed: () => _updateQuota(cfg.appId, (cfg.dailyQuotaMinutes - 5).clamp(5, 180)),
                            child: const Text('-5 min', style: TextStyle(color: Colors.white70)),
                          ),
                          TextButton(
                            onPressed: () => _updateQuota(cfg.appId, (cfg.dailyQuotaMinutes + 5).clamp(5, 180)),
                            child: const Text('+5 min', style: TextStyle(color: Color(0xFF60A5FA))),
                          ),
                        ],
                      ),
                    ],
                  ),
                );
              }),
            ],
          ],
        ),
      ),
    );
  }
}
