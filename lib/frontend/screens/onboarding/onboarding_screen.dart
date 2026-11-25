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
import '../../widgets/motion.dart';
import '../legal/privacy_policy_screen.dart';

/// Clean, Minimal, and Sovereign Onboarding Experience.
/// Hinge-style flow: one question per screen, thin progress bar, back chevron,
/// serif headline, underlined input and a round "next" button.
///   0: Privacy pledge   1: Shield name   2: Content rules   3: VPN   4: Accessibility   5: Battery
class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> with WidgetsBindingObserver {
  static const int _stepCount = 6;
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
        if (savedStep != null && savedStep >= 0 && savedStep < _stepCount) {
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
    await ref.read(authProvider.notifier).finalizeAccountWithName(profileName);

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
        appRoute(const FocusDNSHomeScreen()),
      );
    }
  }

  // ---------------------------------------------------------------------------
  // Hinge-style presentation
  // ---------------------------------------------------------------------------
  static const List<Map<String, String>> _categoryOptions = [
    {'id': 'adult', 'icon': '🔞', 'title': 'Adult content & NSFW', 'sub': '45,000+ adult domains and SafeSearch enforcement'},
    {'id': 'social', 'icon': '📱', 'title': 'Social media feeds', 'sub': 'Instagram, TikTok, Facebook, X and Snapchat'},
    {'id': 'trackers', 'icon': '🛡️', 'title': 'Ads & trackers', 'sub': 'In-app ad SDKs, analytics and surveillance networks'},
    {'id': 'gambling', 'icon': '🎰', 'title': 'Gambling & betting', 'sub': 'Casinos, sports betting and wager sites'},
  ];

  bool get _canContinue {
    if (_isLaunching) return false;
    if (_currentStep == 1) return _nameController.text.trim().isNotEmpty;
    return true;
  }

  void _goNext() {
    if (!_canContinue) return;
    FocusScope.of(context).unfocus();
    if (_currentStep < _stepCount - 1) {
      setState(() => _currentStep++);
      _saveStep(_currentStep);
    } else {
      _completeOnboarding();
    }
  }

  void _goBack() {
    if (_currentStep == 0) return;
    FocusScope.of(context).unfocus();
    setState(() => _currentStep--);
    _saveStep(_currentStep);
  }

  @override
  Widget build(BuildContext context) {
    final themeMode = ref.watch(themeModeProvider);
    final palette = themeMode == ThemeMode.light ? WabiSabiPalette.light : WabiSabiPalette.dark;
    final progress = (_currentStep + 1) / _stepCount;

    return PopScope(
      canPop: _currentStep == 0,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _goBack();
      },
      child: Scaffold(
        backgroundColor: palette.canvas,
        body: SafeArea(
          child: Column(
            children: [
              // Top bar: back chevron + thin progress bar (Hinge)
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 8, 24, 0),
                child: Row(
                  children: [
                    SizedBox(
                      width: 48,
                      height: 48,
                      child: _currentStep == 0
                          ? null
                          : IconButton(
                              key: const Key('onboarding_back_button'),
                              onPressed: _goBack,
                              icon: Icon(Icons.chevron_left_rounded, size: 32, color: palette.ink),
                            ),
                    ),
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(2),
                        child: TweenAnimationBuilder<double>(
                          tween: Tween<double>(begin: 0, end: progress),
                          duration: const Duration(milliseconds: 350),
                          curve: Curves.easeOutCubic,
                          builder: (_, v, __) => LinearProgressIndicator(
                            value: v,
                            minHeight: 4,
                            backgroundColor: palette.border,
                            valueColor: AlwaysStoppedAnimation<Color>(palette.ink),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 280),
                  switchInCurve: Curves.easeOutCubic,
                  switchOutCurve: Curves.easeInCubic,
                  transitionBuilder: (child, anim) => FadeTransition(
                    opacity: anim,
                    child: SlideTransition(
                      position: Tween<Offset>(begin: const Offset(0.06, 0), end: Offset.zero).animate(anim),
                      child: child,
                    ),
                  ),
                  child: KeyedSubtree(
                    key: ValueKey<int>(_currentStep),
                    child: _buildCurrentStep(palette),
                  ),
                ),
              ),
              _buildBottomBar(palette),
            ],
          ),
        ),
      ),
    );
  }

  Widget _headline(WabiSabiPalette palette, String text) => Text(
        text,
        style: GoogleFonts.fraunces(fontSize: 34, height: 1.12, fontWeight: FontWeight.w700, color: palette.ink, letterSpacing: -0.6),
      );

  Widget _buildCurrentStep(WabiSabiPalette palette) {
    switch (_currentStep) {
      case 0:
        return _buildPledgeStep(palette);
      case 1:
        return _buildNameStep(palette);
      case 2:
        return _buildCategoriesStep(palette);
      case 3:
        return _buildPermissionStep(
          palette,
          icon: Icons.vpn_lock_rounded,
          title: 'Turn on your\nlocal shield',
          body: 'FocusDNS filters DNS on this phone to block the sites and apps you choose. Nothing leaves your device.',
          granted: _vpnPrepared,
        );
      case 4:
        return _buildPermissionStep(
          palette,
          icon: Icons.accessibility_new_rounded,
          title: 'Stay focused\nin your apps',
          body: 'Accessibility lets FocusDNS close restricted apps and feeds the moment you open them.',
          granted: _accessibilityEnabled,
        );
      default:
        return _buildPermissionStep(
          palette,
          icon: Icons.battery_charging_full_rounded,
          title: 'Keep protection\nrunning',
          body: 'Allow FocusDNS to run in the background so Android does not stop your shield during deep sleep.',
          granted: _batteryExempt,
        );
    }
  }

  Widget _buildPledgeStep(WabiSabiPalette palette) {
    const pledges = <List<dynamic>>[
      [Icons.phone_android_rounded, 'Your data stays on your phone', 'Rules, lists, history and stats are stored on this device. Your email is only used to sign you in.'],
      [Icons.visibility_off_outlined, 'We never read your screen', 'Accessibility only closes the apps and feeds you restrict. We do not see messages or passwords.'],
      [Icons.lock_outline_rounded, 'Blocked lookups stay private', 'Blocked requests never leave your phone. Allowed ones go to a public DNS resolver, like they do today.'],
      [Icons.delete_outline_rounded, 'You are in control', 'Log out any time, or delete your account and everything stored on this device.'],
    ];
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          FadeSlideIn(child: _headline(palette, 'Welcome to FocusDNS.\nHere is how we\nhandle your data.')),
          const SizedBox(height: 24),
          for (var i = 0; i < pledges.length; i++)
            FadeSlideIn(
              delay: FadeSlideIn.stagger(i + 2, stepMs: 90),
              child: Padding(
                padding: const EdgeInsets.only(bottom: 18),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: palette.border, width: 1.3)),
                      child: Icon(pledges[i][0] as IconData, size: 20, color: palette.ink),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(pledges[i][1] as String, style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.w700, color: palette.ink)),
                          const SizedBox(height: 3),
                          Text(pledges[i][2] as String, style: GoogleFonts.inter(fontSize: 14, height: 1.45, color: palette.mutedInk)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          FadeSlideIn(
            delay: FadeSlideIn.stagger(7, stepMs: 90),
            child: GestureDetector(
              key: const Key('onboarding_privacy_link'),
              onTap: () => openPrivacyPolicy(context),
              child: Text('Read the full Privacy Policy',
                  style: GoogleFonts.inter(fontSize: 14.5, fontWeight: FontWeight.w700, color: palette.ink, decoration: TextDecoration.underline)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNameStep(WabiSabiPalette palette) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          FadeSlideIn(child: _headline(palette, 'What should we\ncall your shield?')),
          const SizedBox(height: 28),
          TextField(
            key: const Key('onboarding_name_field'),
            controller: _nameController,
            autofocus: true,
            textCapitalization: TextCapitalization.words,
            textInputAction: TextInputAction.done,
            maxLength: 24,
            onChanged: (_) => setState(() {}),
            onSubmitted: (_) => _goNext(),
            cursorColor: palette.ink,
            style: GoogleFonts.inter(fontSize: 26, fontWeight: FontWeight.w500, color: palette.ink),
            decoration: InputDecoration(
              hintText: 'Shield name',
              counterText: '',
              hintStyle: GoogleFonts.inter(fontSize: 26, fontWeight: FontWeight.w500, color: palette.mutedInk.withOpacity(0.5)),
              enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: palette.border, width: 1.5)),
              focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: palette.ink, width: 2)),
              contentPadding: const EdgeInsets.symmetric(vertical: 10),
            ),
          ),
          const SizedBox(height: 14),
          Text(
            'This is how your profile appears on your phone. You can change it later.',
            style: GoogleFonts.inter(fontSize: 13.5, height: 1.4, color: palette.mutedInk),
          ),
          const SizedBox(height: 6),
          Text('Required', style: GoogleFonts.inter(fontSize: 12.5, fontWeight: FontWeight.w600, color: palette.mutedInk)),
        ],
      ),
    );
  }

  Widget _buildCategoriesStep(WabiSabiPalette palette) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          FadeSlideIn(child: _headline(palette, 'What pulls you\naway from focus?')),
          const SizedBox(height: 8),
          Text('Select all that apply', style: GoogleFonts.inter(fontSize: 13.5, color: palette.mutedInk)),
          const SizedBox(height: 22),
          for (var i = 0; i < _categoryOptions.length; i++) ...[
            FadeSlideIn(delay: FadeSlideIn.stagger(i + 1, stepMs: 80), child: _buildOptionTile(palette, _categoryOptions[i])),
            const SizedBox(height: 12),
          ],
        ],
      ),
    );
  }

  Widget _buildOptionTile(WabiSabiPalette palette, Map<String, String> c) {
    final id = c['id']!;
    final selected = _selectedCategories.contains(id);
    return InkWell(
      key: Key('onboarding_option_$id'),
      borderRadius: BorderRadius.circular(14),
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
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: selected ? palette.surface : Colors.transparent,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: selected ? palette.ink : palette.border, width: selected ? 2 : 1.2),
        ),
        child: Row(
          children: [
            Text(c['icon']!, style: const TextStyle(fontSize: 24)),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(c['title']!, style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.w600, color: palette.ink)),
                  const SizedBox(height: 2),
                  Text(c['sub']!, style: GoogleFonts.inter(fontSize: 12.5, height: 1.35, color: palette.mutedInk)),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Container(
              width: 26,
              height: 26,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: selected ? palette.ink : Colors.transparent,
                border: Border.all(color: selected ? palette.ink : palette.border, width: 1.5),
              ),
              child: selected ? Icon(Icons.check_rounded, size: 17, color: palette.canvas) : null,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPermissionStep(
    WabiSabiPalette palette, {
    required IconData icon,
    required String title,
    required String body,
    required bool granted,
  }) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _headline(palette, title),
          const SizedBox(height: 14),
          Text(body, style: GoogleFonts.inter(fontSize: 15, height: 1.5, color: palette.mutedInk)),
          const Spacer(),
          Center(
            child: Container(
              width: 140,
              height: 140,
              decoration: BoxDecoration(shape: BoxShape.circle, color: palette.surface, border: Border.all(color: palette.border, width: 1.2)),
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 380),
                switchInCurve: Curves.elasticOut,
                transitionBuilder: (c, a) => ScaleTransition(scale: a, child: c),
                child: Icon(granted ? Icons.check_rounded : icon, key: ValueKey<bool>(granted), size: 64, color: granted ? palette.accent : palette.ink),
              ),
            ),
          ),
          const Spacer(),
        ],
      ),
    );
  }

  Future<void> _requestCurrentPermission() async {
    if (_currentStep == 3) {
      await _requestVpn();
    } else if (_currentStep == 4) {
      await _requestAccessibility();
    } else if (_currentStep == 5) {
      await _requestBattery();
    }
  }

  bool get _currentPermissionGranted =>
      _currentStep == 3 ? _vpnPrepared : _currentStep == 4 ? _accessibilityEnabled : _batteryExempt;

  Widget _buildBottomBar(WabiSabiPalette palette) {
    final isPermissionStep = _currentStep >= 3;

    if (_currentStep == 0) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(24, 8, 24, 20),
        child: SizedBox(
          width: double.infinity,
          height: 56,
          child: PressableScale(
            onTap: _goNext,
            child: Container(
              key: const Key('onboarding_agree_button'),
              alignment: Alignment.center,
              decoration: BoxDecoration(color: palette.ink, borderRadius: BorderRadius.circular(28)),
              child: Text('I agree', style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.w700, color: palette.canvas)),
            ),
          ),
        ),
      );
    }

    if (!isPermissionStep) {
      // Round "next" arrow, bottom-right (Hinge)
      final enabled = _canContinue;
      return Padding(
        padding: const EdgeInsets.fromLTRB(24, 8, 24, 20),
        child: Align(
          alignment: Alignment.centerRight,
          child: GestureDetector(
            key: const Key('onboarding_next_button'),
            onTap: enabled ? _goNext : null,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              width: 60,
              height: 60,
              decoration: BoxDecoration(shape: BoxShape.circle, color: enabled ? palette.ink : palette.border),
              child: Icon(Icons.arrow_forward_rounded, size: 28, color: enabled ? palette.canvas : palette.mutedInk),
            ),
          ),
        ),
      );
    }

    final granted = _currentPermissionGranted;
    final isLast = _currentStep == _stepCount - 1;
    final labels = ['Allow VPN access', 'Open Accessibility settings', 'Allow background running'];
    final primaryLabel = granted ? (isLast ? 'Activate shield' : 'Continue') : labels[_currentStep - 3];

    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: double.infinity,
            height: 56,
            child: ElevatedButton(
              key: const Key('onboarding_primary_button'),
              onPressed: _isLaunching
                  ? null
                  : () async {
                      if (granted) {
                        _goNext();
                      } else {
                        await _requestCurrentPermission();
                      }
                    },
              style: ElevatedButton.styleFrom(
                backgroundColor: palette.ink,
                foregroundColor: palette.canvas,
                elevation: 0,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
              ),
              child: _isLaunching
                  ? SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.2, color: palette.canvas))
                  : Text(primaryLabel, style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.w700)),
            ),
          ),
          if (!granted)
            TextButton(
              key: const Key('onboarding_skip_button'),
              onPressed: _isLaunching ? null : _goNext,
              child: Text('Maybe later', style: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.w600, color: palette.mutedInk)),
            )
          else
            const SizedBox(height: 48),
        ],
      ),
    );
  }
}
