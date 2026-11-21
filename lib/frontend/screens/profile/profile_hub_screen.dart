import 'package:flutter/material.dart';
import '../../../engine/profile/user_profile_model.dart';
import '../../../engine/profile/cross_device_sync_coordinator.dart';
import '../../../engine/profile/accountability_partner_manager.dart';
import '../../../engine/analytics/analytics_persistence_store.dart';
import '../fleet/fleet_orchestration_master_screen.dart';
import '../fleet/browser_extension_pairing_screen.dart';
import '../analytics/longitudinal_analytics_master_screen.dart';
import 'accountability_partner_screen.dart';

/// User Profile Master Hub managing focus archetypes, lifetime sovereignty ranks,
/// security policies, and navigation across the cross-device ecosystem.
class ProfileHubScreen extends StatefulWidget {
  final UserProfileModel initialProfile;
  final CrossDeviceSyncCoordinator syncCoordinator;
  final AccountabilityPartnerManager partnerManager;
  final AnalyticsPersistenceStore analyticsStore;
  final void Function(UserProfileModel updated)? onProfileUpdated;

  const ProfileHubScreen({
    super.key,
    required this.initialProfile,
    required this.syncCoordinator,
    required this.partnerManager,
    required this.analyticsStore,
    this.onProfileUpdated,
  });

  @override
  State<ProfileHubScreen> createState() => _ProfileHubScreenState();
}

class _ProfileHubScreenState extends State<ProfileHubScreen> {
  late UserProfileModel _profile;

  @override
  void initState() {
    super.initState();
    _profile = widget.initialProfile;
  }

  void _updateProfile(UserProfileModel p) {
    setState(() => _profile = p);
    widget.onProfileUpdated?.call(p);
  }

