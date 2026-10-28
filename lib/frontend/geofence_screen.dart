import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../backend/geofence_service.dart';

/**
 * GeofenceScreen
 * ==============
 * Wabi-Sabi themed UI for managing location-based focus boundaries and
 * inspecting geographic conditional uninstallation posture.
 *
 * Visual Components:
 * - Concentric radar canvas visualizing distance to nearest geofence perimeter.
 * - Dynamic Status Pill:
 *     * OUTSIDE ZONE (Green): Normal mode active -> Uninstallation is 100% permitted.
 *     * INSIDE ZONE (Amber): Location focus locked -> Uninstallation blocked until exit.
 * - Life Safety Guarantee:
 *     * Floating Emergency SOS 112 button always unhindered.
 * - Simulation controls for testing perimeter enter/exit transitions.
 */
class GeofenceScreen extends StatefulWidget {
  const GeofenceScreen({Key? key}) : super(key: key);

  @override
  State<GeofenceScreen> createState() => _GeofenceScreenState();
}

class _GeofenceScreenState extends State<GeofenceScreen> {
  GeofenceStatusModel _status = const GeofenceStatusModel();
  List<GeofenceZoneModel> _zones = [];
  bool _isLoading = false;
  String _actionMessage = 'Location boundary active.';

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    final zones = await FocusGeofenceService.getRegisteredZones();
    final status = await FocusGeofenceService.evaluateCoordinates(37.7937, -122.4000);
    if (mounted) {
      setState(() {
        _zones = zones;
        _status = status;
        _isLoading = false;
      });
    }
  }

  Future<void> _simulateLocation(double lat, double lon, String label) async {
    setState(() => _isLoading = true);
    final newStatus = await FocusGeofenceService.evaluateCoordinates(lat, lon);
    if (mounted) {
      setState(() {
        _status = newStatus;
        _isLoading = false;
        _actionMessage = newStatus.insideRestrictedGeofence
            ? 'Simulated coordinates inside $label. Focus locked!'
            : 'Simulated coordinates outside perimeter. Uninstallation permitted!';
      });
    }
  }

  Future<void> _triggerEmergencySos() async {
    await FocusGeofenceService.triggerEmergencyCall();
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
    final isLocked = _status.insideRestrictedGeofence;

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF141516) : const Color(0xFFFAF8F5),
      appBar: AppBar(
        title: const Text(
          'Geofenced Boundary Enforcer',
          style: TextStyle(fontFamily: 'RobotoMono', fontSize: 16, fontWeight: FontWeight.w600),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadData,
            tooltip: 'Refresh Geofence Status',
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
                  _buildRadarCard(isDark, isLocked),
                  const SizedBox(height: 16),
                  _buildPostureGuaranteeCard(isDark, isLocked),
                  const SizedBox(height: 16),
                  _buildSimulationControls(isDark),
                  const SizedBox(height: 16),
                  _buildRegisteredZonesList(isDark),
                  const SizedBox(height: 24),
                ],
              ),
            ),
      floatingActionButton: FloatingActionButton.extended(
        key: const Key('emergency_sos_geofence_btn'),
        onPressed: _triggerEmergencySos,
        backgroundColor: const Color(0xFFD32F2F),
        foregroundColor: Colors.white,
        icon: const Icon(Icons.emergency, size: 20),
        label: const Text('Emergency SOS 112', style: TextStyle(fontFamily: 'RobotoMono', fontWeight: FontWeight.bold)),
      ),
    );
  }

  Widget _buildRadarCard(bool isDark, bool isLocked) {
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
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Perimeter Proximity Radar',
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
                  isLocked ? 'RESTRICTED ZONE (LOCKED)' : 'STANDBY (NORMAL MODE)',
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
          const SizedBox(height: 16),
          Center(
            child: CustomPaint(
              size: const Size(220, 220),
              painter: _GeofenceRadarPainter(
                isLocked: isLocked,
                insideDistanceFraction: isLocked ? 0.3 : 0.85,
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            isLocked
                ? 'Inside: ${_status.matchedZoneName}'
                : 'Closest Perimeter: ${_status.closestZoneName}',
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 4),
          Text(
            'GPS Coordinates: ${_status.latitude.toStringAsFixed(4)}, ${_status.longitude.toStringAsFixed(4)}',
            style: TextStyle(
              fontFamily: 'RobotoMono',
              fontSize: 12,
              color: isDark ? const Color(0xFF90A4AE) : const Color(0xFF757575),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPostureGuaranteeCard(bool isDark, bool isLocked) {
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
                ? '• Device is INSIDE a restricted campus geofence. Uninstallation is LOCKED to prevent focus evasion until exiting the perimeter.'
                : '• Device is OUTSIDE all restricted perimeters. Normal Mode active: Uninstallation is 100% PERMITTED with zero friction.',
            style: TextStyle(
              fontSize: 12,
              height: 1.4,
              color: isDark ? const Color(0xFFCFD8DC) : const Color(0xFF424242),
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            '• Life Safety: Standard telecom dialing (911/112) is NEVER blocked, intercepted, or sandboxed under any geofence.',
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
            'Boundary Simulation Sandbox',
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 6),
          Text(
            _actionMessage,
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
                  key: const Key('simulate_enter_hq_btn'),
                  onPressed: () => _simulateLocation(37.7937, -122.4000, 'Global HQ'),
                  icon: const Icon(Icons.location_on, size: 16),
                  label: const Text('Enter SF HQ', style: TextStyle(fontSize: 12)),
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
                  key: const Key('simulate_exit_btn'),
                  onPressed: () => _simulateLocation(37.7500, -122.3500, 'Outside'),
                  icon: const Icon(Icons.exit_to_app, size: 16),
                  label: const Text('Exit (Outside)', style: TextStyle(fontSize: 12)),
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

  Widget _buildRegisteredZonesList(bool isDark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 4.0, vertical: 4.0),
          child: Text(
            'Registered Geofenced Perimeters',
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
          ),
        ),
        const SizedBox(height: 8),
        ..._zones.map((z) {
          return Container(
            margin: const EdgeInsets.only(bottom: 8.0),
            padding: const EdgeInsets.all(12.0),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF1E2022) : Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isDark ? const Color(0xFF2C3236) : const Color(0xFFE0E0E0),
              ),
            ),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 18,
                  backgroundColor: z.enforceLock ? const Color(0x33FFB74D) : const Color(0x3390CAF9),
                  child: Icon(
                    Icons.security,
                    size: 18,
                    color: z.enforceLock ? const Color(0xFFFFB74D) : const Color(0xFF90CAF9),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        z.name,
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Radius: ${z.radiusMeters.toInt()}m | ${z.latitude.toStringAsFixed(4)}, ${z.longitude.toStringAsFixed(4)}',
                        style: TextStyle(
                          fontFamily: 'RobotoMono',
                          fontSize: 11,
                          color: isDark ? const Color(0xFF90A4AE) : const Color(0xFF757575),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        }).toList(),
      ],
    );
  }
}

class _GeofenceRadarPainter extends CustomPainter {
  final bool isLocked;
  final double insideDistanceFraction;

  _GeofenceRadarPainter({
    required this.isLocked,
    required this.insideDistanceFraction,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final maxRadius = size.width / 2 - 10;

    // Draw concentric range rings
    final ringPaint = Paint()
      ..color = isLocked ? const Color(0x22FFB74D) : const Color(0x2281C784)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;

    for (int i = 1; i <= 3; i++) {
      canvas.drawCircle(center, (maxRadius / 3) * i, ringPaint);
    }

    // Draw Geofence Boundary
    final boundaryRadius = maxRadius * 0.6;
    final boundaryPaint = Paint()
      ..color = const Color(0xFF8B5A2B).withOpacity(0.6)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0;
    canvas.drawCircle(center, boundaryRadius, boundaryPaint);

    final boundaryFill = Paint()
      ..color = const Color(0xFF8B5A2B).withOpacity(0.08)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(center, boundaryRadius, boundaryFill);

    // Draw device dot
    final deviceDist = maxRadius * insideDistanceFraction;
    final deviceAngle = math.pi / 4;
    final deviceOffset = Offset(
      center.dx + deviceDist * math.cos(deviceAngle),
      center.dy + deviceDist * math.sin(deviceAngle),
    );

    final dotPaint = Paint()
      ..color = isLocked ? const Color(0xFFFFB74D) : const Color(0xFF81C784)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(deviceOffset, 7.0, dotPaint);

    final dotRingPaint = Paint()
      ..color = isLocked ? const Color(0xFFFFB74D) : const Color(0xFF81C784)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0;
    canvas.drawCircle(deviceOffset, 12.0, dotRingPaint);
  }

  @override
  bool shouldRepaint(covariant _GeofenceRadarPainter oldDelegate) {
    return oldDelegate.isLocked != isLocked ||
        oldDelegate.insideDistanceFraction != insideDistanceFraction;
  }
}
