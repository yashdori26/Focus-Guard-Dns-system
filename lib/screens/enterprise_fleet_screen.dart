// FocusDNS Enterprise Fleet Screen - Real-Time WebSocket Push & Fleet Lock Control

import 'package:flutter/material.dart';
import '../models/enterprise_models.dart';
import '../services/enterprise_service.dart';

class EnterpriseFleetScreen extends StatefulWidget {
  final EnterpriseService? service;

  const EnterpriseFleetScreen({super.key, this.service});

  @override
  State<EnterpriseFleetScreen> createState() => _EnterpriseFleetScreenState();
}

class _EnterpriseFleetScreenState extends State<EnterpriseFleetScreen> {
  late final EnterpriseService _service;
  bool _isLoading = true;
  DeviceFleetModel? _activeFleet;
  List<FleetDeviceConnectionModel> _devices = [];
  String? _feedbackMessage;
  bool _isError = false;

  @override
  void initState() {
    super.initState();
    _service = widget.service ?? EnterpriseService();
    _loadFleetData();
  }

  Future<void> _loadFleetData() async {
    setState(() => _isLoading = true);
    try {
      final fleet = await _service.getFleet('flt_cart_4b');
      // Mock devices connected over WebSocket
      final devices = [
        FleetDeviceConnectionModel(
          deviceId: 'chromebook_01',
          orgId: 'org_springfield',
          unitId: 'unit_lincoln_high',
          fleetId: 'flt_cart_4b',
          platform: 'CHROMEOS',
          connectedAt: DateTime.now().millisecondsSinceEpoch / 1000.0 - 7200,
          lastHeartbeat: DateTime.now().millisecondsSinceEpoch / 1000.0 - 5,
          rttMs: 14.2,
          pendingQueueSize: 0,
          isAlive: true,
        ),
        FleetDeviceConnectionModel(
          deviceId: 'chromebook_02',
          orgId: 'org_springfield',
          unitId: 'unit_lincoln_high',
          fleetId: 'flt_cart_4b',
          platform: 'CHROMEOS',
          connectedAt: DateTime.now().millisecondsSinceEpoch / 1000.0 - 5400,
          lastHeartbeat: DateTime.now().millisecondsSinceEpoch / 1000.0 - 2,
          rttMs: 18.5,
          pendingQueueSize: 0,
          isAlive: true,
        ),
        FleetDeviceConnectionModel(
          deviceId: 'chromebook_03',
          orgId: 'org_springfield',
          unitId: 'unit_lincoln_high',
          fleetId: 'flt_cart_4b',
          platform: 'CHROMEOS',
          connectedAt: DateTime.now().millisecondsSinceEpoch / 1000.0 - 1200,
          lastHeartbeat: DateTime.now().millisecondsSinceEpoch / 1000.0 - 8,
          rttMs: 22.0,
          pendingQueueSize: 0,
          isAlive: true,
        ),
      ];

      if (mounted) {
        setState(() {
          _activeFleet = fleet;
          _devices = devices;
          _isLoading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _toggleFleetLock(bool lock) async {
    if (_activeFleet == null) return;
    setState(() => _isLoading = true);
    try {
      final updated = lock
          ? await _service.lockFleet(_activeFleet!.fleetId, 3600)
          : await _service.unlockFleet(_activeFleet!.fleetId);

      if (mounted) {
        setState(() {
          _activeFleet = updated;
          _isLoading = false;
          _feedbackMessage = lock ? 'Fleet locked for 3600s.' : 'Fleet unlocked.';
          _isError = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _feedbackMessage = e.toString();
          _isError = true;
        });
      }
    }
  }

  Future<void> _attemptWhitelist(String domain) async {
    if (_activeFleet == null) return;
    try {
      final res = await _service.modifyFleetWhitelist(_activeFleet!.fleetId, domain);
      if (mounted) {
        setState(() {
          _feedbackMessage = res['message'] ?? "Domain '$domain' whitelisted.";
          _isError = false;
        });
      }
    } catch (e) {
      // Inviolable Conditional Whitelisting Law feedback
      if (mounted) {
        setState(() {
          _feedbackMessage = e.toString();
          _isError = true;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isLocked = _activeFleet?.isLocked ?? false;

    return Scaffold(
      backgroundColor: const Color(0xFF141416),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1E1E20),
        elevation: 0,
        title: const Text(
          'Fleet Push & Remote Control Center',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.white70),
            onPressed: _loadFleetData,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFFFFB74D)))
          : SingleChildScrollView(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildWebSocketStatusBanner(),
                  const SizedBox(height: 16),
                  if (_feedbackMessage != null) _buildFeedbackBanner(),
                  const SizedBox(height: 16),
                  _buildFleetCard(isLocked),
                  const SizedBox(height: 18),
                  _buildActionButtons(isLocked),
                  const SizedBox(height: 18),
                  _buildConnectedDevicesTable(),
                ],
              ),
            ),
    );
  }

  Widget _buildWebSocketStatusBanner() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E20),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF2C2C2E)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Container(width: 8, height: 8, decoration: const BoxDecoration(color: Color(0xFF4CAF50), shape: BoxShape.circle)),
              const SizedBox(width: 8),
              const Text('WebSocket Fleet Hub: CONNECTED', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.white)),
            ],
          ),
          const Text('Sub-50ms Fanout Active', style: TextStyle(fontSize: 11, color: Color(0xFF888888))),
        ],
      ),
    );
  }

  Widget _buildFeedbackBanner() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _isError ? const Color(0xFFEF5350).withOpacity(0.15) : const Color(0xFF4CAF50).withOpacity(0.15),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _isError ? const Color(0xFFEF5350) : const Color(0xFF4CAF50)),
      ),
      child: Row(
        children: [
          Icon(_isError ? Icons.lock : Icons.check_circle, color: _isError ? const Color(0xFFEF5350) : const Color(0xFF4CAF50), size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              _feedbackMessage!,
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: _isError ? const Color(0xFFEF5350) : const Color(0xFF4CAF50)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFleetCard(bool isLocked) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E20),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: isLocked ? const Color(0xFFEF5350) : const Color(0xFF2C2C2E)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                _activeFleet?.name ?? 'Fleet',
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: isLocked ? const Color(0xFFEF5350).withOpacity(0.15) : const Color(0xFF4CAF50).withOpacity(0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  isLocked ? 'LOCKED (${_activeFleet?.remainingLockSeconds}s)' : 'IDLE',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: isLocked ? const Color(0xFFEF5350) : const Color(0xFF4CAF50),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Platform: ${_activeFleet?.platform} • Policy: ${_activeFleet?.policyProfileId}',
            style: const TextStyle(fontSize: 12, color: Color(0xFF888888)),
          ),
          const SizedBox(height: 14),
          const Text(
            'Conditional Whitelisting Law: Whitelist additions are strictly blocked when focus session is locked.',
            style: TextStyle(fontSize: 11, color: Color(0xFFAAAAAA), height: 1.3),
          ),
        ],
      ),
    );
  }

  Widget _buildActionButtons(bool isLocked) {
    return Row(
      children: [
        Expanded(
          child: ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: isLocked ? const Color(0xFF4CAF50) : const Color(0xFFEF5350),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 12),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            icon: Icon(isLocked ? Icons.lock_open : Icons.lock, size: 16),
            label: Text(isLocked ? 'Unlock Fleet' : 'Lock Fleet Focus (1h)'),
            onPressed: () => _toggleFleetLock(!isLocked),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF2C2C2E),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 12),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            icon: const Icon(Icons.add_circle_outline, size: 16),
            label: const Text('Test Whitelist'),
            onPressed: () => _showWhitelistDialog(),
          ),
        ),
      ],
    );
  }

  void _showWhitelistDialog() {
    final controller = TextEditingController(text: 'youtube.com');
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E20),
        title: const Text('Test Whitelist Mutation', style: TextStyle(color: Colors.white, fontSize: 16)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Enter domain to whitelist:', style: TextStyle(fontSize: 12, color: Colors.white70)),
            const SizedBox(height: 8),
            TextField(
              controller: controller,
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(
                filled: true,
                fillColor: Color(0xFF141416),
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            child: const Text('Cancel', style: TextStyle(color: Colors.white70)),
            onPressed: () => Navigator.of(ctx).pop(),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF64B5F6), foregroundColor: Colors.black),
            child: const Text('Whitelist'),
            onPressed: () {
              Navigator.of(ctx).pop();
              _attemptWhitelist(controller.text.trim());
            },
          ),
        ],
      ),
    );
  }

  Widget _buildConnectedDevicesTable() {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E20),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF2C2C2E)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Live Connected Devices', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.white)),
              Text('${_devices.length} Online', style: const TextStyle(fontSize: 12, color: Color(0xFF81C784))),
            ],
          ),
          const SizedBox(height: 12),
          ..._devices.map((dev) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  children: [
                    const Icon(Icons.laptop_chromebook, color: Color(0xFF888888), size: 16),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(dev.deviceId, style: const TextStyle(fontSize: 13, color: Colors.white)),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: const Color(0xFF81C784).withOpacity(0.15),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        '${dev.rttMs.toStringAsFixed(1)} ms RTT',
                        style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Color(0xFF81C784)),
                      ),
                    ),
                  ],
                ),
              )),
        ],
      ),
    );
  }
}
