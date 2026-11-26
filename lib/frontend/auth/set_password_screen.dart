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
import '../widgets/motion.dart';
import 'auth_widgets.dart';

/// Screen displayed after email is verified in the sign up process.
/// Asks the user to create a password and confirm it.
class SetPasswordScreen extends ConsumerStatefulWidget {
  final String email;
  const SetPasswordScreen({super.key, required this.email});

  @override
  ConsumerState<SetPasswordScreen> createState() => _SetPasswordScreenState();
}

class _SetPasswordScreenState extends ConsumerState<SetPasswordScreen> {
  final TextEditingController _password = TextEditingController();
  final TextEditingController _confirmPassword = TextEditingController();
  bool _obscurePassword = true;
  bool _obscureConfirm = true;
  bool _loading = false;
  String? _error;
  int _shake = 0;

  @override
  void dispose() {
    _password.dispose();
    _confirmPassword.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final pwd = _password.text;
    final confirm = _confirmPassword.text;

    if (pwd.length < 6) {
      setState(() {
        _error = 'Password must be at least 6 characters.';
        _shake++;
      });
      return;
    }

    if (pwd != confirm) {
      setState(() {
        _error = 'Passwords do not match. Please re-enter.';
        _shake++;
      });
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    // Save credentials to local SQLite database and secure storage
    await AuthStorageService.saveCredentials(
      email: widget.email.trim().toLowerCase(),
      password: pwd,
      profileName: widget.email.split('@').first,
    );

    await AuthStorageService.saveSession(
      token: 'session_${DateTime.now().millisecondsSinceEpoch}',
      email: widget.email.trim().toLowerCase(),
      profileId: 'default',
      profileName: widget.email.split('@').first,
      isEmailVerified: true,
    );

    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('focus_dns_auth_is_logged_in', true);
    try {
      await FocusDnsBlockerManager.putKv('focus_dns_auth_is_logged_in', 'true');
    } catch (_) {}

    final onboarded = prefs.getBool('focus_onboarding_completed') ?? false;
    if (!mounted) return;

    final next = onboarded ? const FocusDNSHomeScreen() : const OnboardingScreen();
    Navigator.of(context).pushAndRemoveUntil(appRoute(next), (route) => false);
  }

  @override
  Widget build(BuildContext context) {
    final themeMode = ref.watch(themeModeProvider);
    final palette = themeMode == ThemeMode.light ? WabiSabiPalette.light : WabiSabiPalette.dark;

    return Scaffold(
      backgroundColor: palette.canvas,
      body: SafeArea(
        child: Column(
          children: [
            AuthBackBar(palette: palette),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    FadeSlideIn(
                      child: AuthHeadline(
                        'Create your\npassword',
                        palette: palette,
                      ),
                    ),
                    const SizedBox(height: 8),
                    FadeSlideIn(
                      delay: FadeSlideIn.stagger(1),
                      child: Text(
                        'Email verified! Now set a secure password for ${widget.email}.',
                        style: GoogleFonts.inter(fontSize: 14, height: 1.45, color: palette.mutedInk),
                      ),
                    ),
                    const SizedBox(height: 28),
                    // Password Field
                    FadeSlideIn(
                      delay: FadeSlideIn.stagger(2),
                      child: Shake(
                        shakeKey: _shake,
                        child: AuthCardTextField(
                          fieldKey: const Key('auth_password_field'),
                          controller: _password,
                          autofocus: true,
                          obscureText: _obscurePassword,
                          hintText: 'Password (min 6 characters)',
                          icon: Icons.lock_outline_rounded,
                          textInputAction: TextInputAction.next,
                          onChanged: (val) {
                            if (_error != null) setState(() => _error = null);
                            setState(() {});
                            if (val.isNotEmpty) {
                              AuthStorageService.saveCredentials(
                                email: widget.email.trim().toLowerCase(),
                                password: val,
                                profileName: widget.email.split('@').first,
                              );
                            }
                          },
                          suffixIcon: IconButton(
                            icon: Icon(
                              _obscurePassword ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                              size: 20,
                              color: palette.mutedInk,
                            ),
                            onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    // Confirm Password Field
                    FadeSlideIn(
                      delay: FadeSlideIn.stagger(3),
                      child: AuthCardTextField(
                        fieldKey: const Key('auth_confirm_password_field'),
                        controller: _confirmPassword,
                        obscureText: _obscureConfirm,
                        hintText: 'Confirm password',
                        icon: Icons.lock_clock_outlined,
                        textInputAction: TextInputAction.done,
                        onChanged: (_) {
                          if (_error != null) setState(() => _error = null);
                          setState(() {});
                        },
                        onSubmitted: (_) => _submit(),
                        suffixIcon: IconButton(
                          icon: Icon(
                            _obscureConfirm ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                            size: 20,
                            color: palette.mutedInk,
                          ),
                          onPressed: () => setState(() => _obscureConfirm = !_obscureConfirm),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    if (_error != null)
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.red.shade900.withOpacity(0.08),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: Colors.red.shade400.withOpacity(0.4)),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.error_outline, size: 16, color: Colors.red.shade700),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                _error!,
                                style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.red.shade700),
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
              child: WabiSabiButton(
                buttonKey: const Key('auth_next_button'),
                label: 'Complete Sign Up',
                loading: _loading,
                enabled: _password.text.length >= 6 && _confirmPassword.text.isNotEmpty,
                onTap: _submit,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
