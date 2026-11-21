import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../state_management/providers.dart';
import '../theme/wabi_sabi_theme.dart';

enum AuthMode { signIn, createAccount }

/// Master Email & Password Authentication Screen
/// Presents clean Sign In and Create Account tabs with persistent sessions.
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
  final _profileNameController = TextEditingController();

  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;
  String? _localError;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    _profileNameController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
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

    if (_mode == AuthMode.createAccount) {
      final confirm = _confirmPasswordController.text;
      if (password != confirm) {
        setState(() => _localError = 'Passwords do not match.');
        return;
      }
    }

    if (_mode == AuthMode.signIn) {
      final res = await ref.read(authProvider.notifier).loginWithEmail(email, password);
      if (res['success'] != true && mounted) {
        setState(() => _localError = res['error']?.toString() ?? 'Sign in failed. Check your credentials.');
      }
    } else {
      final profileName = _profileNameController.text.trim();
      final res = await ref.read(authProvider.notifier).registerWithEmail(
        email,
        password,
        profileName.isNotEmpty ? profileName : 'Personal Shield',
      );
      if (res['success'] != true && mounted) {
        setState(() => _localError = res['error']?.toString() ?? 'Registration failed. Please try again.');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = WabiSabiPalette.of(context);
    final themeMode = ref.watch(themeModeProvider);
    final auth = ref.watch(authProvider);

    final errorText = _localError ?? auth.errorMessage;

    return Scaffold(
      backgroundColor: palette.canvas,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Top Navigation Bar
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 28,
                          height: 28,
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
                                fontSize: 14,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'FOCUS DNS',
                          style: GoogleFonts.inter(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 2.0,
                            color: palette.ink,
                          ),
                        ),
                      ],
                    ),
                    IconButton(
                      icon: Icon(
                        themeMode == ThemeMode.light
                            ? Icons.dark_mode_outlined
                            : Icons.light_mode_outlined,
                        color: palette.ink,
                        size: 20,
                      ),
                      tooltip: 'Toggle Theme',
                      onPressed: () => ref.read(themeModeProvider.notifier).toggle(),
                    ),
                  ],
                ),

                const SizedBox(height: 32),

                // Eyebrow
                Text(
                  _mode == AuthMode.signIn ? 'WELCOME BACK' : 'GET STARTED',
                  style: GoogleFonts.inter(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.4,
                    color: palette.mutedInk,
                  ),
                ),
                const SizedBox(height: 6),

                // Headline
                Text(
                  _mode == AuthMode.signIn
                      ? 'Sign in to FocusDNS.'
                      : 'Create your account.',
                  style: GoogleFonts.fraunces(
                    fontSize: 28,
                    fontWeight: FontWeight.w700,
                    color: palette.ink,
                    letterSpacing: -0.5,
                  ),
                ),
                const SizedBox(height: 6),

                // Subtitle
                Text(
                  _mode == AuthMode.signIn
                      ? 'Access your DNS profiles, blacklists and focus analytics.'
                      : 'Sync your IP automatically and protect all your apps seamlessly.',
                  style: GoogleFonts.inter(
                    fontSize: 13,
                    color: palette.mutedInk,
                    height: 1.35,
                  ),
                ),

                const SizedBox(height: 24),

                // Mode Switcher Capsule (Sign In / Create Account)
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
                              borderRadius: BorderRadius.circular(7),
                              border: _mode == AuthMode.signIn
                                  ? Border.all(color: palette.hairlineSoft)
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
                      const SizedBox(width: 4),
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
                              borderRadius: BorderRadius.circular(7),
                              border: _mode == AuthMode.createAccount
                                  ? Border.all(color: palette.hairlineSoft)
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

                const SizedBox(height: 24),

                // Error Banner
                if (errorText != null && errorText.isNotEmpty) ...[
                  Container(
                    key: const Key('auth_error_banner'),
                    padding: const EdgeInsets.all(12),
                    margin: const EdgeInsets.only(bottom: 16),
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

                // Email Field
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
                    prefixIcon: Icon(Icons.alternate_email_rounded, size: 18, color: palette.mutedInk),
                    filled: true,
                    fillColor: palette.surface,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
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
                      borderSide: BorderSide(color: palette.ink, width: 1.5),
                    ),
                  ),
                ),

                const SizedBox(height: 16),

                // Password Field
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
                    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
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
                      borderSide: BorderSide(color: palette.ink, width: 1.5),
                    ),
                  ),
                ),

                // Additional Fields for Create Account
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
                      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
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
                        borderSide: BorderSide(color: palette.ink, width: 1.5),
                      ),
                    ),
                  ),

                  const SizedBox(height: 16),
                  Text(
                    'INITIAL PROFILE NAME',
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
                      prefixIcon: Icon(Icons.shield_outlined, size: 18, color: palette.mutedInk),
                      filled: true,
                      fillColor: palette.surface,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
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
                        borderSide: BorderSide(color: palette.ink, width: 1.5),
                      ),
                    ),
                  ),
                ],

                const SizedBox(height: 28),

                // Submit Button
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton(
                    key: const Key('submit_auth_button'),
                    onPressed: auth.isLoading ? null : _submit,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: palette.ink,
                      foregroundColor: palette.canvas,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    child: auth.isLoading
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
                                : 'Create Account & Start Protection',
                            style: GoogleFonts.inter(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.2,
                            ),
                          ),
                  ),
                ),

                const SizedBox(height: 20),

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
              ],
            ),
          ),
        ),
      ),
    );
  }
}
