import 'package:flutter/material.dart';
import '../../../engine/profile/fleet_device_model.dart';
import '../../../engine/profile/cross_device_sync_coordinator.dart';
import '../../widgets/fleet/fleet_device_card.dart';
import 'browser_extension_pairing_screen.dart';

/// Master control console for orchestrating the user's multi-device fleet
/// (Android phone, laptop browser extensions, desktop daemons).
class FleetOrchestrationMasterScreen extends StatefulWidget {
  final CrossDeviceSyncCoordinator coordinator;

  const FleetOrchestrationMasterScreen({
    super.key,
    required this.coordinator,
  });

  @override
  State<FleetOrchestrationMasterScreen> createState() => _FleetOrchestrationMasterScreenState();
}

class _FleetOrchestrationMasterScreenState extends State<FleetOrchestrationMasterScreen> {
  int _selectedDurationMinutes = 45;
  bool _isStrictLock = true;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0E0E12),
      appBar: AppBar(
        backgroundColor: const Color(0xFF14141A),
        elevation: 0,
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Fleet Orchestration',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: Colors.white),
            ),
            Text(
              'Unified Cross-Device Synchronization',
              style: TextStyle(fontSize: 11, color: Colors.white54),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Text('📱➕', style: TextStyle(fontSize: 18)),
            tooltip: 'Pair New Device / Extension',
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => BrowserExtensionPairingScreen(
                    userId: widget.coordinator.userId,
                  ),
                ),
              );
            },
          ),
        ],
      ),
      body: StreamBuilder<List<FleetDeviceModel>>(
        stream: widget.coordinator.fleetStream,
        initialData: widget.coordinator.fleetDevices,
        builder: (context, snapshot) {
          final devices = snapshot.data ?? [];
          final onlineCount = devices.where((d) => d.isOnline).length;

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              // 1. Fleet Telemetry Header
              _buildFleetHeaderCard(onlineCount, devices.length),
              const SizedBox(height: 16),

              // 2. Global Fleet Command Console
              _buildGlobalCommandCard(devices.length),
              const SizedBox(height: 20),

              // 3. Paired Devices List
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Expanded(
                    child: Text(
                      'CONNECTED NODES',
                      style: TextStyle(
                        color: Colors.white54,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.8,
                      ),
                    ),
                  ),
                  TextButton.icon(
                    onPressed: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => BrowserExtensionPairingScreen(
                            userId: widget.coordinator.userId,
                          ),
                        ),
                      );
                    },
                    icon: const Icon(Icons.qr_code, size: 14, color: Color(0xFF00E699)),
                    label: const Text(
                      'Pair Extension',
                      style: TextStyle(color: Color(0xFF00E699), fontSize: 11),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),

              if (devices.isEmpty)
                _buildEmptyFleetPlaceholder()
              else
                ...devices.map(
                  (dev) => FleetDeviceCard(
                    device: dev,
                    onLockTapped: () => _handleSingleLock(dev.deviceId),
                    onEmergencyTapped: () => _handleEmergencyRequest(dev.deviceId),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildFleetHeaderCard(int onlineCount, int totalCount) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF16161E),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(0.08)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          Expanded(child: _buildStatColumn('Online Nodes', '$onlineCount / $totalCount', const Color(0xFF00E699))),
          Container(width: 1, height: 32, color: Colors.white.withOpacity(0.1)),
          Expanded(child: _buildStatColumn('Master State', 'SYNCHRONIZED', const Color(0xFF0095F6))),
          Container(width: 1, height: 32, color: Colors.white.withOpacity(0.1)),
          Expanded(child: _buildStatColumn('Replay Shield', 'HMAC-SHA256', const Color(0xFFFF9F1C))),
        ],
      ),
    );
  }

  Widget _buildGlobalCommandCard(int totalDevices) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            const Color(0xFF1E1E28),
            const Color(0xFF181822),
          ],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFFF3B5C).withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: const [
              Text('⚡', style: TextStyle(fontSize: 20)),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'FLEET-WIDE BROADCAST DISPATCHER',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'Push strict focus lockout simultaneously to your phone, browser extensions, and laptops.',
            style: TextStyle(color: Colors.white.withOpacity(0.6), fontSize: 12),
          ),
          const SizedBox(height: 14),

          // Duration Chips
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [25, 45, 90].map((mins) {
              final isSelected = _selectedDurationMinutes == mins;
              return ChoiceChip(
                label: Text('${mins}m Focus'),
                selected: isSelected,
                selectedColor: const Color(0xFF00E699),
                backgroundColor: const Color(0xFF262632),
                labelStyle: TextStyle(
                  color: isSelected ? Colors.black : Colors.white,
                  fontWeight: FontWeight.w700,
                  fontSize: 12,
                ),
                onSelected: (selected) {
                  if (selected) setState(() => _selectedDurationMinutes = mins);
                },
              );
            }).toList(),
          ),
          const SizedBox(height: 14),

          // Action Buttons
          Row(
            children: [
              Expanded(
                flex: 3,
                child: ElevatedButton.icon(
                  onPressed: () => _dispatchFleetLock(totalDevices),
                  icon: const Icon(Icons.lock, size: 16),
                  label: Text('Lock All ($totalDevices Nodes)'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFFF3B5C),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                flex: 2,
                child: ElevatedButton.icon(
                  onPressed: _dispatchFleetBreak,
                  icon: const Icon(Icons.coffee, size: 16),
                  label: const Text('Break (5m)'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF2E2E3A),
                    foregroundColor: const Color(0xFF0095F6),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyFleetPlaceholder() {
    return Container(
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(
        color: const Color(0xFF16161C),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(0.06)),
      ),
      child: Column(
        children: [
          const Text('📱💻', style: TextStyle(fontSize: 40)),
          const SizedBox(height: 12),
          const Text(
            'No Companion Devices Paired',
            style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 6),
          Text(
            'Install the FocusDNS Chrome / Brave / Edge extension or desktop daemon to synchronize your focus across all screens.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white.withOpacity(0.55), fontSize: 12),
          ),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => BrowserExtensionPairingScreen(
                    userId: widget.coordinator.userId,
                  ),
                ),
              );
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF00E699),
              foregroundColor: Colors.black,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            child: const Text('Open Pairing Studio', style: TextStyle(fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }

  Widget _buildStatColumn(String label, String value, Color color) {
    return Column(
      children: [
        Text(value, style: TextStyle(color: color, fontSize: 14, fontWeight: FontWeight.w800)),
        const SizedBox(height: 2),
        Text(label, style: TextStyle(color: Colors.white.withOpacity(0.45), fontSize: 10, fontWeight: FontWeight.w600)),
      ],
    );
  }

  void _dispatchFleetLock(int totalDevices) {
    widget.coordinator.broadcastFocusLock(
      durationMinutes: _selectedDurationMinutes,
      isStrict: _isStrictLock,
    );
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('🔒 Strict Lock engaged across $totalDevices nodes for $_selectedDurationMinutes mins.'),
        backgroundColor: const Color(0xFFFF3B5C),
      ),
    );
  }

  void _dispatchFleetBreak() {
    widget.coordinator.broadcastBreak(breakMinutes: 5);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('☕ Transitioned all paired devices to 5m mindful break.'),
        backgroundColor: Color(0xFF0095F6),
      ),
    );
  }

  void _handleSingleLock(String deviceId) {
    widget.coordinator.broadcastFocusLock(
      durationMinutes: 30,
      isStrict: true,
    );
  }

  void _handleEmergencyRequest(String deviceId) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A22),
        title: const Text('Emergency Override Request', style: TextStyle(color: Colors.white)),
        content: const Text(
          'Emergency requests are routed to your designated accountability partner for signature signoff.',
          style: TextStyle(color: Colors.white70, fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Close', style: TextStyle(color: Color(0xFF00E699))),
          ),
        ],
      ),
    );
  }
}
