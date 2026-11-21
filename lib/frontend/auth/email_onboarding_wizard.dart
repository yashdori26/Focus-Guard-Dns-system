import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../backend/blocker_service.dart';
import '../../backend/vpn_service.dart';
import '../../state_management/providers.dart';
import '../theme/wabi_sabi_theme.dart';

/// 4-Step Progressive Onboarding Wizard
/// 1. Email & Password -> 2. 4-Digit Code -> 3. Profile Name -> 4. Permissions -> Protect Dashboard
class EmailOnboardingWizard extends ConsumerStatefulWidget {
  const EmailOnboardingWizard({super.key});

  @override
  ConsumerState<EmailOnboardingWizard> createState() => _EmailOnboardingWizardState();
}

class _EmailOnboardingWizardState extends ConsumerState<EmailOnboardingWizard> with WidgetsBindingObserver {
  // Mode for Screen 1
  bool _isSignUp = true;

  // Controllers
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  final _otpController = TextEditingController();
  final _profileNameController = TextEditingController();

  bool _obscurePassword = true;
  bool _obscureConfirm = true;
  String? _localError;

  // Resend OTP Countdown
  int _resendCountdown = 0;
  Timer? _countdownTimer;

  // Permission states for Screen 3
  bool _vpnGranted = false;
  bool _accessibilityGranted = false;
  bool _notificationsGranted = false;
  bool _batteryGranted = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _checkAllDevicePermissions();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _countdownTimer?.cancel();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    _otpController.dispose();
    _profileNameController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _checkAllDevicePermissions();
    }
  }

  Future<void> _checkAllDevicePermissions() async {
    final vpn = await FocusDnsVpnManager.isRunning();
    final accessibility = await FocusDnsBlockerManager.isAccessibilityServiceEnabled();
    final battery = await FocusDnsBlockerManager.isBatteryOptimizationIgnored();
    final notifs = await FocusDnsBlockerManager.isNotificationPermissionGranted();

    if (mounted) {
      setState(() {
        if (vpn) _vpnGranted = true;
        if (accessibility) _accessibilityGranted = true;
        if (battery) _batteryGranted = true;
        if (notifs) _notificationsGranted = true;
      });
    }
  }

  void _startResendTimer() {
    _countdownTimer?.cancel();
    setState(() => _resendCountdown = 30);
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_resendCountdown > 0) {
        setState(() => _resendCountdown--);
      } else {
        timer.cancel();
      }
    });
  }

  int _getStepIndex(AuthStep step) {
    switch (step) {
      case AuthStep.profileSetup:
        return 1;
      case AuthStep.permissionSetup:
        return 2;
      default:
        return 0;
    }
  }

  // --- Actions ---

  Future<void> _handleEmailSubmit() async {
    setState(() => _localError = null);
    final email = _emailController.text.trim();
    final password = _passwordController.text;

    if (email.isEmpty || !email.contains('@') || !email.contains('.')) {
      setState(() => _localError = 'Please enter a valid email address.');
      return;
    }

    if (password.length < 6) {
      setState(() => _localError = 'Password must be at least 6 characters.');
      return;
    }

    if (_isSignUp) {
      final confirm = _confirmPasswordController.text;
      if (password != confirm) {
        setState(() => _localError = 'Passwords do not match.');
        return;
      }

      // Option A: Advance directly to Profile Setup (zero email code dependency)
      ref.read(authProvider.notifier).startEmailRegistration(
        email: email,
        password: password,
      );
    } else {
      // Sign In mode: direct authentication
      final res = await ref.read(authProvider.notifier).loginWithEmail(email, password);
      if (res['success'] != true && mounted) {
        setState(() => _localError = res['error']?.toString() ?? 'Invalid email or password.');
      } else {
        ref.read(setupProvider.notifier).autoSyncAndLinkIp();
      }
    }
  }

  Future<void> _handleOtpSubmit() async {
    // Legacy fallback
    setState(() => _localError = null);
    final code = _otpController.text.trim();
    if (code.length != 4) {
      setState(() => _localError = 'Please enter the 4-digit code.');
      return;
    }

    final res = await ref.read(authProvider.notifier).verifyEmail4DigitCode(code);
    if (res['success'] != true && mounted) {
      setState(() => _localError = res['error']?.toString() ?? 'Invalid code. Use 1234.');
    }
  }

  void _handleProfileNameSubmit() {
    setState(() => _localError = null);
    final raw = _profileNameController.text.trim();
    if (raw.isEmpty) {
      setState(() => _localError = 'Please enter a profile name.');
      return;
    }
    ref.read(authProvider.notifier).setOnboardingProfileName(raw);
  }

  Future<void> _grantVpn() async {
    final prepared = await FocusDnsVpnManager.prepare();
    if (mounted) {
      setState(() => _vpnGranted = prepared);
      if (prepared) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('✓ Local DNS VPN permission granted.')),
        );
      }
    }
  }

  Future<void> _grantAccessibility() async {
    // Option 2A: Direct deep link with helpful instruction banner
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Select "Downloaded apps" -> "FocusDNS" and toggle it ON.'),
        duration: Duration(seconds: 4),
      ),
    );
    final opened = await FocusDnsBlockerManager.openAccessibilitySettings();
    if (mounted && opened) {
      final isEnabled = await FocusDnsBlockerManager.isAccessibilityServiceEnabled();
      if (isEnabled) {
        setState(() => _accessibilityGranted = true);
      }
    }
  }

  Future<void> _grantNotifications() async {
    final granted = await FocusDnsBlockerManager.requestNotificationPermission();
    if (mounted) {
      setState(() => _notificationsGranted = granted);
      if (granted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('✓ Focus notifications enabled.')),
        );
      }
    }
  }

  Future<void> _grantBattery() async {
    final requested = await FocusDnsBlockerManager.requestIgnoreBatteryOptimizations();
    if (mounted) {
      setState(() => _batteryGranted = requested);
      if (requested) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('✓ Battery optimization exemption requested.')),
        );
      }
    }
  }

  Future<void> _handleFinishPermissions() async {
    // 1. If VPN was granted, start on-device VPN
    if (_vpnGranted) {
      await ref.read(vpnProvider.notifier).start();
    }

    // 2. If Accessibility was granted, sync blocker status
    if (_accessibilityGranted) {
      await ref.read(blockerProvider.notifier).checkStatus();
    }

    // 3. Complete auth session provisioning
    await ref.read(authProvider.notifier).completePermissionsAndLaunch(
      password: _passwordController.text,
    );

    // 4. Auto-sync IP in background upon completing onboarding (Option 1A)
    ref.read(setupProvider.notifier).autoSyncAndLinkIp();
  }

  @override
  Widget build(BuildContext context) {
    final palette = WabiSabiPalette.of(context);
    final themeMode = ref.watch(themeModeProvider);
    final auth = ref.watch(authProvider);

    final stepIndex = _getStepIndex(auth.currentStep);
    final errorText = _localError ?? auth.errorMessage;

    return Scaffold(
      backgroundColor: palette.canvas,
      body: SafeArea(
        child: Column(
          children: [
            // Header Bar with Step Navigation, Monogram & Theme Toggle
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  if (stepIndex > 0)
                    IconButton(
                      icon: Icon(Icons.arrow_back_ios_new_rounded, size: 18, color: palette.ink),
                      onPressed: () {
                        if (stepIndex == 1) {
                          ref.read(authProvider.notifier).goToStep(AuthStep.emailInput);
                        } else if (stepIndex == 2) {
                          ref.read(authProvider.notifier).goToStep(AuthStep.profileSetup);
                        }
                      },
                    )
                  else
                    Row(
                      children: [
                        Container(
                          width: 26,
                          height: 26,
                          decoration: BoxDecoration(
                            color: palette.ink,
                            shape: BoxShape.circle,
                          ),
                          child: Center(
                            child: Text(
                              'F',
                              style: TextStyle(
                                color: palette.canvas,
                                fontFamily: 'JetBrains Mono',
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'FOCUS DNS',
                          style: GoogleFonts.inter(
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 2.0,
                            color: palette.ink,
                          ),
                        ),
                      ],
                    ),

                  // Progress Indicator Dots (3 Steps)
                  Row(
                    children: List.generate(3, (idx) {
                      final isActive = (idx == stepIndex);
                      final isPassed = (idx < stepIndex);
                      return AnimatedContainer(
                        duration: const Duration(milliseconds: 250),
                        margin: const EdgeInsets.symmetric(horizontal: 3),
                        width: isActive ? 22 : 7,
                        height: 7,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(4),
                          color: isActive
                              ? palette.ink
                              : isPassed
                                  ? palette.ink.withOpacity(0.4)
                                  : palette.border,
                        ),
                      );
                    }),
                  ),

                  // Theme Toggle
                  IconButton(
                    icon: Icon(
                      themeMode == ThemeMode.light
                          ? Icons.dark_mode_outlined
                          : Icons.light_mode_outlined,
                      color: palette.ink,
                      size: 20,
                    ),
                    onPressed: () => ref.read(themeModeProvider.notifier).toggle(),
                  ),
                ],
              ),
            ),

            Divider(height: 1, color: palette.hairlineSoft),

            // Animated View Switcher for the 4 Steps
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Error Banner
                    if (errorText != null && errorText.isNotEmpty) ...[
                      Container(
                        key: const Key('auth_error_banner'),
                        padding: const EdgeInsets.all(12),
                        margin: const EdgeInsets.only(bottom: 20),
                        decoration: BoxDecoration(
                          color: palette.strictAccent.withOpacity(0.08),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: palette.strictAccent.withOpacity(0.35)),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.error_outline_rounded, size: 18, color: palette.strictAccent),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                errorText,
                                style: GoogleFonts.inter(
                                  fontSize: 12,
                                  color: palette.strictAccent,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],

                    if (stepIndex == 0) _buildStep0EmailPassword(palette, auth),
                    if (stepIndex == 1) _buildStep2ProfileName(palette, auth),
                    if (stepIndex == 2) _buildStep3Permissions(palette, auth),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ==========================================
  // STEP 0: EMAIL & PASSWORD
  // ==========================================
  Widget _buildStep0EmailPassword(WabiSabiPalette palette, AuthState auth) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          _isSignUp ? 'STEP 1 OF 3 · GET STARTED' : 'WELCOME BACK',
          style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 1.4, color: palette.mutedInk),
        ),
        const SizedBox(height: 6),
        Text(
          _isSignUp ? 'Create your account.' : 'Sign in to FocusDNS.',
          style: GoogleFonts.fraunces(fontSize: 28, fontWeight: FontWeight.w700, color: palette.ink, letterSpacing: -0.5),
        ),
        const SizedBox(height: 6),
        Text(
          _isSignUp
              ? 'Enter your email and create a password to set up your shield.'
              : 'Sign in to access your DNS profiles, blacklists, and analytics.',
          style: GoogleFonts.inter(fontSize: 13, color: palette.mutedInk, height: 1.35),
        ),
        const SizedBox(height: 20),

        // Mode Switcher Capsule
        Container(
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: palette.surface,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: palette.hairlineSoft),
          ),
          child: Row(
            children: [
              Expanded(
                child: GestureDetector(
                  key: const Key('tab_sign_in'),
                  onTap: () => setState(() {
                    _isSignUp = false;
                    _localError = null;
                  }),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 9),
                    decoration: BoxDecoration(
                      color: !_isSignUp ? palette.canvas : Colors.transparent,
                      borderRadius: BorderRadius.circular(7),
                      border: !_isSignUp ? Border.all(color: palette.hairlineSoft) : null,
                    ),
                    child: Center(
                      child: Text(
                        'Sign In',
                        style: GoogleFonts.inter(
                          fontSize: 13,
                          fontWeight: !_isSignUp ? FontWeight.w700 : FontWeight.w500,
                          color: !_isSignUp ? palette.ink : palette.mutedInk,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 4),
              Expanded(
                child: GestureDetector(
                  key: const Key('tab_create_account'),
                  onTap: () => setState(() {
                    _isSignUp = true;
                    _localError = null;
                  }),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 9),
                    decoration: BoxDecoration(
                      color: _isSignUp ? palette.canvas : Colors.transparent,
                      borderRadius: BorderRadius.circular(7),
                      border: _isSignUp ? Border.all(color: palette.hairlineSoft) : null,
                    ),
                    child: Center(
                      child: Text(
                        'Create Account',
                        style: GoogleFonts.inter(
                          fontSize: 13,
                          fontWeight: _isSignUp ? FontWeight.w700 : FontWeight.w500,
                          color: _isSignUp ? palette.ink : palette.mutedInk,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 24),

        // Email Field
        Text('EMAIL ADDRESS', style: GoogleFonts.inter(fontSize: 10.5, fontWeight: FontWeight.w700, letterSpacing: 0.8, color: palette.mutedInk)),
        const SizedBox(height: 6),
        TextFormField(
          key: const Key('email_input_field'),
          controller: _emailController,
          keyboardType: TextInputType.emailAddress,
          style: GoogleFonts.inter(fontSize: 14, color: palette.ink),
          decoration: InputDecoration(
            prefixIcon: Icon(Icons.alternate_email_rounded, size: 18, color: palette.mutedInk),
            filled: true,
            fillColor: palette.surface,
            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: palette.border)),
            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: palette.border)),
            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: palette.ink, width: 1.5)),
          ),
        ),

        const SizedBox(height: 16),

        // Password Field
        Text('PASSWORD', style: GoogleFonts.inter(fontSize: 10.5, fontWeight: FontWeight.w700, letterSpacing: 0.8, color: palette.mutedInk)),
        const SizedBox(height: 6),
        TextFormField(
          key: const Key('password_input_field'),
          controller: _passwordController,
          obscureText: _obscurePassword,
          style: GoogleFonts.inter(fontSize: 14, color: palette.ink),
          decoration: InputDecoration(
            prefixIcon: Icon(Icons.lock_outline_rounded, size: 18, color: palette.mutedInk),
            suffixIcon: IconButton(
              key: const Key('toggle_password_visibility'),
              icon: Icon(_obscurePassword ? Icons.visibility_off_outlined : Icons.visibility_outlined, size: 18, color: palette.mutedInk),
              onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
            ),
            filled: true,
            fillColor: palette.surface,
            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: palette.border)),
            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: palette.border)),
            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: palette.ink, width: 1.5)),
          ),
        ),

        if (_isSignUp) ...[
          const SizedBox(height: 16),
          Text('CONFIRM PASSWORD', style: GoogleFonts.inter(fontSize: 10.5, fontWeight: FontWeight.w700, letterSpacing: 0.8, color: palette.mutedInk)),
          const SizedBox(height: 6),
          TextFormField(
            key: const Key('confirm_password_input_field'),
            controller: _confirmPasswordController,
            obscureText: _obscureConfirm,
            style: GoogleFonts.inter(fontSize: 14, color: palette.ink),
            decoration: InputDecoration(
              prefixIcon: Icon(Icons.lock_reset_rounded, size: 18, color: palette.mutedInk),
              suffixIcon: IconButton(
                icon: Icon(_obscureConfirm ? Icons.visibility_off_outlined : Icons.visibility_outlined, size: 18, color: palette.mutedInk),
                onPressed: () => setState(() => _obscureConfirm = !_obscureConfirm),
              ),
              filled: true,
              fillColor: palette.surface,
              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: palette.border)),
              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: palette.border)),
              focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: palette.ink, width: 1.5)),
            ),
          ),
        ],

        const SizedBox(height: 28),

        SizedBox(
          width: double.infinity,
          height: 48,
          child: ElevatedButton(
            key: const Key('submit_auth_button'),
            onPressed: auth.isLoading ? null : _handleEmailSubmit,
            style: ElevatedButton.styleFrom(
              backgroundColor: palette.ink,
              foregroundColor: palette.canvas,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            child: auth.isLoading
                ? SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: palette.canvas))
                : Text(
                    _isSignUp ? 'Continue to Profile Setup' : 'Sign In to FocusDNS',
                    style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w700),
                  ),
          ),
        ),
      ],
    );
  }

  // ==========================================
  // STEP 1: 4-DIGIT VERIFICATION CODE
  // ==========================================
  Widget _buildStep1OtpVerification(WabiSabiPalette palette, AuthState auth) {
    final emailDisplay = auth.email ?? _emailController.text.trim();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'STEP 2 OF 4 · SECURITY VERIFICATION',
          style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 1.4, color: palette.mutedInk),
        ),
        const SizedBox(height: 6),
        Text(
          'Check your inbox.',
          style: GoogleFonts.fraunces(fontSize: 28, fontWeight: FontWeight.w700, color: palette.ink, letterSpacing: -0.5),
        ),
        const SizedBox(height: 6),
        Text(
          'We sent a 4-digit verification code to $emailDisplay.',
          style: GoogleFonts.inter(fontSize: 13, color: palette.mutedInk, height: 1.35),
        ),
        const SizedBox(height: 24),

        // 4-Digit Code Field
        Text('ENTER 4-DIGIT CODE', style: GoogleFonts.inter(fontSize: 10.5, fontWeight: FontWeight.w700, letterSpacing: 0.8, color: palette.mutedInk)),
        const SizedBox(height: 8),
        TextFormField(
          key: const Key('otp_code_field'),
          controller: _otpController,
          keyboardType: TextInputType.number,
          maxLength: 4,
          textAlign: TextAlign.center,
          style: GoogleFonts.inter(fontSize: 24, fontWeight: FontWeight.w800, letterSpacing: 12.0, color: palette.ink),
          decoration: InputDecoration(
            counterText: '',
            filled: true,
            fillColor: palette.surface,
            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: palette.border)),
            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: palette.border)),
            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: palette.ink, width: 2.0)),
          ),
        ),

        const SizedBox(height: 12),

        // Auto-Fill dev test chip (Option 2A) & Resend
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            InkWell(
              key: const Key('autofill_dev_code'),
              onTap: () {
                _otpController.text = auth.devOtp ?? '1234';
                setState(() {});
              },
              borderRadius: BorderRadius.circular(6),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: palette.surface,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: palette.border),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.bolt_rounded, size: 14, color: palette.accent),
                    const SizedBox(width: 4),
                    Text('Auto-Fill (1234)', style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w600, color: palette.ink)),
                  ],
                ),
              ),
            ),
            TextButton(
              key: const Key('resend_code_button'),
              onPressed: _resendCountdown > 0
                  ? null
                  : () {
                      ref.read(authProvider.notifier).sendEmailVerificationCode(emailDisplay, isNewAccount: auth.isNewAccount);
                      _startResendTimer();
                    },
              child: Text(
                _resendCountdown > 0 ? 'Resend in ${_resendCountdown}s' : 'Resend Code',
                style: GoogleFonts.inter(fontSize: 12, color: _resendCountdown > 0 ? palette.mutedInk : palette.ink, fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),

        const SizedBox(height: 28),

        SizedBox(
          width: double.infinity,
          height: 48,
          child: ElevatedButton(
            key: const Key('verify_code_button'),
            onPressed: auth.isLoading ? null : _handleOtpSubmit,
            style: ElevatedButton.styleFrom(
              backgroundColor: palette.ink,
              foregroundColor: palette.canvas,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            child: auth.isLoading
                ? SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: palette.canvas))
                : Text('Verify & Continue', style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w700)),
          ),
        ),
      ],
    );
  }

  // ==========================================
  // STEP 2: PROFILE NAME SETUP
  // ==========================================
  Widget _buildStep2ProfileName(WabiSabiPalette palette, AuthState auth) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'STEP 2 OF 3 · PROFILE SETUP',
          style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 1.4, color: palette.mutedInk),
        ),
        const SizedBox(height: 6),
        Text(
          'Name your DNS profile.',
          style: GoogleFonts.fraunces(fontSize: 28, fontWeight: FontWeight.w700, color: palette.ink, letterSpacing: -0.5),
        ),
        const SizedBox(height: 6),
        Text(
          'This profile organizes your blocked feeds, parental rules and focus sessions.',
          style: GoogleFonts.inter(fontSize: 13, color: palette.mutedInk, height: 1.35),
        ),
        const SizedBox(height: 24),

        Text('PROFILE NAME', style: GoogleFonts.inter(fontSize: 10.5, fontWeight: FontWeight.w700, letterSpacing: 0.8, color: palette.mutedInk)),
        const SizedBox(height: 8),
        TextFormField(
          key: const Key('onboarding_profile_name_field'),
          controller: _profileNameController,
          style: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.w600, color: palette.ink),
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(
            prefixIcon: Icon(Icons.shield_outlined, size: 20, color: palette.accent),
            filled: true,
            fillColor: palette.surface,
            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: palette.border)),
            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: palette.border)),
            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: palette.ink, width: 1.5)),
          ),
        ),

        const SizedBox(height: 32),

        SizedBox(
          width: double.infinity,
          height: 48,
          child: ElevatedButton(
            key: const Key('profile_name_continue_button'),
            onPressed: _handleProfileNameSubmit,
            style: ElevatedButton.styleFrom(
              backgroundColor: palette.ink,
              foregroundColor: palette.canvas,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            child: Text('Next: Set Up Permissions', style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w700)),
          ),
        ),
      ],
    );
  }

  // ==========================================
  // STEP 3: APP PERMISSIONS SETUP (ALL 4 CORE)
  // ==========================================
  Widget _buildStep3Permissions(WabiSabiPalette palette, AuthState auth) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'STEP 3 OF 3 · ESSENTIAL PERMISSIONS',
          style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 1.4, color: palette.mutedInk),
        ),
        const SizedBox(height: 6),
        Text(
          'Activate on-device shields.',
          style: GoogleFonts.fraunces(fontSize: 28, fontWeight: FontWeight.w700, color: palette.ink, letterSpacing: -0.5),
        ),
        const SizedBox(height: 6),
        Text(
          'FocusDNS operates locally. These 4 permissions ensure full distraction blocking and battery-efficient protection.',
          style: GoogleFonts.inter(fontSize: 13, color: palette.mutedInk, height: 1.35),
        ),
        const SizedBox(height: 20),

        // Permission Tile 1: Local DNS VPN
        _buildPermissionTile(
          key: const Key('permission_tile_vpn'),
          buttonKey: const Key('grant_vpn_button'),
          icon: Icons.shield_outlined,
          title: 'Local DNS VPN',
          description: 'Sinkholes distraction feeds, trackers, and adult domains locally on your phone.',
          isGranted: _vpnGranted,
          palette: palette,
          onGrant: _grantVpn,
        ),

        const SizedBox(height: 12),

        // Permission Tile 2: Accessibility Blocker
        _buildPermissionTile(
          key: const Key('permission_tile_accessibility'),
          buttonKey: const Key('grant_accessibility_button'),
          icon: Icons.accessibility_new_rounded,
          title: 'Native App Blocker',
          description: 'Closes blocked apps immediately upon launch and enforces Strict Mode.',
          isGranted: _accessibilityGranted,
          palette: palette,
          onGrant: _grantAccessibility,
        ),

        const SizedBox(height: 12),

        // Permission Tile 3: Focus Notifications
        _buildPermissionTile(
          key: const Key('permission_tile_notifications'),
          buttonKey: const Key('grant_notifications_button'),
          icon: Icons.notifications_active_outlined,
          title: 'Focus Notifications',
          description: 'Displays persistent focus countdown timer in your status bar.',
          isGranted: _notificationsGranted,
          palette: palette,
          onGrant: _grantNotifications,
        ),

        const SizedBox(height: 12),

        // Permission Tile 4: Unrestricted Battery
        _buildPermissionTile(
          key: const Key('permission_tile_battery'),
          buttonKey: const Key('grant_battery_button'),
          icon: Icons.battery_charging_full_rounded,
          title: 'Unrestricted Background',
          description: 'Exempts DNS filtering from aggressive Android background task killers.',
          isGranted: _batteryGranted,
          palette: palette,
          onGrant: _grantBattery,
        ),

        const SizedBox(height: 28),

        SizedBox(
          width: double.infinity,
          height: 48,
          child: ElevatedButton(
            key: const Key('finish_onboarding_button'),
            onPressed: auth.isLoading ? null : _handleFinishPermissions,
            style: ElevatedButton.styleFrom(
              backgroundColor: palette.ink,
              foregroundColor: palette.canvas,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            child: auth.isLoading
                ? SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: palette.canvas))
                : Text('Complete Setup & Enter FocusDNS', style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w700)),
          ),
        ),
      ],
    );
  }

  Widget _buildPermissionTile({
    required Key key,
    required Key buttonKey,
    required IconData icon,
    required String title,
    required String description,
    required bool isGranted,
    required WabiSabiPalette palette,
    required VoidCallback onGrant,
  }) {
    return Container(
      key: key,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isGranted ? palette.safeAccent.withOpacity(0.4) : palette.hairlineSoft,
          width: 1.0,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(9),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: isGranted ? palette.safeAccent.withOpacity(0.12) : palette.ink.withOpacity(0.06),
            ),
            child: Icon(icon, size: 20, color: isGranted ? palette.safeAccent : palette.ink),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: GoogleFonts.inter(fontSize: 13.5, fontWeight: FontWeight.w700, color: palette.ink)),
                const SizedBox(height: 2),
                Text(description, style: GoogleFonts.inter(fontSize: 11, color: palette.mutedInk, height: 1.3)),
              ],
            ),
          ),
          const SizedBox(width: 10),
          ElevatedButton(
            key: buttonKey,
            onPressed: onGrant,
            style: ElevatedButton.styleFrom(
              backgroundColor: isGranted ? palette.surface : palette.ink,
              foregroundColor: isGranted ? palette.safeAccent : palette.canvas,
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(6),
                side: isGranted ? BorderSide(color: palette.safeAccent) : BorderSide.none,
              ),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: Text(
              isGranted ? 'GRANTED ✓' : 'GRANT',
              style: GoogleFonts.inter(fontSize: 10.5, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }
}
