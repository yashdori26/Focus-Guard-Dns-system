import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../backend/blocker_service.dart';
import '../../../backend/vpn_service.dart';
import '../../../models/app_models.dart';
import '../../../services/app_storage_service.dart';
import '../../../services/auth_storage_service.dart';
import '../../../state_management/providers.dart';
import '../../home_screen.dart';
import '../../theme/wabi_sabi_theme.dart';

class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> with WidgetsBindingObserver {
  int _currentStep = 0;
  final TextEditingController _nameController = TextEditingController(text: 'Personal Shield');

  // Step 2: Selected Categories and Apps
  final Set<String> _selectedCategories = {'adult', 'youtube', 'social', 'trackers'};

  // Step 3: Permission states
  bool _vpnPrepared = false;
  bool _accessibilityEnabled = false;
  bool _batteryExempt = false;
  bool _isLaunching = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadSavedOnboardingState();
    _checkInitialPermissions();
    _nameController.addListener(_saveProfileName);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _nameController.removeListener(_saveProfileName);
    _nameController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _checkInitialPermissions();
    }
  }

  Future<void> _loadSavedOnboardingState() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedStep = prefs.getInt('focus_onboarding_step');
      final savedName = prefs.getString('focus_onboarding_name');
      final savedCats = prefs.getStringList('focus_onboarding_cats');

      if (!mounted) return;
      setState(() {
        if (savedStep != null && savedStep >= 0 && savedStep <= 2) {
          _currentStep = savedStep;
        }
        if (savedName != null && savedName.isNotEmpty) {
          _nameController.text = savedName;
        }
        if (savedCats != null && savedCats.isNotEmpty) {
          _selectedCategories.clear();
          _selectedCategories.addAll(savedCats);
        }
      });
    } catch (_) {}
  }

  void _saveProfileName() {
    SharedPreferences.getInstance().then((prefs) {
      prefs.setString('focus_onboarding_name', _nameController.text);
    }).catchError((_) {});
  }

  void _saveStep(int step) {
    SharedPreferences.getInstance().then((prefs) {
      prefs.setInt('focus_onboarding_step', step);
    }).catchError((_) {});
  }

  void _saveCategories() {
    SharedPreferences.getInstance().then((prefs) {
      prefs.setStringList('focus_onboarding_cats', _selectedCategories.toList());
    }).catchError((_) {});
  }

  Future<void> _checkInitialPermissions() async {
    final vpn = await FocusDnsVpnManager.isRunning();
    final a11y = await FocusDnsBlockerManager.isAccessibilityServiceEnabled();
    final battery = await FocusDnsBlockerManager.isBatteryOptimizationIgnored();
    if (mounted) {
      setState(() {
        _vpnPrepared = vpn;
        _accessibilityEnabled = a11y;
        _batteryExempt = battery;
      });
    }
  }

  Future<void> _requestVpn() async {
    final ok = await FocusDnsVpnManager.prepare();
    if (mounted) setState(() => _vpnPrepared = ok);
  }

  Future<void> _requestAccessibility() async {
    await FocusDnsBlockerManager.openAccessibilitySettings();
    Future.delayed(const Duration(seconds: 2), _checkInitialPermissions);
  }

  Future<void> _requestBattery() async {
    await FocusDnsBlockerManager.requestIgnoreBatteryOptimizations();
    Future.delayed(const Duration(seconds: 1), _checkInitialPermissions);
  }

  Future<void> _completeOnboarding() async {
    setState(() => _isLaunching = true);

    final profileName = _nameController.text.trim().isNotEmpty
        ? _nameController.text.trim()
        : 'Personal Shield';

    // 1. Save profile name
    ref.read(settingsProvider.notifier).updateProfileName(profileName);
    await AuthStorageService.updateActiveProfile('local', profileName);

    // 2. Map selected categories to native blocker & rules
    final List<String> nativeCategories = [];
    if (_selectedCategories.contains('adult')) nativeCategories.add('porn');
    if (_selectedCategories.contains('social')) nativeCategories.add('social');
    if (_selectedCategories.contains('gambling')) nativeCategories.add('gambling');

    final bool blockYoutube = _selectedCategories.contains('youtube');
    final bool blockTrackers = _selectedCategories.contains('trackers');

    // Packages to block directly
    final List<String> packagesToBlock = [];
    if (blockYoutube) {
      packagesToBlock.add('com.google.android.youtube');
    }
    if (_selectedCategories.contains('social')) {
      packagesToBlock.addAll([
        'com.instagram.android',
        'com.zhiliaoapp.musically',
        'com.ss.android.ugc.trill',
        'com.facebook.katana',
        'com.twitter.android',
        'com.snapchat.android',
        'com.reddit.frontpage',
        'com.pinterest',
      ]);
    }
    if (_selectedCategories.contains('gambling')) {
      packagesToBlock.addAll([
        'com.winzo.gold',
        'com.mpl.androidapp',
        'com.rummycircle.android',
        'com.dream11.app',
      ]);
    }
    if (_selectedCategories.contains('adult')) {
      packagesToBlock.addAll([
        'org.torproject.torbrowser',
        'org.torproject.torbrowser_alpha',
      ]);
    }

    // Update native blocker and database rules
    await FocusDnsBlockerManager.setBlockedPackages(packagesToBlock, source: 'onboarding');
    await FocusDnsBlockerManager.setBlockedCategories(nativeCategories);
    await FocusDnsBlockerManager.setFeedFilters(
      instagramReels: _selectedCategories.contains('social'),
      youtubeShorts: blockYoutube,
    );
    await FocusDnsVpnManager.updateSecuritySettings(
      safesearch: _selectedCategories.contains('adult'),
      threatIntel: true,
      adblock: blockTrackers,
    );

    // Save app categories to storage
    final blockedItems = [
      if (_selectedCategories.contains('adult'))
        const BlockedItem(id: 'porn', name: 'Adult & NSFW', icon: '🔞', color: Colors.red),
      if (_selectedCategories.contains('youtube'))
        const BlockedItem(id: 'youtube', name: 'YouTube Shorts', icon: '🎬', color: Colors.deepOrange),
      if (_selectedCategories.contains('social'))
        const BlockedItem(id: 'social', name: 'Social Media Feeds', icon: '📱', color: Colors.purple),
      if (_selectedCategories.contains('gambling'))
        const BlockedItem(id: 'gambling', name: 'Gambling & Betting', icon: '🎰', color: Colors.amber),
    ];
    await AppStorageService.saveBlockedCategories(blockedItems);

    // 3. Mark protection on and start local VPN
    await FocusDnsBlockerManager.setProtectionEnabled(true);
    await ref.read(protectionProvider.notifier).set(true);
    try {
      ref.read(deepFocusProvider.notifier).syncWithBlocker();
    } catch (_) {}
    try {
      await ref.read(vpnProvider.notifier).start(profileId: 'local');
    } catch (_) {}

    // 4. Mark onboarding as completed in device preferences & clear scratch onboarding state
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('focus_onboarding_step');
    await prefs.remove('focus_onboarding_name');
    await prefs.remove('focus_onboarding_cats');
    await prefs.setBool('focus_onboarding_completed', true);

    if (mounted) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const FocusDNSHomeScreen()),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final themeMode = ref.watch(themeModeProvider);
    final palette = themeMode == ThemeMode.light
        ? WabiSabiPalette.light
        : WabiSabiPalette.dark;

    final progress = (_currentStep + 1) / 3.0;

    return Scaffold(
      backgroundColor: palette.canvas,
      body: SafeArea(
        child: Column(
          children: [
            // SLEEK TOP PROGRESS HEADER
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 28,
                            height: 28,
                            decoration: BoxDecoration(
                              color: palette.surface,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: palette.border, width: 1),
                            ),
                            child: Icon(Icons.shield_outlined, size: 16, color: palette.accent),
                          ),
                          const SizedBox(width: 10),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'FOCUSDNS · SOVEREIGN SETUP',
                                style: GoogleFonts.inter(
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 1.3,
                                  color: palette.mutedInk,
                                ),
                              ),
                              const SizedBox(height: 1),
                              Text(
                                _currentStep == 0
                                    ? 'Step 1 of 3: Shield Identity'
                                    : _currentStep == 1
                                        ? 'Step 2 of 3: Content Rules'
                                        : 'Step 3 of 3: Security & Trust',
                                style: GoogleFonts.inter(
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w600,
                                  color: palette.ink,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                      // Tactile step badge
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          color: palette.surface,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: palette.border),
                        ),
                        child: Text(
                          '${(_currentStep + 1)} / 3',
                          style: GoogleFonts.jetBrainsMono(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: palette.accent,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  // Smooth Animated Progress Bar
                  ClipRRect(
                    borderRadius: BorderRadius.circular(3),
                    child: SizedBox(
                      height: 4,
                      child: LinearProgressIndicator(
                        value: progress,
                        backgroundColor: palette.border,
                        valueColor: AlwaysStoppedAnimation<Color>(palette.accent),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Divider(height: 1, thickness: 1, color: palette.hairlineSoft),

            // STEP CONTENT BODY
            Expanded(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 280),
                switchInCurve: Curves.easeOutCubic,
                switchOutCurve: Curves.easeInCubic,
                child: KeyedSubtree(
                  key: ValueKey<int>(_currentStep),
                  child: SingleChildScrollView(
                    physics: const BouncingScrollPhysics(),
                    padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 20.0),
                    child: _buildCurrentStep(palette),
                  ),
                ),
              ),
            ),

            // BOTTOM NAVIGATION BAR
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 16.0),
              decoration: BoxDecoration(
                color: palette.surface,
                border: Border(top: BorderSide(color: palette.border, width: 1.0)),
              ),
              child: Row(
                children: [
                  if (_currentStep > 0) ...[
                    OutlinedButton(
                      onPressed: () {
                        setState(() {
                          _currentStep--;
                          _saveStep(_currentStep);
                        });
                      },
                      style: OutlinedButton.styleFrom(
                        foregroundColor: palette.ink,
                        side: BorderSide(color: palette.border, width: 1.2),
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      child: Text('← Back', style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600)),
                    ),
                    const SizedBox(width: 12),
                  ],
                  Expanded(
                    child: ElevatedButton(
                      onPressed: _isLaunching
                          ? null
                          : () {
                              if (_currentStep < 2) {
                                setState(() {
                                  _currentStep++;
                                  _saveStep(_currentStep);
                                });
                              } else {
                                _completeOnboarding();
                              }
                            },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: palette.accent,
                        foregroundColor: palette.canvas,
                        elevation: 0,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      child: _isLaunching
                          ? SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2.2, color: palette.canvas),
                            )
                          : Text(
                              _currentStep == 2 ? 'Activate Shield & Launch →' : 'Continue to Next Step →',
                              style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.bold, letterSpacing: -0.2),
                            ),
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

  Widget _buildCurrentStep(WabiSabiPalette palette) {
    switch (_currentStep) {
      case 0:
        return _buildStep1Profile(palette);
      case 1:
        return _buildStep2Categories(palette);
      case 2:
      default:
        return _buildStep3PermissionsAndTrust(palette);
    }
  }

  // --- STEP 1: NAME YOUR SHIELD PROFILE ---
  Widget _buildStep1Profile(WabiSabiPalette palette) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Name Your Shield',
          style: GoogleFonts.fraunces(
            fontSize: 29,
            fontWeight: FontWeight.w700,
            color: palette.ink,
            letterSpacing: -0.6,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Give your local filtering shield an identifiable identity on this hardware. All rules, logs, and telemetry are isolated to this device profile.',
          style: GoogleFonts.inter(
            fontSize: 13.5,
            color: palette.mutedInk,
            height: 1.5,
          ),
        ),
        const SizedBox(height: 28),

        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: palette.surface,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: palette.border, width: 1.2),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: palette.safeAccent,
                      boxShadow: [
                        BoxShadow(
                          color: palette.safeAccent.withOpacity(0.4),
                          blurRadius: 6,
                          spreadRadius: 1,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'ON-DEVICE PROFILE IDENTITY',
                    style: GoogleFonts.jetBrainsMono(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.9,
                      color: palette.mutedInk,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _nameController,
                style: GoogleFonts.inter(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: palette.ink,
                ),
                decoration: InputDecoration(
                  hintText: 'e.g. Deep Work, Personal Shield',
                  hintStyle: TextStyle(color: palette.mutedInk.withOpacity(0.5)),
                  filled: true,
                  fillColor: palette.canvas,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: palette.border),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: palette.border),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: palette.accent, width: 1.8),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Icon(Icons.lock_outline_rounded, size: 14, color: palette.mutedInk),
                  const SizedBox(width: 6),
                  Text(
                    'Stored locally in device SQLite. Zero cloud telemetries.',
                    style: GoogleFonts.inter(fontSize: 12, color: palette.mutedInk),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  // --- STEP 2: CHOOSE APPS & CATEGORIES TO BLOCK ---
  Widget _buildStep2Categories(WabiSabiPalette palette) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Choose What to Sever',
          style: GoogleFonts.fraunces(
            fontSize: 29,
            fontWeight: FontWeight.w700,
            color: palette.ink,
            letterSpacing: -0.6,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Select the vices and algorithmic dopamine traps you want blocked and sinkholed on this phone.',
          style: GoogleFonts.inter(
            fontSize: 13.5,
            color: palette.mutedInk,
            height: 1.5,
          ),
        ),
        const SizedBox(height: 20),

        _buildCategoryCard(
          id: 'adult',
          icon: '🔞',
          title: 'Adult Content & NSFW',
          subtitle: '45,000+ porn, erotic webcam, and adult domains + SafeSearch VIP.',
          palette: palette,
        ),
        const SizedBox(height: 10),

        _buildCategoryCard(
          id: 'youtube',
          icon: '🎬',
          title: 'YouTube Shorts & Algorithmic Feeds',
          subtitle: 'Instantly severs YouTube Shorts and doomscroll loops.',
          palette: palette,
        ),
        const SizedBox(height: 10),

        _buildCategoryCard(
          id: 'social',
          icon: '📱',
          title: 'Social Media (Reels & Feeds)',
          subtitle: 'Instagram, TikTok, Facebook, Twitter/X, and Snapchat umbrellas.',
          palette: palette,
        ),
        const SizedBox(height: 10),

        _buildCategoryCard(
          id: 'trackers',
          icon: '🛡️',
          title: 'Surveillance & Ad Trackers',
          subtitle: 'Kills telemetry, in-app ad SDKs, analytics, and surveillance networks.',
          palette: palette,
        ),
        const SizedBox(height: 10),

        _buildCategoryCard(
          id: 'gambling',
          icon: '🎰',
          title: 'Gambling & Betting',
          subtitle: 'Casinos, sports betting portals, and high-risk speculation sites.',
          palette: palette,
        ),
      ],
    );
  }

  Widget _buildCategoryCard({
    required String id,
    required String icon,
    required String title,
    required String subtitle,
    required WabiSabiPalette palette,
  }) {
    final selected = _selectedCategories.contains(id);

    return InkWell(
      onTap: () {
        setState(() {
          if (selected) {
            _selectedCategories.remove(id);
          } else {
            _selectedCategories.add(id);
          }
        });
        _saveCategories();
      },
      borderRadius: BorderRadius.circular(16),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.all(15),
        decoration: BoxDecoration(
          color: selected ? palette.surface : palette.canvas,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: selected ? palette.accent : palette.border,
            width: selected ? 1.6 : 1.0,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: palette.canvas,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: palette.border, width: 1),
              ),
              alignment: Alignment.center,
              child: Text(icon, style: const TextStyle(fontSize: 22)),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: GoogleFonts.inter(
                      fontSize: 14,
                      fontWeight: selected ? FontWeight.bold : FontWeight.w600,
                      color: palette.ink,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    subtitle,
                    style: GoogleFonts.inter(fontSize: 11.5, color: palette.mutedInk, height: 1.3),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              width: 24,
              height: 24,
              decoration: BoxDecoration(
                color: selected ? palette.accent : Colors.transparent,
                shape: BoxShape.circle,
                border: Border.all(
                  color: selected ? palette.accent : palette.mutedInk.withOpacity(0.4),
                  width: 1.6,
                ),
              ),
              child: selected
                  ? Icon(Icons.check_rounded, size: 15, color: palette.canvas)
                  : null,
            ),
          ],
        ),
      ),
    );
  }

  // --- STEP 3: PERMISSIONS & 100% LOCAL DATABASE TRUST ASSURANCE ---
  Widget _buildStep3PermissionsAndTrust(WabiSabiPalette palette) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Local Security & Trust',
          style: GoogleFonts.fraunces(
            fontSize: 29,
            fontWeight: FontWeight.w700,
            color: palette.ink,
            letterSpacing: -0.6,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'FocusDNS operates 100% on-device. Review permissions and local database assurance below.',
          style: GoogleFonts.inter(
            fontSize: 13.5,
            color: palette.mutedInk,
            height: 1.5,
          ),
        ),
        const SizedBox(height: 18),

        // 100% LOCAL DATABASE TRUST GUARANTEE CARD
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: palette.safeAccent.withOpacity(0.08),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: palette.safeAccent.withOpacity(0.35), width: 1.2),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 26,
                    height: 26,
                    decoration: BoxDecoration(
                      color: palette.safeAccent.withOpacity(0.15),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(Icons.verified_user_rounded, color: palette.safeAccent, size: 17),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    '100% LOCAL SQLITE ASSURANCE',
                    style: GoogleFonts.jetBrainsMono(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.9,
                      color: palette.safeAccent,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                'Every query log, telemetry record, and blocklist is saved strictly in your phone’s encrypted local SQLite database. No external servers are reached, no personal data is collected, and zero tracking occurs.',
                style: GoogleFonts.inter(
                  fontSize: 12.5,
                  color: palette.ink,
                  height: 1.45,
                ),
              ),
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: palette.canvas,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: palette.border, width: 0.8),
                ),
                child: Text(
                  'Loopback Virtual Bind: 10.254.1.2 (IPv4) • fd00::2 (IPv6)',
                  style: GoogleFonts.jetBrainsMono(
                    fontSize: 10.5,
                    color: palette.mutedInk,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),

        // PERMISSION 1: VPN SETUP
        _buildPermissionTile(
          icon: Icons.vpn_lock_rounded,
          title: 'Local DNS VPN Tunnel',
          subtitle: 'Required to intercept DNS queries and sinkhole ads/traps locally.',
          granted: _vpnPrepared,
          actionLabel: _vpnPrepared ? 'GRANTED ✓' : 'AUTHORIZE',
          onTap: _requestVpn,
          palette: palette,
        ),
        const SizedBox(height: 10),

        // PERMISSION 2: ACCESSIBILITY SERVICE
        _buildPermissionTile(
          icon: Icons.accessibility_new_rounded,
          title: 'Doomscroll Accessibility',
          subtitle: 'Enables auto-back navigation on YouTube Shorts & Instagram Reels.',
          granted: _accessibilityEnabled,
          actionLabel: _accessibilityEnabled ? 'ACTIVE ✓' : 'ENABLE',
          onTap: _requestAccessibility,
          palette: palette,
        ),
        const SizedBox(height: 10),

        // PERMISSION 3: DOZE BATTERY OPTIMIZATION
        _buildPermissionTile(
          icon: Icons.battery_charging_full_rounded,
          title: 'Doze Battery Immunity',
          subtitle: 'Prevents Android from killing the filter in deep sleep (<1.2%/day).',
          granted: _batteryExempt,
          actionLabel: _batteryExempt ? 'EXEMPT ✓' : 'ALLOW',
          onTap: _requestBattery,
          palette: palette,
        ),
      ],
    );
  }

  Widget _buildPermissionTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required bool granted,
    required String actionLabel,
    required VoidCallback onTap,
    required WabiSabiPalette palette,
  }) {
    return Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: granted ? palette.safeAccent.withOpacity(0.4) : palette.border,
          width: 1.1,
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(9),
            decoration: BoxDecoration(
              color: granted
                  ? palette.safeAccent.withOpacity(0.12)
                  : palette.canvas,
              shape: BoxShape.circle,
              border: Border.all(color: granted ? palette.safeAccent.withOpacity(0.3) : palette.border, width: 0.8),
            ),
            child: Icon(
              icon,
              size: 20,
              color: granted ? palette.safeAccent : palette.mutedInk,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: GoogleFonts.inter(
                    fontSize: 13.5,
                    fontWeight: FontWeight.bold,
                    color: palette.ink,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: GoogleFonts.inter(fontSize: 11, color: palette.mutedInk, height: 1.3),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          InkWell(
            onTap: granted ? null : onTap,
            borderRadius: BorderRadius.circular(9),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
              decoration: BoxDecoration(
                color: granted
                    ? palette.safeAccent.withOpacity(0.12)
                    : palette.accent,
                borderRadius: BorderRadius.circular(9),
              ),
              child: Text(
                actionLabel,
                style: GoogleFonts.inter(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.4,
                  color: granted ? palette.safeAccent : palette.canvas,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
