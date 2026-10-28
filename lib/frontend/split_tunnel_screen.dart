import 'package:flutter/material.dart';
import '../backend/mdm_service.dart';

/// Fullscreen UI for managing per-app split tunneling routing.
class SplitTunnelScreen extends StatefulWidget {
  const SplitTunnelScreen({super.key});

  @override
  State<SplitTunnelScreen> createState() => _SplitTunnelScreenState();
}

class _SplitTunnelScreenState extends State<SplitTunnelScreen> {
  List<SplitTunnelAppItem> _allApps = [];
  List<SplitTunnelAppItem> _filteredApps = [];
  final Set<String> _selectedPackages = {};
  String _mode = 'disallow_list';
  bool _isLoading = true;
  String _searchQuery = '';
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadApps();
  }

  Future<void> _loadApps() async {
    setState(() => _isLoading = true);
    final apps = await FocusMdmManager.getSplitTunnelApps();
    final telemetry = await FocusMdmManager.getSplitTunnelApps();

    final selected = apps.where((a) => a.isSelected).map((a) => a.packageName).toSet();

    if (mounted) {
      setState(() {
        _allApps = apps;
        _selectedPackages.clear();
        _selectedPackages.addAll(selected);
        _applySearch();
        _isLoading = false;
      });
    }
  }

  void _applySearch() {
    if (_searchQuery.trim().isEmpty) {
      _filteredApps = List.from(_allApps);
    } else {
      final q = _searchQuery.toLowerCase();
      _filteredApps = _allApps.where((app) {
        return app.appName.toLowerCase().contains(q) ||
            app.packageName.toLowerCase().contains(q);
      }).toList();
    }
  }

  Future<void> _saveChanges() async {
    setState(() => _isLoading = true);
    await FocusMdmManager.setSplitTunnelPackages(_selectedPackages.toList());
    await FocusMdmManager.setSplitTunnelMode(_mode);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: Color(0xFF2C2C2E),
          content: Text(
            'Split-tunneling routing configuration applied successfully.',
            style: TextStyle(color: Colors.white),
          ),
        ),
      );
      Navigator.of(context).pop();
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF121214),
      appBar: AppBar(
        backgroundColor: const Color(0xFF121214),
        elevation: 0,
        title: const Text(
          'Split Tunneling',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w600,
            color: Colors.white,
          ),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.of(context).pop(),
        ),
        actions: [
          TextButton(
            onPressed: _saveChanges,
            child: const Text(
              'Save',
              style: TextStyle(
                color: Color(0xFF4CAF50),
                fontWeight: FontWeight.bold,
                fontSize: 15,
              ),
            ),
          ),
        ],
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(color: Colors.white54, strokeWidth: 2),
            )
          : Column(
              children: [
                // Mode Explainer Header
                Container(
                  margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1E1E20),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: const Color(0xFF2C2C2E)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.info_outline, size: 18, color: Color(0xFF64B5F6)),
                          const SizedBox(width: 8),
                          const Text(
                            'Exempt Applications from VPN',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      const Text(
                        'Selected applications will bypass FocusDNS and connect directly to the internet. Recommended for banking, Google Pay, and corporate VPNs.',
                        style: TextStyle(fontSize: 12, color: Color(0xFF9E9E9E), height: 1.3),
                      ),
                    ],
                  ),
                ),
                // Search Field
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: TextField(
                    controller: _searchController,
                    style: const TextStyle(color: Colors.white, fontSize: 14),
                    decoration: InputDecoration(
                      hintText: 'Search installed apps...',
                      hintStyle: const TextStyle(color: Color(0xFF666666)),
                      prefixIcon: const Icon(Icons.search, color: Color(0xFF888888)),
                      filled: true,
                      fillColor: const Color(0xFF1E1E20),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(color: Color(0xFF2C2C2E)),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(color: Color(0xFF2C2C2E)),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(color: Color(0xFF4CAF50)),
                      ),
                    ),
                    onChanged: (val) {
                      setState(() {
                        _searchQuery = val;
                        _applySearch();
                      });
                    },
                  ),
                ),
                // App List
                Expanded(
                  child: ListView.separated(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    itemCount: _filteredApps.length,
                    separatorBuilder: (_, __) => const Divider(color: Color(0xFF222224), height: 1),
                    itemBuilder: (context, index) {
                      final app = _filteredApps[index];
                      final isSelected = _selectedPackages.contains(app.packageName);

                      return ListTile(
                        contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        leading: CircleAvatar(
                          backgroundColor: const Color(0xFF2A2A2E),
                          child: Text(
                            app.appName.isNotEmpty ? app.appName[0].toUpperCase() : 'A',
                            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                          ),
                        ),
                        title: Text(
                          app.appName,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        subtitle: Text(
                          app.packageName,
                          style: const TextStyle(color: Color(0xFF777777), fontSize: 11),
                        ),
                        trailing: Checkbox(
                          value: isSelected,
                          activeColor: const Color(0xFF4CAF50),
                          checkColor: Colors.black,
                          side: const BorderSide(color: Color(0xFF555555)),
                          onChanged: (val) {
                            setState(() {
                              if (val == true) {
                                _selectedPackages.add(app.packageName);
                              } else {
                                _selectedPackages.remove(app.packageName);
                              }
                            });
                          },
                        ),
                        onTap: () {
                          setState(() {
                            if (isSelected) {
                              _selectedPackages.remove(app.packageName);
                            } else {
                              _selectedPackages.add(app.packageName);
                            }
                          });
                        },
                      );
                    },
                  ),
                ),
              ],
            ),
    );
  }
}
