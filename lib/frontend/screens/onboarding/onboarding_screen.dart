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

/// Clean, Minimal, and Sovereign Onboarding Experience.
/// Guides the user through:
///   Step 1: Shield Identity (Profile Name)
///   Step 2: Content Rules (Categories to sever)
///   Step 3: Local Security & Trust (Permissions & Local SQLite Assurance)
class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> with WidgetsBindingObserver {
  int _currentStep = 0;
  final TextEditingController _nameController = TextEditingController();

  // Step 2: Selected Categories and Apps
  final Set<String> _selectedCategories = {'adult', 'social', 'trackers'};

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
      final authProfileName = await AuthStorageService.getActiveProfileName();

      final savedVpn = prefs.getBool('focus_perm_vpn') ?? false;
      final savedA11y = prefs.getBool('focus_perm_a11y') ?? false;
      final savedBattery = prefs.getBool('focus_perm_battery') ?? false;

      String? dbVpnStr;
      String? dbA11yStr;
      String? dbBatteryStr;
      try {
        dbVpnStr = await FocusDnsBlockerManager.getKv('focus_perm_vpn');
        dbA11yStr = await FocusDnsBlockerManager.getKv('focus_perm_a11y');
        dbBatteryStr = await FocusDnsBlockerManager.getKv('focus_perm_battery');
      } catch (_) {}

      final dbVpn = dbVpnStr == '1';
      final dbA11y = dbA11yStr == '1';
      final dbBattery = dbBatteryStr == '1';

      if (!mounted) return;
      setState(() {
        if (savedStep != null && savedStep >= 0 && savedStep <= 2) {
          _currentStep = savedStep;
        }
        if (savedName != null && savedName.isNotEmpty) {
          _nameController.text = savedName;
        } else if (authProfileName.isNotEmpty && authProfileName != 'Personal Shield') {
          _nameController.text = authProfileName;
        }
        if (savedCats != null && savedCats.isNotEmpty) {
          _selectedCategories.clear();
          _selectedCategories.addAll(savedCats);
        }
        if (savedVpn || dbVpn) _vpnPrepared = true;
        if (savedA11y || dbA11y) _accessibilityEnabled = true;
        if (savedBattery || dbBattery) _batteryExempt = true;
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
    final vpn = await FocusDnsVpnManager.isPrepared() || await FocusDnsVpnManager.isRunning();
    final a11y = await FocusDnsBlockerManager.isAccessibilityServiceEnabled();
    final battery = await FocusDnsBlockerManager.isBatteryOptimizationIgnored();
    
    final prefs = await SharedPreferences.getInstance();
    final savedVpn = prefs.getBool('focus_perm_vpn') ?? false;
    final savedA11y = prefs.getBool('focus_perm_a11y') ?? false;
    final savedBattery = prefs.getBool('focus_perm_battery') ?? false;

    String? dbVpnStr;
    String? dbA11yStr;
    String? dbBatteryStr;
    try {
      dbVpnStr = await FocusDnsBlockerManager.getKv('focus_perm_vpn');
      dbA11yStr = await FocusDnsBlockerManager.getKv('focus_perm_a11y');
      dbBatteryStr = await FocusDnsBlockerManager.getKv('focus_perm_battery');
    } catch (_) {}

    final dbVpn = dbVpnStr == '1';
    final dbA11y = dbA11yStr == '1';
    final dbBattery = dbBatteryStr == '1';

    final finalVpn = vpn || savedVpn || dbVpn || _vpnPrepared;
    final finalA11y = a11y || savedA11y || dbA11y || _accessibilityEnabled;
    final finalBattery = battery || savedBattery || dbBattery || _batteryExempt;

    if (finalVpn) {
      await prefs.setBool('focus_perm_vpn', true);
      FocusDnsBlockerManager.putKv('focus_perm_vpn', '1').catchError((_) => false);
    }
    if (finalA11y) {
      await prefs.setBool('focus_perm_a11y', true);
      FocusDnsBlockerManager.putKv('focus_perm_a11y', '1').catchError((_) => false);
    }
    if (finalBattery) {
      await prefs.setBool('focus_perm_battery', true);
      FocusDnsBlockerManager.putKv('focus_perm_battery', '1').catchError((_) => false);
    }

    if (mounted) {
      setState(() {
        _vpnPrepared = finalVpn;
        _accessibilityEnabled = finalA11y;
        _batteryExempt = finalBattery;
      });
    }
  }

  Future<void> _requestVpn() async {
    final success = await FocusDnsVpnManager.prepare();
    final isReady = success || await FocusDnsVpnManager.isPrepared();
    if (isReady) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('focus_perm_vpn', true);
      await FocusDnsBlockerManager.putKv('focus_perm_vpn', '1');
      if (mounted) setState(() => _vpnPrepared = true);
    }
    await _checkInitialPermissions();
  }

