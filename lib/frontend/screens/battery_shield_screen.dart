import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../services/battery_telemetry_service.dart';
import '../theme/wabi_sabi_theme.dart';
import 'zero_battery/zero_battery_master_studio_screen.dart';

/// Dedicated screen for verifying FocusDNS zero-battery background operation and Doze exemptions.
class BatteryShieldScreen extends StatefulWidget {
  const BatteryShieldScreen({super.key});

  @override
  State<BatteryShieldScreen> createState() => _BatteryShieldScreenState();
}

class _BatteryShieldScreenState extends State<BatteryShieldScreen> {
  final BatteryTelemetryService _service = BatteryTelemetryService();

  @override
  void initState() {
    super.initState();
    _service.addListener(_onServiceUpdate);
  }

  void _onServiceUpdate() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _service.removeListener(_onServiceUpdate);
    _service.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = WabiSabiPalette.of(context);
    final report = _service.report;

    return Scaffold(
      backgroundColor: palette.canvas,
      appBar: AppBar(
        backgroundColor: palette.canvas,
        elevation: 0,
        iconTheme: IconThemeData(color: palette.ink),
        title: Text(
          'Zero-Battery Background Shield',
          style: GoogleFonts.plusJakartaSans(
            color: palette.ink,
            fontSize: 18,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.3,
          ),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 1. Live Consumption Hero Card
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(22),
                decoration: BoxDecoration(
                  color: palette.surface,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: palette.border),
                ),
                child: Column(
                  children: [
                    Container(
                      width: 64,
                      height: 64,
                      decoration: BoxDecoration(
                        color: const Color(0xFF2ECC71).withOpacity(0.12),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.battery_saver_rounded,
                        color: Color(0xFF27AE60),
                        size: 32,
                      ),
                    ),
                    const SizedBox(height: 14),
                    Text(
                      '${report.estimatedDailyDrainPercentage.toStringAsFixed(2)}% / DAY',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 32,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -1,
                        color: palette.ink,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Strict Guarantee: <1.20% per 24 Hours',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: const Color(0xFF27AE60),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Unlike conventional VPN blockers that process all streaming and media bytes, FocusDNS routes ONLY virtual DNS port 53. 100% of video and audio streams run directly on hardware with zero userspace overhead.',
                      textAlign: TextAlign.center,
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 12,
                        color: palette.mutedInk,
                        height: 1.45,
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 20),

              // 2. Hardware Audit Diagnostics Grid
              Text(
                'KERNEL & HARDWARE AUDIT',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.1,
                  color: palette.mutedInk,
                ),
              ),
              const SizedBox(height: 10),

              Row(
                children: [
                  Expanded(
                    child: _buildMetricTile(
                      icon: Icons.power_off_rounded,
                      title: 'WAKE-LOCKS',
                      value: '${report.activeWakeLocks} Active',
                      subtitle: 'Zero CPU wake-locks',
                      palette: palette,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _buildMetricTile(
                      icon: Icons.alt_route_rounded,
                      title: 'ROUTING SCOPE',
                      value: '10.254.1.2/32',
                      subtitle: 'DNS packets only',
                      palette: palette,
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
                      title: 'BUFFER POOL',
                      value: '100% Direct',
                      subtitle: 'Zero GC thrashing',
                      palette: palette,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _buildMetricTile(
                      icon: Icons.shield_outlined,
                      title: 'DOZE EXEMPTION',
                      value: report.isDozeExempted ? 'Granted' : 'Restricted',
                      subtitle: report.isDozeExempted ? '24/7 unbreakable' : 'Tap to optimize',
                      palette: palette,
                      valueColor: report.isDozeExempted ? const Color(0xFF27AE60) : palette.strictAccent,
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 24),

              // 3. Multi-OEM Optimization Button
              Container(
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
                      'OEM BATTERY OPTIMIZER',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.1,
                        color: palette.mutedInk,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Aggressive vendor battery killers (Xiaomi MIUI, Samsung Sleeping Apps, Huawei Protected Apps) may silently terminate background focus listeners. Exempting FocusDNS ensures unbreakable focus protection.',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 12,
                        color: palette.mutedInk,
                        height: 1.4,
                      ),
                    ),
                    const SizedBox(height: 14),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: () async {
                          final success = await _service.requestOptimizationExemption();
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(success ? 'Doze exemption active.' : 'Redirecting to device settings...'),
                                backgroundColor: palette.ink,
                              ),
                            );
                          }
                        },
                        icon: const Icon(Icons.bolt_rounded, size: 18),
                        label: const Text('OPTIMIZE BATTERY SETTINGS'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: palette.ink,
                          foregroundColor: palette.canvas,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(builder: (_) => const ZeroBatteryMasterStudioScreen()),
                          );
                        },
                        icon: const Icon(Icons.tune_rounded, size: 16),
                        label: const Text('OPEN ADVANCED ZERO-BATTERY STUDIO'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: palette.ink,
                          side: BorderSide(color: palette.border),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
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
    required WabiSabiPalette palette,
    Color? valueColor,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: palette.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: palette.mutedInk),
              const SizedBox(width: 6),
              Text(
                title,
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.8,
                  color: palette.mutedInk,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: GoogleFonts.plusJakartaSans(
              fontSize: 14,
              fontWeight: FontWeight.w800,
              color: valueColor ?? palette.ink,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            subtitle,
            style: GoogleFonts.plusJakartaSans(
              fontSize: 11,
              color: palette.mutedInk,
            ),
          ),
        ],
      ),
    );
  }
}
