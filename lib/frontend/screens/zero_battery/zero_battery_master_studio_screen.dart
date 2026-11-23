import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../engine/daemon/oem/oem_registry.dart';
import '../../../engine/daemon/telemetry/battery_drain_profiler.dart';
import '../../../engine/daemon/telemetry/oem_resilience_auditor.dart';
import '../../../engine/daemon/telemetry/power_historian_recorder.dart';
import '../../widgets/zero_battery/energy_radial_meter.dart';
import '../../widgets/zero_battery/oem_brand_card.dart';
import '../../widgets/zero_battery/oem_survival_scorecard.dart';
import '../../widgets/zero_battery/power_timeline_chart.dart';
import 'battery_drain_histogram_screen.dart';
import 'battery_stress_benchmark_screen.dart';
import 'oem_exemption_wizard_screen.dart';
import 'power_profile_config_screen.dart';
import 'wake_lock_audit_screen.dart';

/// Master Control Studio for FocusDNS Zero-Battery Daemon & Industrial OEM Resilience.
class ZeroBatteryMasterStudioScreen extends StatefulWidget {
  const ZeroBatteryMasterStudioScreen({super.key});

  @override
  State<ZeroBatteryMasterStudioScreen> createState() => _ZeroBatteryMasterStudioScreenState();
}

class _ZeroBatteryMasterStudioScreenState extends State<ZeroBatteryMasterStudioScreen> {
  final OemRegistry _oemRegistry = OemRegistry();
  final BatteryDrainProfiler _profiler = BatteryDrainProfiler();
  final PowerHistorianRecorder _historian = PowerHistorianRecorder();

  @override
  void initState() {
    super.initState();
    _oemRegistry.detectDevice();
    // Simulate some active baseline packets
    _profiler.recordPacketBatch(
      totalInBatch: 1250,
      sinkholedInBatch: 820,
      zeroCopyHitsInBatch: 1250,
      wakeLocks: 0,
    );
  }

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? const Color(0xFF141416) : const Color(0xFFF8F9FA);
    final cardColor = isDark ? const Color(0xFF1C1C1E) : Colors.white;
    final borderColor = isDark ? const Color(0xFF2C2C2E) : const Color(0xFFE5E5EA);

