import 'dart:async';
import 'package:flutter/material.dart';
import '../backend/attestation_service.dart';

/// Card showing Multi-OEM heuristic sandboxing coverage (Samsung, Xiaomi, Oppo, Vivo, Huawei, Pixel),
/// System Alert Window overlay status, and evasion resistance mechanisms.
class MultiOemShieldCard extends StatefulWidget {
  const MultiOemShieldCard({super.key});

  @override
  State<MultiOemShieldCard> createState() => _MultiOemShieldCardState();
}

class _MultiOemShieldCardState extends State<MultiOemShieldCard> {
  bool _canDrawOverlays = false;
  bool _isLoading = false;

  final List<Map<String, dynamic>> _supportedOems = const [
    {'name': 'Samsung OneUI', 'pkg': 'com.samsung.android.settings', 'supported': true},
    {'name': 'Xiaomi HyperOS', 'pkg': 'com.miui.securitycenter', 'supported': true},
    {'name': 'Oppo ColorOS', 'pkg': 'com.coloros.safecenter', 'supported': true},
    {'name': 'Vivo OriginOS', 'pkg': 'com.vivo.permissionmanager', 'supported': true},
    {'name': 'Huawei EMUI', 'pkg': 'com.huawei.systemmanager', 'supported': true},
    {'name': 'Google Pixel', 'pkg': 'com.android.settings', 'supported': true},
  ];

  final List<String> _evasionVectors = const [
    'App Info "Clear Data / Storage" button interception',
    'Package Manager "Force Stop" neutralization',
    'Private DNS (DoT) override circumvention detection',
    'Device Administrator deactivation rejection hook',
    'System clock & Monotonic time drift anti-rollback',
    'Developer Options (ADB USB debugging) heuristic monitor',
  ];

  @override
  void initState() {
    super.initState();
    _checkOverlayState();
  }

  Future<void> _checkOverlayState() async {
    final allowed = await FocusAttestationManager.canDrawOverlays();
    if (mounted) {
      setState(() {
        _canDrawOverlays = allowed;
        _isLoading = false;
      });
    }
  }

  Future<void> _requestOverlayPermission() async {
    await FocusAttestationManager.requestOverlayPermission();
    await Future.delayed(const Duration(milliseconds: 500));
    _checkOverlayState();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E20),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF2C2C2E)),
      ),
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          const Row(
            children: [
              Icon(Icons.devices, size: 20, color: Color(0xFF81D4FA)),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Multi-OEM Anti-Evasion Matrix',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                    letterSpacing: -0.2,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          const Text(
            'Different smartphone manufacturers customize Android Settings and Task Managers differently. '
            'FocusDNS includes tailored heuristic sandboxing for each major OEM ecosystem.',
            style: TextStyle(fontSize: 12, color: Color(0xFFAAAAAA), height: 1.35),
          ),
          const SizedBox(height: 14),

          // OEM Chip Grid
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _supportedOems.map((oem) {
              return Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: const Color(0xFF141416),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFF2E2E32)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.check_circle, size: 12, color: Color(0xFF4CAF50)),
                    const SizedBox(width: 6),
                    Text(
                      oem['name'] as String,
                      style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w500, color: Colors.white70),
                    ),
                  ],
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 16),

          // Intercepted vectors checklist
          const Text(
            'Active Resistance Vectors:',
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFFCCCCCC)),
          ),
          const SizedBox(height: 8),
          ..._evasionVectors.map((vec) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.shield, size: 13, color: Color(0xFF81D4FA)),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        vec,
                        style: const TextStyle(fontSize: 11.5, color: Color(0xFF999999), height: 1.3),
                      ),
                    ),
                  ],
                ),
              )),
          const SizedBox(height: 16),

          // Floating Overlay Status banner
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFF141416),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: _canDrawOverlays ? const Color(0xFF2E7D32) : const Color(0xFFF57F17),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  _canDrawOverlays ? Icons.layers : Icons.layers_clear,
                  color: _canDrawOverlays ? const Color(0xFF4CAF50) : const Color(0xFFFFB300),
                  size: 22,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _canDrawOverlays
                            ? 'System Alert Overlay Active'
                            : 'Overlay Permission Needed',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: _canDrawOverlays ? const Color(0xFF4CAF50) : const Color(0xFFFFB300),
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _canDrawOverlays
                            ? 'Fullscreen HUD renders smoothly during lock attempts.'
                            : 'Grant SYSTEM_ALERT_WINDOW for reliable lock presentation.',
                        style: const TextStyle(fontSize: 11, color: Color(0xFF888888)),
                      ),
                    ],
                  ),
                ),
                if (!_canDrawOverlays)
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFF57F17),
                      foregroundColor: Colors.black,
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                      textStyle: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                    ),
                    onPressed: _requestOverlayPermission,
                    child: const Text('Grant'),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
