import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../services/email_otp_service.dart';
import '../../state_management/providers.dart';
import '../theme/wabi_sabi_theme.dart';
import '../widgets/motion.dart';
import 'auth_widgets.dart';
import 'otp_screen.dart';
import 'smtp_settings_sheet.dart';

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
  bool _loading = false;
  String? _error;
  bool _needsSmtpSetup = false;
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
      _needsSmtpSetup = false;
    });

    final res = await ref.read(authProvider.notifier).sendEmailVerificationCode(
          _email.text.trim(),
          isNewAccount: widget.isNewAccount,
        );
    if (!mounted) return;

    final ok = res['success'] == true;
    final needsSetup = res['needs_smtp_setup'] == true;

    if (!ok) {
      setState(() {
        _loading = false;
        _shake++;
        _needsSmtpSetup = needsSetup;
        _error = res['error']?.toString() ?? 'Could not send verification email. Please try again.';
      });
      return;
    }

    setState(() => _loading = false);
    Navigator.of(context).push(appRoute(OtpScreen(
      email: _email.text.trim().toLowerCase(),
      isNewAccount: widget.isNewAccount,
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
                        widget.isNewAccount ? "What's your\nemail address?" : 'Welcome back.\nEnter your email',
                        palette: palette,
                      ),
                    ),
                    const SizedBox(height: 8),
                    FadeSlideIn(
                      delay: FadeSlideIn.stagger(1),
                      child: Text(
                        "We'll send a 6-digit verification code to confirm it's you. No password required.",
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
                          textInputAction: TextInputAction.done,
                          autofillHints: const [AutofillHints.email],
                          hintText: 'name@example.com',
                          icon: Icons.alternate_email_rounded,
                          onChanged: (_) {
                            if (_error != null) setState(() => _error = null);
                            setState(() {});
                          },
                          onSubmitted: (_) => _submit(),
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
                    const SizedBox(height: 16),
                    if (_error != null)
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.red.shade900.withOpacity(0.08),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: Colors.red.shade400.withOpacity(0.4)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
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
                            if (_needsSmtpSetup) ...[
                              const SizedBox(height: 10),
                              GestureDetector(
                                onTap: () => SmtpSettingsSheet.show(context),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                  decoration: BoxDecoration(
                                    color: palette.surface,
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(color: palette.border),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(Icons.tune_rounded, size: 16, color: palette.ink),
                                      const SizedBox(width: 8),
                                      Text(
                                        'Configure Gmail / SMTP Sender',
                                        style: GoogleFonts.inter(fontSize: 12.5, fontWeight: FontWeight.w700, color: palette.ink),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
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
