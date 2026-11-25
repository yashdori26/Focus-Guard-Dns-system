import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../state_management/providers.dart';
import '../theme/wabi_sabi_theme.dart';
import '../widgets/motion.dart';
import 'auth_widgets.dart';
import 'otp_screen.dart';

final RegExp _emailPattern = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]{2,}$');

/// One question per screen: "What's your email?" then we email a one-time code.
class EmailEntryScreen extends ConsumerStatefulWidget {
  final bool isNewAccount;
  const EmailEntryScreen({super.key, required this.isNewAccount});

  @override
  ConsumerState<EmailEntryScreen> createState() => _EmailEntryScreenState();
}

class _EmailEntryScreenState extends ConsumerState<EmailEntryScreen> {
  final TextEditingController _email = TextEditingController();
  bool _loading = false;
  String? _error;
  int _shake = 0;

  bool get _valid => _emailPattern.hasMatch(_email.text.trim());

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_valid || _loading) return;
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
    final devOtp = res['dev_otp']?.toString();
    if (kDebugMode && devOtp != null) debugPrint('[FocusDNS] dev verification code: $devOtp');

    // The server reports whether the email really went out. Without delivery (and without a
    // dev code) the user could never finish, so say so instead of showing a code box.
    final undelivered = ok && res['smtp_delivered'] == false && devOtp == null;
    if (!ok || undelivered) {
      setState(() {
        _loading = false;
        _shake++;
        _error = undelivered
            ? 'We could not email a code right now. Please try again in a moment.'
            : (res['error']?.toString() ?? 'Something went wrong. Please try again.');
      });
      return;
    }

    setState(() => _loading = false);
    Navigator.of(context).push(appRoute(OtpScreen(email: _email.text.trim().toLowerCase(), isNewAccount: widget.isNewAccount)));
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
                padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    FadeSlideIn(child: AuthHeadline(widget.isNewAccount ? "What's your\nemail?" : 'Welcome back.\nWhat\'s your email?', palette: palette)),
                    const SizedBox(height: 28),
                    FadeSlideIn(
                      delay: FadeSlideIn.stagger(2),
                      child: Shake(
                        shakeKey: _shake,
                        child: TextField(
                          key: const Key('auth_email_field'),
                          controller: _email,
                          autofocus: true,
                          keyboardType: TextInputType.emailAddress,
                          textInputAction: TextInputAction.done,
                          autofillHints: const [AutofillHints.email],
                          autocorrect: false,
                          cursorColor: palette.ink,
                          onChanged: (_) => setState(() => _error = null),
                          onSubmitted: (_) => _submit(),
                          style: GoogleFonts.inter(fontSize: 24, fontWeight: FontWeight.w500, color: palette.ink),
                          decoration: InputDecoration(
                            hintText: 'name@email.com',
                            hintStyle: GoogleFonts.inter(fontSize: 24, fontWeight: FontWeight.w500, color: palette.mutedInk.withValues(alpha: 0.5)),
                            enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: palette.border, width: 1.5)),
                            focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: palette.ink, width: 2)),
                            contentPadding: const EdgeInsets.symmetric(vertical: 10),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 220),
                      child: _error != null
                          ? Text(_error!, key: const ValueKey('err'), style: GoogleFonts.inter(fontSize: 13.5, height: 1.4, color: Colors.red.shade700, fontWeight: FontWeight.w600))
                          : Text(
                              "We'll email you a code to confirm it's you. No password needed.",
                              key: const ValueKey('hint'),
                              style: GoogleFonts.inter(fontSize: 13.5, height: 1.4, color: palette.mutedInk),
                            ),
                    ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 20),
              child: Align(
                alignment: Alignment.centerRight,
                child: RoundNextButton(palette: palette, enabled: _valid, loading: _loading, onTap: _submit),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