  Future<void> _requestAccessibility() async {
    await FocusDnsBlockerManager.openAccessibilitySettings();
    Future.delayed(const Duration(milliseconds: 500), _checkInitialPermissions);
    Future.delayed(const Duration(seconds: 1), _checkInitialPermissions);
    Future.delayed(const Duration(seconds: 2), _checkInitialPermissions);
  }

  Future<void> _requestBattery() async {
    await FocusDnsBlockerManager.requestIgnoreBatteryOptimizations();
    Future.delayed(const Duration(milliseconds: 500), _checkInitialPermissions);
    Future.delayed(const Duration(seconds: 1), _checkInitialPermissions);
    Future.delayed(const Duration(seconds: 2), _checkInitialPermissions);
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

    final bool blockTrackers = _selectedCategories.contains('trackers');

    // Packages to block directly
    final List<String> packagesToBlock = [];
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
      youtubeShorts: false,
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

    // Also persist completion into native SQLite LocalDb so it never resets
    try {
      await FocusDnsBlockerManager.putKv('focus_onboarding_completed', '1');
      await FocusDnsBlockerManager.putKv('focus_dns_auth_profile_name', profileName);
    } catch (_) {}

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
            // Minimal Header with Hairline Progress
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Expanded(
                        child: Row(
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
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'FOCUSDNS · SETUP',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
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
                                        ? 'Step 1: Shield Identity'
                                        : _currentStep == 1
                                            ? 'Step 2: Content Rules'
                                            : 'Step 3: Security & Trust',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: GoogleFonts.inter(
                                      fontSize: 12.5,
                                      fontWeight: FontWeight.w600,
                                      color: palette.ink,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: palette.surface,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: palette.border),
                        ),
                        child: Text(
                          '${_currentStep + 1} / 3',
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
                  ClipRRect(
                    borderRadius: BorderRadius.circular(2),
                    child: SizedBox(
                      height: 3,
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

            // Step Content Body
            Expanded(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 260),
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

            // Minimalist Bottom Action Bar
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 14.0),
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
                        side: BorderSide(color: palette.border, width: 1.1),
                        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 13),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
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
                        padding: const EdgeInsets.symmetric(vertical: 13),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      child: _isLaunching
                          ? SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2.0, color: palette.canvas),
                            )
                          : Text(
                              _currentStep == 2 ? 'Activate Shield & Launch →' : 'Continue →',
                              style: GoogleFonts.inter(fontSize: 13.5, fontWeight: FontWeight.bold, letterSpacing: -0.1),
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

  // --- STEP 1: SHIELD IDENTITY ---
  Widget _buildStep1Profile(WabiSabiPalette palette) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Name Your Shield',
          style: GoogleFonts.fraunces(
            fontSize: 28,
            fontWeight: FontWeight.w700,
            color: palette.ink,
            letterSpacing: -0.5,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'Name this device configuration. All rules, logs, and telemetry are isolated on-device.',
          style: GoogleFonts.inter(
            fontSize: 13,
            color: palette.mutedInk,
            height: 1.45,
          ),
        ),
        const SizedBox(height: 24),

        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: palette.surface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: palette.border, width: 1.1),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: palette.safeAccent,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'LOCAL PROFILE IDENTITY',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.jetBrainsMono(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.8,
                        color: palette.mutedInk,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              TextField(
                controller: _nameController,
                style: GoogleFonts.inter(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: palette.ink,
                ),
                decoration: InputDecoration(
                  hintText: 'e.g. Personal Shield, Deep Work',
                  hintStyle: TextStyle(color: palette.mutedInk.withOpacity(0.4)),
                  filled: true,
                  fillColor: palette.canvas,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide(color: palette.border),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide(color: palette.border),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide(color: palette.accent, width: 1.6),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Icon(Icons.lock_outline_rounded, size: 13, color: palette.mutedInk),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'Saved locally in SQLite database. Zero external servers.',
                      style: GoogleFonts.inter(fontSize: 11.5, color: palette.mutedInk),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  // --- STEP 2: CONTENT RULES ---
  Widget _buildStep2Categories(WabiSabiPalette palette) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Choose What to Sever',
          style: GoogleFonts.fraunces(
            fontSize: 28,
            fontWeight: FontWeight.w700,
            color: palette.ink,
            letterSpacing: -0.5,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'Select the categories and dopamine sinks you want sinkholed on this device.',
          style: GoogleFonts.inter(
            fontSize: 13,
            color: palette.mutedInk,
            height: 1.45,
          ),
        ),
        const SizedBox(height: 20),

        _buildCategoryCard(
          id: 'adult',
          icon: '🔞',
          title: 'Adult Content & NSFW',
          subtitle: '45,000+ adult domains, explicit webcams & SafeSearch enforcement.',
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
          subtitle: 'In-app ad SDKs, analytics, and surveillance networks.',
          palette: palette,
        ),
        const SizedBox(height: 10),

        _buildCategoryCard(
          id: 'gambling',
          icon: '🎰',
          title: 'Gambling & Betting',
          subtitle: 'Casinos, sports betting portals, and speculative wager sites.',
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
      borderRadius: BorderRadius.circular(14),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
        decoration: BoxDecoration(
          color: selected ? palette.surface : palette.canvas,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected ? palette.accent : palette.border,
            width: selected ? 1.5 : 1.0,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: palette.canvas,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: palette.border, width: 1),
              ),
              alignment: Alignment.center,
              child: Text(icon, style: const TextStyle(fontSize: 18)),
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
                      fontWeight: selected ? FontWeight.bold : FontWeight.w600,
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
            const SizedBox(width: 8),
            AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              width: 22,
              height: 22,
              decoration: BoxDecoration(
                color: selected ? palette.accent : Colors.transparent,
                shape: BoxShape.circle,
                border: Border.all(
                  color: selected ? palette.accent : palette.mutedInk.withOpacity(0.35),
                  width: 1.5,
                ),
              ),
              child: selected
                  ? Icon(Icons.check_rounded, size: 14, color: palette.canvas)
                  : null,
            ),
          ],
        ),
      ),
    );
  }

  // --- STEP 3: SECURITY & LOCAL TRUST ---
  Widget _buildStep3PermissionsAndTrust(WabiSabiPalette palette) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Local Security & Trust',
          style: GoogleFonts.fraunces(
            fontSize: 28,
            fontWeight: FontWeight.w700,
            color: palette.ink,
            letterSpacing: -0.5,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'FocusDNS operates 100% on-device. Review permissions and local database assurance.',
          style: GoogleFonts.inter(
            fontSize: 13,
            color: palette.mutedInk,
            height: 1.45,
          ),
        ),
        const SizedBox(height: 18),

        // 100% LOCAL DATABASE TRUST GUARANTEE CARD
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: palette.safeAccent.withOpacity(0.06),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: palette.safeAccent.withOpacity(0.3), width: 1.1),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 24,
                    height: 24,
                    decoration: BoxDecoration(
                      color: palette.safeAccent.withOpacity(0.15),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(Icons.verified_user_rounded, color: palette.safeAccent, size: 15),
                  ),
                  const SizedBox(width: 9),
                  Text(
                    '100% LOCAL SQLITE ASSURANCE',
                    style: GoogleFonts.jetBrainsMono(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.8,
                      color: palette.safeAccent,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                'Every query log, telemetry record, and blocklist is saved strictly in your phone’s local SQLite database. No external servers are reached, and zero personal data is transmitted.',
                style: GoogleFonts.inter(
                  fontSize: 12,
                  color: palette.ink,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                decoration: BoxDecoration(
                  color: palette.canvas,
                  borderRadius: BorderRadius.circular(7),
                  border: Border.all(color: palette.border, width: 0.8),
                ),
                child: Text(
                  'Loopback Virtual Bind: 10.254.1.2 (IPv4) • fd00::2 (IPv6)',
                  style: GoogleFonts.jetBrainsMono(
                    fontSize: 10,
                    color: palette.mutedInk,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // PERMISSION 1: VPN SETUP
        _buildPermissionTile(
          icon: Icons.vpn_lock_rounded,
          title: 'Local DNS VPN Tunnel',
          subtitle: 'Required to intercept DNS queries and sinkhole ads & distractions locally.',
          granted: _vpnPrepared,
          actionLabel: _vpnPrepared ? 'ACTIVE ✓' : 'AUTHORIZE',
          onTap: _requestVpn,
          palette: palette,
        ),
        const SizedBox(height: 10),

        // PERMISSION 2: ACCESSIBILITY SERVICE
        _buildPermissionTile(
          icon: Icons.accessibility_new_rounded,
          title: 'Doomscroll Accessibility',
          subtitle: 'Enables automatic closure and enforcement on restricted applications.',
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
          subtitle: 'Prevents Android from stopping background protection during deep sleep.',
          granted: _batteryExempt,
          actionLabel: _batteryExempt ? 'ACTIVE ✓' : 'ALLOW',
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
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: granted ? palette.safeAccent.withOpacity(0.35) : palette.border,
          width: 1.0,
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: granted
                  ? palette.safeAccent.withOpacity(0.12)
                  : palette.canvas,
              shape: BoxShape.circle,
              border: Border.all(color: granted ? palette.safeAccent.withOpacity(0.25) : palette.border, width: 0.8),
            ),
            child: Icon(
              icon,
              size: 18,
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
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: palette.ink,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: GoogleFonts.inter(fontSize: 10.5, color: palette.mutedInk, height: 1.3),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          InkWell(
            onTap: granted ? null : onTap,
            borderRadius: BorderRadius.circular(8),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
              decoration: BoxDecoration(
                color: granted
                    ? palette.safeAccent.withOpacity(0.12)
                    : palette.accent,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                actionLabel,
                style: GoogleFonts.inter(
                  fontSize: 10.5,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.3,
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