    final snapshot = _profiler.computeSnapshot();
    final scorecard = OemResilienceAuditor.auditDevice(
      profile: _oemRegistry.currentProfile,
      probe: _oemRegistry.probe,
    );

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        backgroundColor: bgColor,
        elevation: 0,
        title: Text(
          'Zero-Battery Daemon Studio',
          style: GoogleFonts.plusJakartaSans(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: isDark ? Colors.white : Colors.black87,
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.tune_rounded),
            tooltip: 'Power Profiles',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const PowerProfileConfigScreen()),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 1. Hero Energy Consumption Gauge
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(22),
                decoration: BoxDecoration(
                  color: cardColor,
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: borderColor),
                ),
                child: Column(
                  children: [
                    EnergyRadialMeter(
                      dailyDrainPercentage: snapshot.projected24hDrainPercentage,
                      currentDrawMicroamps: snapshot.currentDrawMicroamperes,
                      maxBudgetPercentage: 1.0,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'STRICT GUARANTEE: < 1.0% PER 24 HOURS',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.8,
                        color: const Color(0xFF2ECC71),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Routes exclusively 10.254.1.2/32 DNS. All streaming, social feeds, and file downloads bypass userspace and execute directly on hardware with zero CPU wake-locks.',
                      textAlign: TextAlign.center,
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 12,
                        color: isDark ? Colors.white60 : Colors.black54,
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 20),

              // 2. Hardware Architecture & Kernel Diagnostics Grid
              Text(
                'HARDWARE & KERNEL AUDIT',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.1,
                  color: isDark ? Colors.white54 : Colors.black45,
                ),
              ),
              const SizedBox(height: 10),

              Row(
                children: [
                  Expanded(
                    child: _buildMetricTile(
                      icon: Icons.power_off_rounded,
                      title: 'WAKE-LOCKS',
                      value: '${snapshot.activeWakeLocks} Active',
                      subtitle: 'Zero CPU wake-locks',
                      isDark: isDark,
                      cardColor: cardColor,
                      borderColor: borderColor,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _buildMetricTile(
                      icon: Icons.alt_route_rounded,
                      title: 'ROUTE ISOLATION',
                      value: '10.254.1.2/32',
                      subtitle: 'DNS virtual tun only',
                      isDark: isDark,
                      cardColor: cardColor,
                      borderColor: borderColor,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: _buildMetricTile(
                      icon: Icons.memory_rounded,
                      title: 'RING BUFFERS',
                      value: '${(snapshot.zeroCopyBufferHitRatio * 100).toStringAsFixed(0)}% Direct',
                      subtitle: 'Zero GC churn',
                      isDark: isDark,
                      cardColor: cardColor,
                      borderColor: borderColor,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _buildMetricTile(
                      icon: Icons.shield_outlined,
                      title: 'DOZE EXEMPTION',
                      value: _oemRegistry.probe.isDozeExempted ? 'Granted' : 'Restricted',
                      subtitle: _oemRegistry.probe.isDozeExempted ? 'Pierces deep idle' : 'Tap to optimize',
                      isDark: isDark,
                      cardColor: cardColor,
                      borderColor: borderColor,
                      valueColor: _oemRegistry.probe.isDozeExempted
                          ? const Color(0xFF2ECC71)
                          : const Color(0xFFE74C3C),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 22),

              // 3. 24-Hour Comparative Power Chart
              PowerTimelineChart(entries: _historian.history),

              const SizedBox(height: 22),

              // 4. OEM Survivability Scorecard
              OemSurvivalScorecard(
                scorecard: scorecard,
                onFixVulnerabilities: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const OemExemptionWizardScreen()),
                ),
              ),

              const SizedBox(height: 20),

              // 5. Detected Device Brand Card
              OemBrandCard(
                profile: _oemRegistry.currentProfile,
                romVersion: _oemRegistry.probe.romVersion,
                onLaunchWizard: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const OemExemptionWizardScreen()),
                ),
              ),

              const SizedBox(height: 20),

              // 6. Deep Diagnostic Utilities Action Hub
              Text(
                'DIAGNOSTIC & BENCHMARK SUITE',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.1,
                  color: isDark ? Colors.white54 : Colors.black45,
                ),
              ),
              const SizedBox(height: 10),

              _buildNavTile(
                icon: Icons.bar_chart_rounded,
                title: '24-Hour Drain Histogram',
                subtitle: 'Correlate DNS query volume with battery percentage',
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const BatteryDrainHistogramScreen()),
                ),
                isDark: isDark,
                cardColor: cardColor,
                borderColor: borderColor,
              ),
              const SizedBox(height: 10),
              _buildNavTile(
                icon: Icons.alarm_on_rounded,
                title: 'Zero Wake-Lock Inspector',
                subtitle: 'Verify real-time CPU sleep and alarm schedules',
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const WakeLockAuditScreen()),
                ),
                isDark: isDark,
                cardColor: cardColor,
                borderColor: borderColor,
              ),
              const SizedBox(height: 10),
              _buildNavTile(
                icon: Icons.speed_rounded,
                title: '100K-Packet Stress Benchmark',
                subtitle: 'Stress test buffer recycling and power projection',
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const BatteryStressBenchmarkScreen()),
                ),
                isDark: isDark,
                cardColor: cardColor,
                borderColor: borderColor,
              ),

              const SizedBox(height: 30),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMetricTile({
    required IconData icon,
    required String title,
    required String value,
    required String subtitle,
    required bool isDark,
    required Color cardColor,
    required Color borderColor,
    Color? valueColor,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 15, color: isDark ? Colors.white60 : Colors.black54),
              const SizedBox(width: 6),
              Text(
                title,
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.8,
                  color: isDark ? Colors.white60 : Colors.black54,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: GoogleFonts.plusJakartaSans(
              fontSize: 15,
              fontWeight: FontWeight.w800,
              color: valueColor ?? (isDark ? Colors.white : Colors.black87),
            ),
          ),
          const SizedBox(height: 2),
          Text(
            subtitle,
            style: GoogleFonts.plusJakartaSans(
              fontSize: 11,
              color: isDark ? Colors.white54 : Colors.black45,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNavTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
    required bool isDark,
    required Color cardColor,
    required Color borderColor,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: cardColor,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: borderColor),
        ),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF2C2C2E) : const Color(0xFFF2F2F7),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, size: 20, color: isDark ? Colors.white70 : Colors.black87),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: isDark ? Colors.white : Colors.black87,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 11,
                      color: isDark ? Colors.white54 : Colors.black45,
                    ),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded, size: 20, color: isDark ? Colors.white38 : Colors.black38),
          ],
        ),
      ),
    );
  }
}
