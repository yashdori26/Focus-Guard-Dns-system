import 'package:flutter/material.dart';
import '../../../engine/profile/fleet_device_model.dart';

/// Interactive card widget displaying a paired fleet device's real-time telemetry,
/// active session mode, and remote focus lock action.
class FleetDeviceCard extends StatelessWidget {
  final FleetDeviceModel device;
  final VoidCallback? onLockTapped;
  final VoidCallback? onEmergencyTapped;

  const FleetDeviceCard({
    super.key,
    required this.device,
    this.onLockTapped,
    this.onEmergencyTapped,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF16161C),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: device.isStrictLockActive
              ? const Color(0xFFFF3B5C).withOpacity(0.4)
              : Colors.white.withOpacity(0.08),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 1. Header: Platform icon, Device name, Online pulse
          Row(
            children: [
              Text(device.platformIcon, style: const TextStyle(fontSize: 24)),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      device.deviceName,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${device.platform.name.toUpperCase()} • v${device.clientVersion} • ${device.pingLatencyMs}ms ping',
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.5),
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
              // Pulse Indicator
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: device.isOnline ? const Color(0xFF00E699) : const Color(0xFF50505C),
                  boxShadow: device.isOnline
                      ? [
                          BoxShadow(
                            color: const Color(0xFF00E699).withOpacity(0.6),
                            blurRadius: 6,
                            spreadRadius: 1,
                          )
                        ]
                      : null,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),

          // 2. Status Badge & Battery Row
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _buildModeBadge(device),
              if (device.batteryPercentage != null)
                Row(
                  children: [
                    Text(
                      device.isCharging == true ? '⚡' : '🔋',
                      style: const TextStyle(fontSize: 12),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      '${device.batteryPercentage}%',
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.7),
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
            ],
          ),
          const SizedBox(height: 12),

          // 3. Metrics Summary: Traps severed & Time saved
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.03),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                Expanded(child: _buildMetricColumn('Traps Severed', '${device.distractionsBlockedToday}', const Color(0xFF00E699))),
                Container(width: 1, height: 24, color: Colors.white.withOpacity(0.08)),
                Expanded(child: _buildMetricColumn('Time Saved', '${device.minutesReclaimedToday}m', Colors.white)),
                Container(width: 1, height: 24, color: Colors.white.withOpacity(0.08)),
                Expanded(child: _buildMetricColumn('Countdown', device.formattedRemainingTime, const Color(0xFFFF9F1C))),
              ],
            ),
          ),
          const SizedBox(height: 12),

          // 4. Action Buttons
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: onLockTapped,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFF00E699),
                    side: BorderSide(color: const Color(0xFF00E699).withOpacity(0.4)),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    padding: const EdgeInsets.symmetric(vertical: 8),
                  ),
                  child: const Text('🔒 Lock 30m', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                ),
              ),
              const SizedBox(width: 8),
              OutlinedButton(
                onPressed: onEmergencyTapped,
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFFFF3B5C),
                  side: BorderSide(color: const Color(0xFFFF3B5C).withOpacity(0.4)),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                ),
                child: const Text('Emergency', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildModeBadge(FleetDeviceModel device) {
    if (device.isStrictLockActive) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: const Color(0xFFFF3B5C).withOpacity(0.18),
          borderRadius: BorderRadius.circular(8),
        ),
        child: const Text(
          '🔒 STRICT LOCK ACTIVE',
          style: TextStyle(color: Color(0xFFFF3B5C), fontSize: 10, fontWeight: FontWeight.w800),
        ),
      );
    } else if (device.activeMode == 'focus') {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: const Color(0xFF00E699).withOpacity(0.18),
          borderRadius: BorderRadius.circular(8),
        ),
        child: const Text(
          '🎯 FOCUSING',
          style: TextStyle(color: Color(0xFF00E699), fontSize: 10, fontWeight: FontWeight.w800),
        ),
      );
    } else if (device.activeMode == 'break') {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: const Color(0xFF0095F6).withOpacity(0.18),
          borderRadius: BorderRadius.circular(8),
        ),
        child: const Text(
          '☕ MINDFUL BREAK',
          style: TextStyle(color: Color(0xFF0095F6), fontSize: 10, fontWeight: FontWeight.w800),
        ),
      );
    } else {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.08),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          'STANDBY',
          style: TextStyle(color: Colors.white.withOpacity(0.6), fontSize: 10, fontWeight: FontWeight.w700),
        ),
      );
    }
  }

  Widget _buildMetricColumn(String label, String value, Color valueColor) {
    return Column(
      children: [
        Text(
          value,
          style: TextStyle(color: valueColor, fontSize: 13, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 1),
        Text(
          label,
          style: TextStyle(color: Colors.white.withOpacity(0.4), fontSize: 9, fontWeight: FontWeight.w600),
        ),
      ],
    );
  }
}
