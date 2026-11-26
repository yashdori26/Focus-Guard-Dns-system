import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../state_management/providers.dart';
import '../theme/wabi_sabi_theme.dart';
import '../widgets/motion.dart';
import 'auth_widgets.dart';
import 'otp_screen.dart';

final RegExp _emailPattern = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]{2,}$');

/// Clean, tactile Wabi-Sabi Email Entry Screen
class EmailEntryScreen extends ConsumerStatefulWidget {
  final bool isNewAccount;
  const EmailEntryScreen({super.key, required this.isNewAccount});

  @override
  ConsumerState<EmailEntryScreen> createState() => _EmailEntryScreenState();
}

class _EmailEntryScreenState extends ConsumerState<EmailEntryScreen> {
  final TextEditingController _email = TextEditingController();
  final TextEditingController _password = TextEditingController();
  bool _obscurePassword = true;
  bool _loading = false;
  String? _error;
  int _shake = 0;

  bool get _valid {
    final emailOk = _emailPattern.hasMatch(_email.text.trim());
    if (!widget.isNewAccount) return emailOk;
    return emailOk && _password.text.length >= 6;
  }

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_valid || _loading) {
      if (widget.isNewAccount && _emailPattern.hasMatch(_email.text.trim()) && _password.text.length < 6) {
        setState(() {
          _error = 'Password must be at least 6 characters.';
          _shake++;
        });
      }
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() {
      _loading = true;
      _error = null;
    });

    final res = await ref.read(authProvider.notifier).sendEmailVerificationCode(
          _email.text.trim(),
          isNewAccount: widget.isNewAccount,
        );
    if (!mounted) return;

    final ok = res['success'] == true;

    if (!ok) {
      setState(() {
        _loading = false;
        _shake++;
        _error = res['error']?.toString() ?? 'Could not send verification email. Please try again.';
      });
      return;
    }

    setState(() => _loading = false);
    Navigator.of(context).push(appRoute(OtpScreen(
      email: _email.text.trim().toLowerCase(),
      isNewAccount: widget.isNewAccount,
      password: widget.isNewAccount ? _password.text : null,
    )));
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
                        widget.isNewAccount ? "Create your\naccount" : 'Welcome back.\nEnter your email',
                        palette: palette,
                      ),
                    ),
                    const SizedBox(height: 8),
                    FadeSlideIn(
                      delay: FadeSlideIn.stagger(1),
                      child: Text(
                        widget.isNewAccount
                            ? "Set a password and we'll send a 6-digit code to verify your email."
                            : "We'll send a 6-digit verification code to confirm it's you. No password required.",
                        style: GoogleFonts.inter(fontSize: 14, height: 1.45, color: palette.mutedInk),
                      ),
                    ),
                    const SizedBox(height: 28),
                    FadeSlideIn(
                      delay: FadeSlideIn.stagger(2),
                      child: Shake(
                        shakeKey: _shake,
                        child: AuthCardTextField(
                          fieldKey: const Key('auth_email_field'),
                          controller: _email,
                          autofocus: true,
                          keyboardType: TextInputType.emailAddress,
                          textInputAction: widget.isNewAccount ? TextInputAction.next : TextInputAction.done,
                          autofillHints: const [AutofillHints.email],
                          hintText: 'name@example.com',
                          icon: Icons.alternate_email_rounded,
                          onChanged: (_) {
                            if (_error != null) setState(() => _error = null);
                            setState(() {});
                          },
                          onSubmitted: (_) {
                            if (!widget.isNewAccount) _submit();
                          },
                          suffixIcon: _email.text.isNotEmpty
                              ? IconButton(
                                  icon: Icon(Icons.clear, size: 18, color: palette.mutedInk),
                                  onPressed: () {
                                    _email.clear();
                                    setState(() {});
                                  },
                                )
                              : null,
                        ),
                      ),
                    ),
                    if (widget.isNewAccount) ...[
                      const SizedBox(height: 14),
                      FadeSlideIn(
                        delay: FadeSlideIn.stagger(3),
                        child: AuthCardTextField(
                          fieldKey: const Key('auth_password_field'),
                          controller: _password,
                          obscureText: _obscurePassword,
                          hintText: 'Password (min 6 characters)',
                          icon: Icons.lock_outline_rounded,
                          textInputAction: TextInputAction.done,
                          onChanged: (_) {
                            if (_error != null) setState(() => _error = null);
                            setState(() {});
                          },
                          onSubmitted: (_) => _submit(),
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
                    ],
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
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 20),
              child: WabiSabiButton(
                buttonKey: const Key('auth_next_button'),
                label: 'Send Verification Code',
                enabled: _valid,
                loading: _loading,
                onTap: _submit,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
