import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../state_management/providers.dart';
import '../../theme/wabi_sabi_theme.dart';

class ProfileSetupView extends ConsumerStatefulWidget {
  const ProfileSetupView({super.key});

  @override
  ConsumerState<ProfileSetupView> createState() => _ProfileSetupViewState();
}

class _ProfileSetupViewState extends ConsumerState<ProfileSetupView> {
  final TextEditingController _nameController = TextEditingController();
  String _selectedPreset = 'balanced';
  String _selectedIcon = 'shield';
  String _selectedDeviceType = 'mobile';

  final List<Map<String, String>> _icons = [
    {'id': 'shield', 'label': '🛡️ Shield'},
    {'id': 'laptop', 'label': '💻 Laptop'},
    {'id': 'phone', 'label': '📱 Mobile'},
    {'id': 'home', 'label': '🏠 Home'},
    {'id': 'focus', 'label': '🎯 Focus'},
    {'id': 'lock', 'label': '🔒 Stealth'},
  ];

  final List<Map<String, dynamic>> _policies = [
    {
      'id': 'balanced',
      'title': 'Balanced Protection',
      'desc': 'Blocks ads, malware domains, and in-browser cryptomining. Zero website breakage.',
      'icon': Icons.tune_rounded,
    },
    {
      'id': 'strict',
      'title': 'Strict & SafeSearch',
      'desc': 'Enforces Google & Bing SafeSearch, blocks adult/malicious DGA domains.',
      'icon': Icons.lock_clock_rounded,
    },
    {
      'id': 'ultra',
      'title': 'Ultra-Stealth Shield',
      'desc': 'Hardens typo-squatting, disguised CNAME trackers, and unverified telemetry.',
      'icon': Icons.security_rounded,
    },
  ];

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _submitSetup() async {
    final rawName = _nameController.text.trim();
    if (rawName.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a profile name.')),
      );
      return;
    }
    final name = rawName;

    final res = await ref.read(authProvider.notifier).completeProfileSetup(
      profileName: name,
      preset: _selectedPreset,
      icon: _selectedIcon,
      deviceType: _selectedDeviceType,
    );

    if (mounted && res['success'] == true) {
      // Reload settings provider with newly provisioned profile
      await ref.read(settingsProvider.notifier).loadSettings();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('🎉 Welcome to FocusDNS! Profile "$name" is active.'),
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = WabiSabiPalette.of(context);
    final auth = ref.watch(authProvider);

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Step 3 Header
          Text(
            'Name Your DNS Profile',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: palette.ink,
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Your phone number is verified! Enter a custom name to identify this device\'s DNS filtering rules and cloud analytics.',
            style: TextStyle(fontSize: 13, height: 1.45, color: palette.mutedInk),
          ),

          const SizedBox(height: 24),

          // Profile Name Box (Requested by User)
          Text(
            'PROFILE NAME',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.bold,
              letterSpacing: 0.8,
              color: palette.mutedInk,
            ),
          ),
          const SizedBox(height: 8),

          Container(
            decoration: BoxDecoration(
              color: palette.surface,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: palette.border, width: 1.2),
            ),
            child: TextField(
              controller: _nameController,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: palette.ink,
              ),
              decoration: InputDecoration(
                prefixIcon: const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 14),
                  child: Icon(Icons.badge_outlined, size: 20),
                ),
                suffixIcon: _nameController.text.isNotEmpty
                    ? IconButton(
                        icon: Icon(Icons.clear, size: 16, color: palette.mutedInk),
                        onPressed: () => setState(() => _nameController.clear()),
                      )
                    : null,
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                border: InputBorder.none,
              ),
              onChanged: (_) => setState(() {}),
            ),
          ),

          const SizedBox(height: 24),

          // Icon / Badge Selector
          Text(
            'PROFILE ICON',
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 0.8, color: palette.mutedInk),
          ),
          const SizedBox(height: 8),

          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: _icons.map((ic) {
                final isSelected = (_selectedIcon == ic['id']);
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: InkWell(
                    onTap: () => setState(() => _selectedIcon = ic['id']!),
                    borderRadius: BorderRadius.circular(10),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: isSelected ? palette.ink : palette.surface,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: isSelected ? palette.ink : palette.border),
                      ),
                      child: Text(
                        ic['label']!,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                          color: isSelected ? palette.canvas : palette.ink,
                        ),
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),

          const SizedBox(height: 24),

          // Initial DNS Protection Policy Preset
          Text(
            'INITIAL FILTERING POLICY',
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 0.8, color: palette.mutedInk),
          ),
          const SizedBox(height: 8),

          Column(
            children: _policies.map((pol) {
              final isSelected = (_selectedPreset == pol['id']);
              return GestureDetector(
                onTap: () => setState(() => _selectedPreset = pol['id'] as String),
                child: Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: isSelected ? palette.ink.withOpacity(0.06) : palette.surface,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: isSelected ? palette.ink : palette.border,
                      width: isSelected ? 1.6 : 1.0,
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(pol['icon'] as IconData, size: 20, color: palette.ink),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              pol['title'] as String,
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                                color: palette.ink,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              pol['desc'] as String,
                              style: TextStyle(fontSize: 11, color: palette.mutedInk),
                            ),
                          ],
                        ),
                      ),
                      if (isSelected)
                        Icon(Icons.check_circle_rounded, size: 18, color: palette.ink),
                    ],
                  ),
                ),
              );
            }).toList(),
          ),

          if (auth.errorMessage != null) ...[
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: const Color(0xFFE05252).withOpacity(0.08),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFFE05252).withOpacity(0.3)),
              ),
              child: Text(
                auth.errorMessage!,
                style: const TextStyle(fontSize: 12, color: Color(0xFFD32F2F), fontWeight: FontWeight.w500),
              ),
            ),
          ],

          const SizedBox(height: 28),

          // Activate & Launch Button
          SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton(
              onPressed: auth.isLoading ? null : _submitSetup,
              style: ElevatedButton.styleFrom(
                backgroundColor: palette.ink,
                foregroundColor: palette.canvas,
                elevation: 0,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
              child: auth.isLoading
                  ? SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2.2, color: palette.canvas),
                    )
                  : const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          'Activate Profile & Launch FocusDNS',
                          style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                        ),
                        SizedBox(width: 8),
                        Icon(Icons.rocket_launch_rounded, size: 18),
                      ],
                    ),
            ),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}
