import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/server_config.dart';
import '../state_management/providers.dart';
import 'profile_settings_sheet.dart';
import 'theme/wabi_sabi_theme.dart';

/// Modal bottom sheet allowing 1-tap switching between DNS profiles,
/// adding new profiles, and opening profile settings.
class ProfileSwitcherSheet extends ConsumerStatefulWidget {
  const ProfileSwitcherSheet({super.key});

  @override
  ConsumerState<ProfileSwitcherSheet> createState() => _ProfileSwitcherSheetState();
}

class _ProfileSwitcherSheetState extends ConsumerState<ProfileSwitcherSheet> {
  List<Map<String, dynamic>> _profiles = [];
  bool _isLoading = true;
  bool _isCreating = false;
  final TextEditingController _newProfileController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _fetchProfiles();
  }

  @override
  void dispose() {
    _newProfileController.dispose();
    super.dispose();
  }

  Future<void> _fetchProfiles() async {
    setState(() => _isLoading = true);
    final client = ref.read(apiClientProvider);
    final list = await client.getProfiles();
    if (mounted) {
      setState(() {
        _profiles = list;
        _isLoading = false;
      });
    }
  }

  Future<void> _switchToProfile(String profileId, String profileName) async {
    final client = ref.read(apiClientProvider);
    client.updateConfig(newProfileId: profileId);

    // Save to device persistence
    final config = await ServerConfig.load();
    final updated = config.copyWith(activeProfileId: profileId);
    await updated.save();

    // Update setup provider & reload settings
    ref.read(setupProvider.notifier).updateServerHost(null, profileId);
    await ref.read(settingsProvider.notifier).loadSettings();

    // If VPN is active, update running tunnel
    final vpnState = ref.read(vpnProvider);
    if (vpnState.isRunning) {
      await ref.read(vpnProvider.notifier).start(profileId: profileId);
    }

    if (mounted) {
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Switched to $profileName ($profileId)'),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  Future<void> _createNewProfile() async {
    final name = _newProfileController.text.trim();
    if (name.isEmpty) return;

    setState(() => _isCreating = true);
    final client = ref.read(apiClientProvider);
    final created = await client.createProfile(name);

    if (mounted) {
      setState(() => _isCreating = false);
      if (created != null && created['profile_id'] != null) {
        final pid = created['profile_id'].toString();
        _newProfileController.clear();
        await _switchToProfile(pid, name);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to create profile. Check connection.')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = WabiSabiPalette.of(context);
    final activeProfileId = ref.watch(setupProvider).profileId;
    final activeProfileName = ref.watch(settingsProvider).profileName;

    return Container(
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        border: Border(top: BorderSide(color: palette.border)),
      ),
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Drag handle
            Center(
              child: Container(
                width: 36,
                height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: palette.border,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),

            // Header Row
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'DNS Profiles',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: palette.ink,
                        letterSpacing: -0.3,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Active: $activeProfileName ($activeProfileId)',
                      style: TextStyle(fontSize: 12, color: palette.mutedInk),
                    ),
                  ],
                ),
                IconButton(
                  icon: Icon(Icons.close, color: palette.mutedInk, size: 20),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Profiles List
            if (_isLoading)
              Center(
                child: Padding(
                  padding: const EdgeInsets.all(24.0),
                  child: SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(strokeWidth: 2, color: palette.ink),
                  ),
                ),
              )
            else if (_profiles.isEmpty)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: palette.canvas,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: palette.border),
                ),
                child: Text(
                  'Current Profile: $activeProfileName\nID: $activeProfileId',
                  style: TextStyle(fontSize: 13, color: palette.ink),
                ),
              )
            else
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 220),
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: _profiles.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final p = _profiles[index];
                    final pid = p['profile_id']?.toString() ?? '';
                    final name = p['name']?.toString() ?? 'Profile $pid';
                    final isCurrent = (pid == activeProfileId);

                    return GestureDetector(
                      onTap: () => _switchToProfile(pid, name),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                        decoration: BoxDecoration(
                          color: isCurrent ? palette.ink.withOpacity(0.08) : palette.canvas,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: isCurrent ? palette.ink : palette.border,
                            width: isCurrent ? 1.5 : 1,
                          ),
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 8,
                              height: 8,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: isCurrent ? palette.ink : palette.mutedInk.withOpacity(0.4),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    name,
                                    style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: isCurrent ? FontWeight.bold : FontWeight.w500,
                                      color: palette.ink,
                                    ),
                                  ),
                                  Text(
                                    'ID: $pid${p['connected_devices'] != null ? ' • ${p['connected_devices']} devices' : ''}',
                                    style: TextStyle(fontSize: 11, color: palette.mutedInk),
                                  ),
                                ],
                              ),
                            ),
                            if (isCurrent)
                              Icon(Icons.check_circle_rounded, size: 18, color: palette.ink),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),

            const SizedBox(height: 16),

            // Add Profile Input Row
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _newProfileController,
                    style: TextStyle(fontSize: 13, color: palette.ink),
                    decoration: InputDecoration(
                      hintText: 'New profile name...',
                      hintStyle: TextStyle(fontSize: 13, color: palette.mutedInk),
                      filled: true,
                      fillColor: palette.canvas,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide(color: palette.border),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide(color: palette.border),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide(color: palette.ink),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: _isCreating ? null : _createNewProfile,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: palette.ink,
                    foregroundColor: palette.canvas,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    elevation: 0,
                  ),
                  child: _isCreating
                      ? SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2, color: palette.canvas),
                        )
                      : const Text('Add', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                ),
              ],
            ),

            const SizedBox(height: 16),

            // Open Full Profile Settings Tab
            OutlinedButton(
              onPressed: () {
                Navigator.pop(context);
                showModalBottomSheet(
                  context: context,
                  isScrollControlled: true,
                  backgroundColor: Colors.transparent,
                  builder: (_) => const AllProfileSettingsSheet(),
                );
              },
              style: OutlinedButton.styleFrom(
                foregroundColor: palette.ink,
                side: BorderSide(color: palette.border),
                minimumSize: const Size(double.infinity, 44),
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.tune_rounded, size: 16),
                  SizedBox(width: 8),
                  Text('Detailed Profile Settings & Rules', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