  @override
  Widget build(BuildContext context) {
    final archetypeInfo = _profile.archetypeInfo;

    return Scaffold(
      backgroundColor: const Color(0xFF0E0E12),
      appBar: AppBar(
        backgroundColor: const Color(0xFF14141A),
        elevation: 0,
        title: const Text(
          'Profile & Sovereignty',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: Colors.white),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // 1. Hero Identity Card
          _buildHeroIdentityCard(),
          const SizedBox(height: 18),

          // 2. Lifetime Sovereignty Stats
          _buildLifetimeStatsGrid(),
          const SizedBox(height: 20),

          // 3. Focus Archetype Selector
          _buildArchetypeSelector(archetypeInfo),
          const SizedBox(height: 20),

          // 4. Ecosystem & Cross-Device Hub Links
          _buildEcosystemNavigationHub(context),
          const SizedBox(height: 20),

          // 5. Anti-Tamper Security Settings
          _buildSecurityPolicyCard(),
        ],
      ),
    );
  }

  Widget _buildHeroIdentityCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            const Color(0xFF181824),
            const Color(0xFF14141C),
          ],
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withOpacity(0.08)),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 32,
            backgroundColor: const Color(0xFF00E699).withOpacity(0.15),
            child: Text(
              _profile.archetypeInfo.icon,
              style: const TextStyle(fontSize: 32),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      _profile.displayName,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.3,
                      ),
                    ),
                    const SizedBox(width: 6),
                    const Text('🛡️', style: TextStyle(fontSize: 14)),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  _profile.sovereigntyRank,
                  style: const TextStyle(
                    color: Color(0xFF00E699),
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'User ID: ${_profile.userId}',
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.4),
                    fontSize: 10,
                    fontFamily: 'monospace',
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLifetimeStatsGrid() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF16161E),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(0.06)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'LIFETIME FOCUS SOVEREIGNTY',
            style: TextStyle(
              color: Colors.white54,
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.8,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              Expanded(child: _buildStatTile('Hours Saved', '${_profile.totalLifetimeHoursReclaimed}h', const Color(0xFF00E699))),
              Container(width: 1, height: 30, color: Colors.white.withOpacity(0.08)),
              Expanded(child: _buildStatTile('Traps Blocked', '${_profile.totalLifetimeTrapsSevered}', const Color(0xFFFF9F1C))),
              Container(width: 1, height: 30, color: Colors.white.withOpacity(0.08)),
              Expanded(child: _buildStatTile('Best Streak', '${_profile.bestLifetimeStreakDays}d', const Color(0xFF0095F6))),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStatTile(String label, String value, Color color) {
    return Column(
      children: [
        Text(
          value,
          style: TextStyle(color: color, fontSize: 18, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 10, fontWeight: FontWeight.w600),
        ),
      ],
    );
  }

  Widget _buildArchetypeSelector(FocusArchetypeInfo current) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFF16161E),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withOpacity(0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'FOCUS ARCHETYPE',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.8,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: const Color(0xFF00E699).withOpacity(0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '${current.recommendedDailyFocusHours}h Goal',
                  style: const TextStyle(color: Color(0xFF00E699), fontSize: 10, fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            current.subtitle,
            style: TextStyle(color: Colors.white.withOpacity(0.65), fontSize: 12),
          ),
          const SizedBox(height: 14),

          // Archetype Options Grid
          Row(
            children: FocusArchetype.values.map((archetype) {
              final isSelected = _profile.archetype == archetype;
              return Expanded(
                child: GestureDetector(
                  onTap: () {
                    _updateProfile(_profile.copyWith(archetype: archetype));
                  },
                  child: Container(
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    decoration: BoxDecoration(
                      color: isSelected ? const Color(0xFF00E699).withOpacity(0.15) : const Color(0xFF101015),
                      border: Border.all(
                        color: isSelected ? const Color(0xFF00E699) : Colors.white.withOpacity(0.06),
                      ),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      children: [
                        Text(
                          _getArchetypeIcon(archetype),
                          style: const TextStyle(fontSize: 22),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          _getArchetypeName(archetype),
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: isSelected ? Colors.white : Colors.white60,
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildEcosystemNavigationHub(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF16161E),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withOpacity(0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'CROSS-DEVICE ECOSYSTEM',
            style: TextStyle(
              color: Colors.white54,
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.8,
            ),
          ),
          const SizedBox(height: 8),

          _buildNavigationTile(
            icon: '📱💻',
            title: 'Device Fleet Console',
            subtitle: 'Manage phone, laptop, and desktop synchronization',
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => FleetOrchestrationMasterScreen(
                    coordinator: widget.syncCoordinator,
                  ),
                ),
              );
            },
          ),
          _buildNavigationTile(
            icon: '🌐',
            title: 'Browser Extension Pairing',
            subtitle: 'Chrome, Brave, Edge & Firefox Manifest V3 Extension',
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => BrowserExtensionPairingScreen(
                    userId: _profile.userId,
                  ),
                ),
              );
            },
          ),
          _buildNavigationTile(
            icon: '📈',
            title: 'Longitudinal Focus Analytics',
            subtitle: '7x24 heatmap, recovery curve, and streak momentum',
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => LongitudinalAnalyticsMasterScreen(
                    store: widget.analyticsStore,
                  ),
                ),
              );
            },
          ),
          _buildNavigationTile(
            icon: '👥',
            title: 'Accountability Partner Vault',
            subtitle: 'Manage guardian email, trust scores, and emergency review',
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => AccountabilityPartnerScreen(
                    manager: widget.partnerManager,
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildNavigationTile({
    required String icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: ListTile(
        contentPadding: EdgeInsets.zero,
        leading: Container(
          width: 38,
          height: 38,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.04),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text(icon, style: const TextStyle(fontSize: 18)),
        ),
        title: Text(
          title,
          style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w700),
        ),
        subtitle: Text(
          subtitle,
          style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 11),
        ),
        trailing: const Icon(Icons.arrow_forward_ios, size: 12, color: Colors.white38),
        onTap: onTap,
      ),
    );
  }

  Widget _buildSecurityPolicyCard() {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFF16161E),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withOpacity(0.08)),
      ),
      child: Material(
        color: Colors.transparent,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'ANTI-TAMPER SECURITY POLICIES',
              style: TextStyle(
                color: Colors.white54,
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.8,
              ),
            ),
            const SizedBox(height: 12),

            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Strict Anti-Uninstall Shield', style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600)),
              subtitle: const Text('Enforces Android Device Admin to prevent blocker deletion during active lock', style: TextStyle(color: Colors.white54, fontSize: 11)),
              value: _profile.strictAntiUninstallEnabled,
              activeColor: const Color(0xFF00E699),
              onChanged: (val) {
                _updateProfile(_profile.copyWith(strictAntiUninstallEnabled: val));
              },
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Biometric Authentication', style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600)),
              subtitle: const Text('Requires fingerprint or face unlock to access settings', style: TextStyle(color: Colors.white54, fontSize: 11)),
              value: _profile.biometricUnlockRequired,
              activeColor: const Color(0xFF00E699),
              onChanged: (val) {
                _updateProfile(_profile.copyWith(biometricUnlockRequired: val));
              },
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Mandatory Partner Signoff', style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600)),
              subtitle: const Text('Requires accountability partner approval for any early emergency release', style: TextStyle(color: Colors.white54, fontSize: 11)),
              value: _profile.emergencyPartnerRequired,
              activeColor: const Color(0xFF00E699),
              onChanged: (val) {
                _updateProfile(_profile.copyWith(emergencyPartnerRequired: val));
              },
            ),
          ],
        ),
      ),
    );
  }

  String _getArchetypeIcon(FocusArchetype archetype) {
    switch (archetype) {
      case FocusArchetype.studentScholar: return '🎓';
      case FocusArchetype.deepWorkEngineer: return '💻';
      case FocusArchetype.executiveSovereign: return '👔';
      case FocusArchetype.zenMonk: return '🧘';
    }
  }

  String _getArchetypeName(FocusArchetype archetype) {
    switch (archetype) {
      case FocusArchetype.studentScholar: return 'Student';
      case FocusArchetype.deepWorkEngineer: return 'Engineer';
      case FocusArchetype.executiveSovereign: return 'Executive';
      case FocusArchetype.zenMonk: return 'Zen Monk';
    }
  }
}
