import 'package:flutter/material.dart';
import '../backend/schedule_service.dart';

/**
 * EnterpriseScheduleScreen
 * ========================
 * Wabi-Sabi themed UI for managing scheduled enterprise focus windows and
 * inspecting time-based conditional uninstallation posture.
 *
 * Core Law Verification:
 * - When current time is INSIDE a scheduled window: Focus is locked, uninstallation is BLOCKED.
 * - When current time is OUTSIDE scheduled windows: Normal mode active, uninstallation is 100% PERMITTED.
 * - Emergency Exemption: Standard telecom dialing (911/112) is NEVER blocked by schedules.
 */
class EnterpriseScheduleScreen extends StatefulWidget {
  const EnterpriseScheduleScreen({Key? key}) : super(key: key);

  @override
  State<EnterpriseScheduleScreen> createState() => _EnterpriseScheduleScreenState();
}

class _EnterpriseScheduleScreenState extends State<EnterpriseScheduleScreen> {
  ScheduleStatusModel _status = const ScheduleStatusModel();
  List<FocusScheduleIntervalModel> _intervals = [];
  bool _isLoading = false;
  String _simulationMessage = 'Schedule evaluation active.';

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    final intervals = await FocusScheduleService.getScheduleIntervals();
    final status = await FocusScheduleService.evaluateSchedule();
    if (mounted) {
      setState(() {
        _intervals = intervals;
        _status = status;
        _isLoading = false;
      });
    }
  }

  Future<void> _simulateTime(int hour, int minute, String label) async {
    setState(() => _isLoading = true);
    final status = await FocusScheduleService.evaluateSchedule(
      dayOfWeek: 1, // Monday
      hour: hour,
      minute: minute,
    );
    if (mounted) {
      setState(() {
        _status = status;
        _isLoading = false;
        _simulationMessage = status.inFocusWindow
            ? 'Simulated time ($label): INSIDE focus window. Uninstallation locked!'
            : 'Simulated time ($label): OUTSIDE focus window. Clean uninstallation permitted!';
      });
    }
  }

  Future<void> _triggerEmergencySos() async {
    await FocusScheduleService.triggerEmergencyCall();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Emergency SOS 112 dialer launched (Life Safety Exemption).'),
          duration: Duration(seconds: 3),
          backgroundColor: Color(0xFFD32F2F),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final isLocked = _status.inFocusWindow;

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF141516) : const Color(0xFFFAF8F5),
      appBar: AppBar(
        title: const Text(
          'Enterprise Focus Schedule',
          style: TextStyle(fontFamily: 'RobotoMono', fontSize: 16, fontWeight: FontWeight.w600),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadData,
            tooltip: 'Refresh Schedule Status',
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildTimelineStatusCard(isDark, isLocked),
                  const SizedBox(height: 16),
                  _buildGuaranteeCard(isDark, isLocked),
                  const SizedBox(height: 16),
                  _buildSimulationControls(isDark),
                  const SizedBox(height: 16),
                  _buildScheduledIntervalsList(isDark),
                  const SizedBox(height: 24),
                ],
              ),
            ),
      floatingActionButton: FloatingActionButton.extended(
        key: const Key('emergency_sos_schedule_btn'),
        onPressed: _triggerEmergencySos,
        backgroundColor: const Color(0xFFD32F2F),
        foregroundColor: Colors.white,
        icon: const Icon(Icons.emergency, size: 20),
        label: const Text('Emergency SOS 112', style: TextStyle(fontFamily: 'RobotoMono', fontWeight: FontWeight.bold)),
      ),
    );
  }

  Widget _buildTimelineStatusCard(bool isDark, bool isLocked) {
    return Container(
      padding: const EdgeInsets.all(20.0),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E2022) : Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isLocked
              ? const Color(0xFFFFB74D)
              : (isDark ? const Color(0xFF2C3236) : const Color(0xFFE0E0E0)),
          width: isLocked ? 1.5 : 1.0,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Timetable Posture',
                style: TextStyle(
                  fontFamily: 'RobotoMono',
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: isDark ? const Color(0xFFB0BEC5) : const Color(0xFF5D4037),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: isLocked ? const Color(0x33FFB74D) : const Color(0x3381C784),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: isLocked ? const Color(0xFFFFB74D) : const Color(0xFF81C784),
                  ),
                ),
                child: Text(
                  isLocked ? 'FOCUS SESSION ACTIVE (LOCKED)' : 'STANDBY (NORMAL MODE)',
                  style: TextStyle(
                    fontFamily: 'RobotoMono',
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: isLocked ? const Color(0xFFFFB74D) : const Color(0xFF81C784),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              CircleAvatar(
                radius: 22,
                backgroundColor: isLocked ? const Color(0x33FFB74D) : const Color(0x3381C784),
                child: Icon(
                  isLocked ? Icons.alarm_on : Icons.alarm_off,
                  color: isLocked ? const Color(0xFFFFB74D) : const Color(0xFF81C784),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _status.activeWindowTitle,
                      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      isLocked
                          ? 'Focus protection armed. Uninstallation locked.'
                          : 'Outside scheduled focus. Clean uninstallation permitted.',
                      style: TextStyle(
                        fontFamily: 'RobotoMono',
                        fontSize: 12,
                        color: isDark ? const Color(0xFF90A4AE) : const Color(0xFF757575),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildGuaranteeCard(bool isDark, bool isLocked) {
    return Container(
      padding: const EdgeInsets.all(16.0),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E2022) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark ? const Color(0xFF2C3236) : const Color(0xFFE0E0E0),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                isLocked ? Icons.lock : Icons.lock_open,
                size: 18,
                color: isLocked ? const Color(0xFFFFB74D) : const Color(0xFF81C784),
              ),
              const SizedBox(width: 8),
              const Text(
                'Inviolable Uninstallation Law',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            isLocked
                ? '• Device is INSIDE a scheduled enterprise focus window. Uninstallation is LOCKED until the scheduled interval ends.'
                : '• Device is OUTSIDE scheduled focus windows. Normal Mode active: Uninstallation is 100% PERMITTED with zero friction.',
            style: TextStyle(
              fontSize: 12,
              height: 1.4,
              color: isDark ? const Color(0xFFCFD8DC) : const Color(0xFF424242),
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            '• Life Safety: Standard telecom dialing (911/112) is NEVER blocked, intercepted, or sandboxed under any schedule.',
            style: TextStyle(
              fontSize: 12,
              height: 1.4,
              color: Color(0xFF81D4FA),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSimulationControls(bool isDark) {
    return Container(
      padding: const EdgeInsets.all(16.0),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E2022) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark ? const Color(0xFF2C3236) : const Color(0xFFE0E0E0),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Time-Shift Simulation Sandbox',
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 6),
          Text(
            _simulationMessage,
            style: TextStyle(
              fontFamily: 'RobotoMono',
              fontSize: 11,
              color: isDark ? const Color(0xFF90A4AE) : const Color(0xFF616161),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  key: const Key('simulate_work_hours_btn'),
                  onPressed: () => _simulateTime(10, 30, '10:30 AM Work Hours'),
                  icon: const Icon(Icons.work, size: 16),
                  label: const Text('10:30 AM (In-Window)', style: TextStyle(fontSize: 12)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF2B2D2F),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  key: const Key('simulate_off_hours_btn'),
                  onPressed: () => _simulateTime(18, 30, '18:30 PM Off-Hours'),
                  icon: const Icon(Icons.nightlight, size: 16),
                  label: const Text('18:30 PM (Off-Hours)', style: TextStyle(fontSize: 12)),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: Color(0xFF81C784)),
                    foregroundColor: const Color(0xFF81C784),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildScheduledIntervalsList(bool isDark) {
    const dayNames = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 4.0, vertical: 4.0),
          child: Text(
            'Recurring Enterprise Focus Timetables',
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
          ),
        ),
        const SizedBox(height: 8),
        ..._intervals.map((iv) {
          return Container(
            margin: const EdgeInsets.only(bottom: 10.0),
            padding: const EdgeInsets.all(14.0),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF1E2022) : Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: isDark ? const Color(0xFF2C3236) : const Color(0xFFE0E0E0),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      iv.title,
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                    ),
                    Text(
                      '${iv.startTimeFormatted} - ${iv.endTimeFormatted}',
                      style: const TextStyle(
                        fontFamily: 'RobotoMono',
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                        color: Color(0xFF8B5A2B),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: List.generate(7, (idx) {
                    final dayNum = idx + 1;
                    final isSelected = iv.daysOfWeek.contains(dayNum);
                    return Container(
                      margin: const EdgeInsets.only(right: 6.0),
                      width: 28,
                      height: 28,
                      decoration: BoxDecoration(
                        color: isSelected
                            ? const Color(0xFF2B2D2F)
                            : (isDark ? const Color(0xFF181A1B) : const Color(0xFFF0F0F0)),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                          color: isSelected
                              ? const Color(0xFF8B5A2B)
                              : (isDark ? const Color(0xFF2C3236) : const Color(0xFFE0E0E0)),
                        ),
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        dayNames[idx],
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: isSelected
                              ? Colors.white
                              : (isDark ? const Color(0xFF78909C) : const Color(0xFF9E9E9E)),
                        ),
                      ),
                    );
                  }),
                ),
              ],
            ),
          );
        }).toList(),
      ],
    );
  }
}
