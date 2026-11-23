import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../engine/daemon/models/battery_profile_config.dart';

/// Screen allowing configuration of background energy budgets and power profiles.
class PowerProfileConfigScreen extends StatefulWidget {
  const PowerProfileConfigScreen({super.key});

  @override
  State<PowerProfileConfigScreen> createState() => _PowerProfileConfigScreenState();
}

class _PowerProfileConfigScreenState extends State<PowerProfileConfigScreen> {
  BatteryPowerMode _selectedMode = BatteryPowerMode.balanced;
  bool _enableZeroCopyBuffers = true;
  bool _enableStrictZeroWakeLock = true;
  bool _alertOnExcessiveDrain = true;

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? const Color(0xFF141416) : const Color(0xFFF8F9FA);
    final cardColor = isDark ? const Color(0xFF1C1C1E) : Colors.white;
    final borderColor = isDark ? const Color(0xFF2C2C2E) : const Color(0xFFE5E5EA);

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        backgroundColor: bgColor,
        elevation: 0,
        title: Text(
          'Power Profile Settings',
          style: GoogleFonts.plusJakartaSans(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: isDark ? Colors.white : Colors.black87,
          ),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'ENERGY PRESERVATION PROFILES',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.1,
                  color: isDark ? Colors.white54 : Colors.black45,
                ),
              ),
              const SizedBox(height: 12),

              _buildProfileOption(
                mode: BatteryPowerMode.ultraSaver,
                title: 'Ultra-Battery Saver',
                drainBudget: '< 0.5% / day',
                description: '2-minute background polling, minimal telemetry, zero GC buffer allocations.',
                isDark: isDark,
                cardColor: cardColor,
                borderColor: borderColor,
              ),
              const SizedBox(height: 10),
              _buildProfileOption(
                mode: BatteryPowerMode.balanced,
                title: 'Balanced (Recommended)',
                drainBudget: '< 1.0% / day',
                description: '30-second telemetry sampling, standard dual-sentinel heartbeat monitoring.',
                isDark: isDark,
                cardColor: cardColor,
                borderColor: borderColor,
              ),
              const SizedBox(height: 10),
              _buildProfileOption(
                mode: BatteryPowerMode.highStrictness,
                title: 'High-Frequency Strict Focus',
                drainBudget: '< 1.5% / day',
                description: '10-second Doze verification, real-time tamper tripwires, aggressive keepalive.',
                isDark: isDark,
                cardColor: cardColor,
                borderColor: borderColor,
              ),

              const SizedBox(height: 24),

              Text(
                'HARDWARE TUNING & KERNEL SWITCHES',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.1,
                  color: isDark ? Colors.white54 : Colors.black45,
                ),
              ),
              const SizedBox(height: 12),

              Material(
                color: cardColor,
                borderRadius: BorderRadius.circular(18),
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: borderColor),
                  ),
                  child: Column(
                    children: [
                      SwitchListTile(
                        value: _enableZeroCopyBuffers,
                        activeColor: const Color(0xFF2ECC71),
                        title: Text(
                          'Direct Ring Buffer Pooling',
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: isDark ? Colors.white : Colors.black87,
                          ),
                        ),
                        subtitle: Text(
                          'Eliminates garbage collector thrashing during DNS bursts.',
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 11,
                            color: isDark ? Colors.white54 : Colors.black45,
                          ),
                        ),
                        onChanged: (val) => setState(() => _enableZeroCopyBuffers = val),
                      ),
                      Divider(height: 1, color: borderColor),
                      SwitchListTile(
                        value: _enableStrictZeroWakeLock,
                        activeColor: const Color(0xFF2ECC71),
                        title: Text(
                          'Strict Zero Wake-Lock Policy',
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: isDark ? Colors.white : Colors.black87,
                          ),
                        ),
                        subtitle: Text(
                          'Trips an alarm if any thread prevents CPU deep sleep > 50ms.',
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 11,
                            color: isDark ? Colors.white54 : Colors.black45,
                          ),
                        ),
                        onChanged: (val) => setState(() => _enableStrictZeroWakeLock = val),
                      ),
                      Divider(height: 1, color: borderColor),
                      SwitchListTile(
                        value: _alertOnExcessiveDrain,
                        activeColor: const Color(0xFF2ECC71),
                        title: Text(
                          'Anomaly Drain Alerts',
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: isDark ? Colors.white : Colors.black87,
                          ),
                        ),
                        subtitle: Text(
                          'Notify if rogue apps cause continuous DNS retry loops.',
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 11,
                            color: isDark ? Colors.white54 : Colors.black45,
                          ),
                        ),
                        onChanged: (val) => setState(() => _alertOnExcessiveDrain = val),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 30),

              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Power profile applied: ${_selectedMode.name}'),
                        backgroundColor: isDark ? Colors.white : Colors.black87,
                      ),
                    );
                    Navigator.pop(context);
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF2ECC71),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    textStyle: GoogleFonts.plusJakartaSans(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  child: const Text('SAVE POWER PROFILE'),
                ),
              ),

              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildProfileOption({
    required BatteryPowerMode mode,
    required String title,
    required String drainBudget,
    required String description,
    required bool isDark,
    required Color cardColor,
    required Color borderColor,
  }) {
    final bool isSelected = _selectedMode == mode;
    final Color activeColor = const Color(0xFF2ECC71);

    return InkWell(
      onTap: () => setState(() => _selectedMode = mode),
      borderRadius: BorderRadius.circular(18),
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: cardColor,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: isSelected ? activeColor : borderColor,
            width: isSelected ? 1.5 : 1.0,
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              margin: const EdgeInsets.only(top: 2),
              width: 20,
              height: 20,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: isSelected ? activeColor : (isDark ? Colors.white38 : Colors.black38),
                  width: 2,
                ),
              ),
              child: isSelected
                  ? Center(
                      child: Container(
                        width: 10,
                        height: 10,
                        decoration: BoxDecoration(
                          color: activeColor,
                          shape: BoxShape.circle,
                        ),
                      ),
                    )
                  : null,
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        title,
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: isDark ? Colors.white : Colors.black87,
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: activeColor.withOpacity(0.12),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          drainBudget,
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                            color: activeColor,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    description,
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 11.5,
                      color: isDark ? Colors.white60 : Colors.black54,
                      height: 1.35,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
