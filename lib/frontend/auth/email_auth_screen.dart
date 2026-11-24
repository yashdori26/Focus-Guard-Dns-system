import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../backend/blocker_service.dart';
import '../../services/auth_storage_service.dart';
import '../../state_management/providers.dart';
import '../home_screen.dart';
import '../screens/onboarding/onboarding_screen.dart';
import '../theme/wabi_sabi_theme.dart';

enum AuthMode { signIn, createAccount }

/// Master Email & Password Authentication Screen.
/// Clean, minimal, tactile Wabi-Sabi aesthetic with 100% local database synchronization.
/// Safely persists credentials in local SQLite so active profiles and settings never reset.
class EmailAuthScreen extends ConsumerStatefulWidget {
  const EmailAuthScreen({super.key});

  @override
  ConsumerState<EmailAuthScreen> createState() => _EmailAuthScreenState();
}

class _EmailAuthScreenState extends ConsumerState<EmailAuthScreen> {
  AuthMode _mode = AuthMode.signIn;

  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  final _profileNameController = TextEditingController(text: 'Personal Shield');

  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;
  bool _rememberMe = true;
  String? _localError;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _loadRememberedCredentials();
  }

  Future<void> _loadRememberedCredentials() async {
    try {
      final creds = await AuthStorageService.getSavedCredentials();
      final email = creds['email'];
      final password = creds['password'];
      final profileName = creds['profile_name'];
      final remember = creds['remember_me'] != 'false';

      if (mounted) {
        setState(() {
          _rememberMe = remember;
          if (email != null && email.isNotEmpty) {
            _emailController.text = email;
          }
          if (password != null && password.isNotEmpty) {
            _passwordController.text = password;
          }
          if (profileName != null && profileName.isNotEmpty) {
            _profileNameController.text = profileName;
          }
        });
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    _profileNameController.dispose();
    super.dispose();
  }

  Future<void> _proceedNext() async {
    final prefs = await SharedPreferences.getInstance();
    bool completed = prefs.getBool('focus_onboarding_completed') ?? false;

    if (!completed) {
      try {
        final dbVal = await FocusDnsBlockerManager.getKv('focus_onboarding_completed', '0');
        if (dbVal == '1') completed = true;
      } catch (_) {}
    }

    if (!mounted) return;

    if (completed) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const FocusDNSHomeScreen()),
      );
    } else {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const OnboardingScreen()),
      );
    }
  }

  Future<void> _submit() async {
    setState(() {
      _localError = null;
    });

    final email = _emailController.text.trim();
    final password = _passwordController.text;

    final emailRegex = RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$');
    if (email.isEmpty || !emailRegex.hasMatch(email)) {
      setState(() => _localError = 'Please enter a valid email address.');
      return;
    }

    if (password.length < 6) {
      setState(() => _localError = 'Password must be at least 6 characters long.');
      return;
    }

    if (_mode == AuthMode.createAccount) {
      final confirm = _confirmPasswordController.text;
      if (password != confirm) {
        setState(() => _localError = 'Passwords do not match. Please verify.');
        return;
      }
    }

    setState(() => _isLoading = true);

    try {
      if (_mode == AuthMode.signIn) {
        final res = await ref.read(authProvider.notifier).loginWithEmail(email, password);
        if (res['success'] == true) {
          if (_rememberMe) {
            final activeName = await AuthStorageService.getActiveProfileName();
            await AuthStorageService.saveCredentials(
              email: email,
              password: password,
              profileName: activeName,
              rememberMe: true,
            );
          }
          await _proceedNext();
        } else {
          if (mounted) {
            setState(() {
              _localError = res['error']?.toString() ?? 'Sign in failed. Check your credentials.';
              _isLoading = false;
            });
          }
        }
      } else {
        final profileName = _profileNameController.text.trim().isNotEmpty
            ? _profileNameController.text.trim()
            : 'Personal Shield';

        final res = await ref.read(authProvider.notifier).registerWithEmail(
          email,
          password,
          profileName,
        );

        if (res['success'] == true) {
          if (_rememberMe) {
            await AuthStorageService.saveCredentials(
              email: email,
              password: password,
              profileName: profileName,
              rememberMe: true,
            );
          }
          await _proceedNext();
        } else {
          if (mounted) {
            setState(() {
              _localError = res['error']?.toString() ?? 'Registration failed. Please try again.';
              _isLoading = false;
            });
          }
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _localError = 'An unexpected error occurred: $e';
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = WabiSabiPalette.of(context);
    final themeMode = ref.watch(themeModeProvider);
    final auth = ref.watch(authProvider);

    final errorText = _localError ?? auth.errorMessage;
    final isBusy = _isLoading || auth.isLoading;

    return Scaffold(
      backgroundColor: palette.canvas,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Top App Bar: Monogram Logo + Brand + Theme Switcher + Skip
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Expanded(
                          child: Row(
                            children: [
                              Container(
                                width: 32,
                                height: 32,
                                decoration: BoxDecoration(
                                  color: palette.ink,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Center(
                                  child: Text(
                                    'F',
                                    style: GoogleFonts.jetBrainsMono(
                                      color: palette.canvas,
                                      fontWeight: FontWeight.w800,
                                      fontSize: 15,
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Flexible(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'FOCUS DNS',
                                      overflow: TextOverflow.ellipsis,
                                      style: GoogleFonts.inter(
                                        fontSize: 12.5,
                                        fontWeight: FontWeight.w800,
                                        letterSpacing: 1.6,
                                        color: palette.ink,
                                      ),
                                    ),
                                    Text(
                                      '100% Local · Sovereign Shield',
                                      overflow: TextOverflow.ellipsis,
                                      style: GoogleFonts.inter(
                                        fontSize: 10,
                                        fontWeight: FontWeight.w500,
                                        color: palette.mutedInk,
                                        letterSpacing: 0.3,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: Icon(
                                themeMode == ThemeMode.light
                                    ? Icons.dark_mode_outlined
                                    : Icons.light_mode_outlined,
                                color: palette.ink,
                                size: 19,
                              ),
                              tooltip: 'Toggle Theme',
                              padding: const EdgeInsets.all(6),
                              constraints: const BoxConstraints(),
                              visualDensity: VisualDensity.compact,
                              onPressed: () => ref.read(themeModeProvider.notifier).toggle(),
                            ),
                            const SizedBox(width: 4),
                            TextButton(
                              onPressed: _proceedNext,
                              style: TextButton.styleFrom(
                                foregroundColor: palette.mutedInk,
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                minimumSize: Size.zero,
                                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              ),
                              child: Row(
                                children: [
                                  Text(
                                    'Skip',
                                    style: GoogleFonts.inter(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                      letterSpacing: 0.2,
                                    ),
                                  ),
                                  const SizedBox(width: 3),
                                  const Icon(Icons.arrow_forward_rounded, size: 13),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),

                    const SizedBox(height: 32),

                    // Eyebrow & Headline
                    Text(
                      _mode == AuthMode.signIn ? 'WELCOME BACK' : 'SOVEREIGN SETUP',
                      style: GoogleFonts.inter(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.4,
                        color: palette.mutedInk,
                      ),
                    ),
                    const SizedBox(height: 6),

                    Text(
                      _mode == AuthMode.signIn
                          ? 'Sign in to FocusDNS.'
                          : 'Create your local shield.',
                      style: GoogleFonts.fraunces(
                        fontSize: 28,
                        fontWeight: FontWeight.w700,
                        color: palette.ink,
                        letterSpacing: -0.6,
                      ),
                    ),
                    const SizedBox(height: 6),

                    Text(
                      _mode == AuthMode.signIn
                          ? 'Access your DNS profiles, blocker preferences, and focus analytics.'
                          : 'All credentials and configurations are saved locally on-device.',
                      style: GoogleFonts.inter(
                        fontSize: 13,
                        color: palette.mutedInk,
                        height: 1.4,
                      ),
                    ),

                    const SizedBox(height: 24),

                    // Clean Mode Switcher Capsule (Sign In vs Create Account)
                    Container(
                      padding: const EdgeInsets.all(3),
                      decoration: BoxDecoration(
                        color: palette.surface,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: palette.border, width: 1),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: GestureDetector(
                              key: const Key('tab_sign_in'),
                              onTap: () {
                                setState(() {
                                  _mode = AuthMode.signIn;
                                  _localError = null;
                                });
                              },
                              child: Container(
                                padding: const EdgeInsets.symmetric(vertical: 9),
                                decoration: BoxDecoration(
                                  color: _mode == AuthMode.signIn ? palette.canvas : Colors.transparent,
                                  borderRadius: BorderRadius.circular(8),
                                  border: _mode == AuthMode.signIn
                                      ? Border.all(color: palette.hairlineSoft, width: 1)
                                      : null,
                                ),
                                child: Center(
                                  child: Text(
                                    'Sign In',
                                    style: GoogleFonts.inter(
                                      fontSize: 13,
                                      fontWeight: _mode == AuthMode.signIn ? FontWeight.w700 : FontWeight.w500,
                                      color: _mode == AuthMode.signIn ? palette.ink : palette.mutedInk,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 3),
                          Expanded(
                            child: GestureDetector(
                              key: const Key('tab_create_account'),
                              onTap: () {
                                setState(() {
                                  _mode = AuthMode.createAccount;
                                  _localError = null;
                                });
                              },
                              child: Container(
                                padding: const EdgeInsets.symmetric(vertical: 9),
                                decoration: BoxDecoration(
                                  color: _mode == AuthMode.createAccount ? palette.canvas : Colors.transparent,
                                  borderRadius: BorderRadius.circular(8),
                                  border: _mode == AuthMode.createAccount
                                      ? Border.all(color: palette.hairlineSoft, width: 1)
                                      : null,
                                ),
                                child: Center(
                                  child: Text(
                                    'Create Account',
                                    style: GoogleFonts.inter(
                                      fontSize: 13,
                                      fontWeight: _mode == AuthMode.createAccount ? FontWeight.w700 : FontWeight.w500,
                                      color: _mode == AuthMode.createAccount ? palette.ink : palette.mutedInk,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 20),

                    // Elegant Error Banner
                    if (errorText != null && errorText.isNotEmpty) ...[
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        decoration: BoxDecoration(
                          color: Colors.red.withOpacity(0.06),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.red.withOpacity(0.25)),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Icon(Icons.info_outline_rounded, color: Colors.red, size: 17),
                            const SizedBox(width: 9),
                            Expanded(
                              child: Text(
                                errorText,
                                style: GoogleFonts.inter(
                                  fontSize: 12.5,
                                  color: Colors.red.shade800,
                                  height: 1.35,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                    ],

                    // Field 1: Email Address
                    Text(
                      'EMAIL ADDRESS',
                      style: GoogleFonts.inter(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.8,
                        color: palette.mutedInk,
                      ),
                    ),
                    const SizedBox(height: 6),
                    TextFormField(
                      key: const Key('email_input_field'),
                      controller: _emailController,
                      keyboardType: TextInputType.emailAddress,
                      autocorrect: false,
                      style: GoogleFonts.inter(fontSize: 14, color: palette.ink),
                      decoration: InputDecoration(
                        hintText: 'alex@example.com',
                        hintStyle: GoogleFonts.inter(fontSize: 13, color: palette.mutedInk.withOpacity(0.4)),
                        prefixIcon: Icon(Icons.mail_outline_rounded, size: 18, color: palette.mutedInk),
                        filled: true,
                        fillColor: palette.surface,
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
                          borderSide: BorderSide(color: palette.ink, width: 1.5),
                        ),
                      ),
                    ),

                    const SizedBox(height: 16),

                    // Field 2: Password
                    Text(
                      'PASSWORD',
                      style: GoogleFonts.inter(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.8,
                        color: palette.mutedInk,
                      ),
                    ),
                    const SizedBox(height: 6),
                    TextFormField(
                      key: const Key('password_input_field'),
                      controller: _passwordController,
                      obscureText: _obscurePassword,
                      style: GoogleFonts.inter(fontSize: 14, color: palette.ink),
                      decoration: InputDecoration(
                        hintText: '••••••••',
                        hintStyle: GoogleFonts.inter(fontSize: 13, color: palette.mutedInk.withOpacity(0.4)),
                        prefixIcon: Icon(Icons.lock_outline_rounded, size: 18, color: palette.mutedInk),
                        suffixIcon: IconButton(
                          key: const Key('toggle_password_visibility'),
                          icon: Icon(
                            _obscurePassword ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                            size: 18,
                            color: palette.mutedInk,
                          ),
                          onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                        ),
                        filled: true,
                        fillColor: palette.surface,
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
                          borderSide: BorderSide(color: palette.ink, width: 1.5),
                        ),
                      ),
                    ),

                    // Additional Fields for Create Account Mode
                    if (_mode == AuthMode.createAccount) ...[
                      const SizedBox(height: 16),
                      Text(
                        'CONFIRM PASSWORD',
                        style: GoogleFonts.inter(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.8,
                          color: palette.mutedInk,
                        ),
                      ),
                      const SizedBox(height: 6),
                      TextFormField(
                        key: const Key('confirm_password_input_field'),
                        controller: _confirmPasswordController,
                        obscureText: _obscureConfirmPassword,
                        style: GoogleFonts.inter(fontSize: 14, color: palette.ink),
                        decoration: InputDecoration(
                          hintText: '••••••••',
                          hintStyle: GoogleFonts.inter(fontSize: 13, color: palette.mutedInk.withOpacity(0.4)),
                          prefixIcon: Icon(Icons.lock_reset_rounded, size: 18, color: palette.mutedInk),
                          suffixIcon: IconButton(
                            key: const Key('toggle_confirm_password_visibility'),
                            icon: Icon(
                              _obscureConfirmPassword ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                              size: 18,
                              color: palette.mutedInk,
                            ),
                            onPressed: () => setState(() => _obscureConfirmPassword = !_obscureConfirmPassword),
                          ),
                          filled: true,
                          fillColor: palette.surface,
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
                            borderSide: BorderSide(color: palette.ink, width: 1.5),
                          ),
                        ),
                      ),

                      const SizedBox(height: 16),
                      Text(
                        'PROFILE NAME',
                        style: GoogleFonts.inter(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.8,
                          color: palette.mutedInk,
                        ),
                      ),
                      const SizedBox(height: 6),
                      TextFormField(
                        key: const Key('profile_name_input_field'),
                        controller: _profileNameController,
                        style: GoogleFonts.inter(fontSize: 14, color: palette.ink),
                        decoration: InputDecoration(
                          hintText: 'Personal Shield',
                          hintStyle: GoogleFonts.inter(fontSize: 13, color: palette.mutedInk.withOpacity(0.4)),
                          prefixIcon: Icon(Icons.shield_outlined, size: 18, color: palette.mutedInk),
                          filled: true,
                          fillColor: palette.surface,
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
                            borderSide: BorderSide(color: palette.ink, width: 1.5),
                          ),
                        ),
                      ),
                    ],

                    const SizedBox(height: 14),

                    // Remember Credentials Toggle
                    InkWell(
                      onTap: () => setState(() => _rememberMe = !_rememberMe),
                      borderRadius: BorderRadius.circular(6),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4.0),
                        child: Row(
                          children: [
                            SizedBox(
                              width: 20,
                              height: 20,
                              child: Checkbox(
                                value: _rememberMe,
                                activeColor: palette.ink,
                                checkColor: palette.canvas,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                                onChanged: (val) => setState(() => _rememberMe = val ?? true),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                'Remember profile and credentials in local database',
                                style: GoogleFonts.inter(
                                  fontSize: 12,
                                  color: palette.mutedInk,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),

                    const SizedBox(height: 24),

                    // Submit Action Button
                    SizedBox(
                      width: double.infinity,
                      height: 48,
                      child: ElevatedButton(
                        key: const Key('submit_auth_button'),
                        onPressed: isBusy ? null : _submit,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: palette.ink,
                          foregroundColor: palette.canvas,
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                        child: isBusy
                            ? SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  valueColor: AlwaysStoppedAnimation<Color>(palette.canvas),
                                ),
                              )
                            : Text(
                                _mode == AuthMode.signIn
                                    ? 'Sign In to FocusDNS'
                                    : 'Create Account & Continue',
                                style: GoogleFonts.inter(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 0.2,
                                ),
                              ),
                      ),
                    ),

                    const SizedBox(height: 16),

                    // Mode Toggle Footer Link
                    Center(
                      child: GestureDetector(
                        key: const Key('toggle_mode_link'),
                        onTap: () {
                          setState(() {
                            _mode = (_mode == AuthMode.signIn) ? AuthMode.createAccount : AuthMode.signIn;
                            _localError = null;
                          });
                        },
                        child: Padding(
                          padding: const EdgeInsets.all(8.0),
                          child: Text(
                            _mode == AuthMode.signIn
                                ? "Don't have an account? Create one"
                                : 'Already have an account? Sign in',
                            style: GoogleFonts.inter(
                              fontSize: 12.5,
                              color: palette.mutedInk,
                              decoration: TextDecoration.underline,
                            ),
                          ),
                        ),
                      ),
                    ),

                    const SizedBox(height: 8),

                    // Offline Guest Access Link
                    Center(
                      child: GestureDetector(
                        onTap: _proceedNext,
                        child: Padding(
                          padding: const EdgeInsets.all(8.0),
                          child: Text(
                            'Continue as Guest (100% Offline Mode)',
                            style: GoogleFonts.inter(
                              fontSize: 12,
                              color: palette.mutedInk.withOpacity(0.7),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
