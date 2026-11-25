import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../state_management/providers.dart';
import '../home_screen.dart';
import '../screens/onboarding/onboarding_screen.dart';
import '../theme/wabi_sabi_theme.dart';
import '../widgets/motion.dart';
import 'auth_widgets.dart';

/// Length of the emailed code. Keep in sync with the server (see server_otp_patch).
const int kEmailOtpLength = 6;

/// Hinge-style code entry: boxes, auto-submit, shake on a wrong code, resend timer.
class OtpScreen extends ConsumerStatefulWidget {
  final String email;
  final bool isNewAccount;
  const OtpScreen({super.key, required this.email, required this.isNewAccount});

  @override
  ConsumerState<OtpScreen> createState() => _OtpScreenState();
}

class _OtpScreenState extends ConsumerState<OtpScreen> {
  final TextEditingController _code = TextEditingController();
  final FocusNode _focus = FocusNode();
  bool _verifying = false;
  String? _error;
  int _shake = 0;
  int _secondsLeft = 30;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _focus.addListener(() {
      if (mounted) setState(() {});
    });
    _startTimer();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _code.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _startTimer() {
    _timer?.cancel();
    setState(() => _secondsLeft = 30);
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return t.cancel();
      if (_secondsLeft <= 1) {
        t.cancel();
      }
      setState(() => _secondsLeft = (_secondsLeft - 1).clamp(0, 999));
    });
  }

  Future<void> _verify() async {
    if (_verifying || _code.text.length != kEmailOtpLength) return;
    setState(() {
      _verifying = true;
      _error = null;
    });
    final res = await ref.read(authProvider.notifier).verifyEmail4DigitCode(_code.text);
    if (!mounted) return;

    if (res['success'] != true) {
      _code.clear();
      setState(() {
        _verifying = false;
        _shake++;
        _error = res['error']?.toString() ?? 'That code is not right. Try again.';
      });
      _focus.requestFocus();
      return;
    }

    HapticFeedback.lightImpact();
    final prefs = await SharedPreferences.getInstance();
    final onboarded = prefs.getBool('focus_onboarding_completed') ?? false;
    if (!mounted) return;
    final next = (!widget.isNewAccount && onboarded) ? const FocusDNSHomeScreen() : const OnboardingScreen();
    Navigator.of(context).pushAndRemoveUntil(appRoute(next), (route) => false);
  }

  Future<void> _resend() async {
    if (_secondsLeft > 0) return;
    final res = await ref.read(authProvider.notifier).sendEmailVerificationCode(widget.email, isNewAccount: widget.isNewAccount);
    if (!mounted) return;
    if (res['success'] == true) {
      _startTimer();
      setState(() => _error = null);
    } else {
      setState(() => _error = res['error']?.toString() ?? 'Could not resend the code.');
    }
  }

  Widget _boxes(WabiSabiPalette palette) {
    final text = _code.text;
    return Stack(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: List.generate(kEmailOtpLength, (i) {
            final filled = i < text.length;
            final active = i == text.length && _focus.hasFocus;
            return AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              width: 46,
              height: 60,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: _error != null ? Colors.red.shade600 : (active || filled ? palette.ink : palette.border), width: active ? 2 : 1.4),
              ),
              child: AnimatedScale(
                scale: filled ? 1 : 0.6,
                duration: const Duration(milliseconds: 140),
                child: Text(filled ? text[i] : '', style: GoogleFonts.inter(fontSize: 26, fontWeight: FontWeight.w700, color: palette.ink)),
              ),
            );
          }),
        ),
        // Invisible field receives the typing (and SMS/email autofill).
        Positioned.fill(
          child: Opacity(
            opacity: 0.0,
            child: TextField(
              key: const Key('auth_otp_field'),
              controller: _code,
              focusNode: _focus,
              autofocus: true,
              keyboardType: TextInputType.number,
              autofillHints: const [AutofillHints.oneTimeCode],
              inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(kEmailOtpLength)],
              enableInteractiveSelection: false,
              showCursor: false,
              onChanged: (_) {
                setState(() => _error = null);
                if (_code.text.length == kEmailOtpLength) _verify();
              },
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final themeMode = ref.watch(themeModeProvider);
    final palette = themeMode == ThemeMode.light ? WabiSabiPalette.light : WabiSabiPalette.dark;
    final canResend = _secondsLeft == 0;
    final mm = '0:${_secondsLeft.toString().padLeft(2, '0')}';

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
                    FadeSlideIn(child: AuthHeadline('Enter your\ncode', palette: palette)),
                    const SizedBox(height: 10),
                    FadeSlideIn(
                      delay: FadeSlideIn.stagger(1),
                      child: Text('We emailed a $kEmailOtpLength-digit code to ${widget.email}.',
                          style: GoogleFonts.inter(fontSize: 15, height: 1.45, color: palette.mutedInk)),
                    ),
                    const SizedBox(height: 30),
                    FadeSlideIn(delay: FadeSlideIn.stagger(2), child: Shake(shakeKey: _shake, child: _boxes(palette))),
                    const SizedBox(height: 16),
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 220),
                      child: _error != null
                          ? Text(_error!, key: const ValueKey('err'), style: GoogleFonts.inter(fontSize: 13.5, fontWeight: FontWeight.w600, color: Colors.red.shade700))
                          : const SizedBox.shrink(key: ValueKey('noerr')),
                    ),
                    const SizedBox(height: 24),
                    GestureDetector(
                      key: const Key('auth_resend_button'),
                      onTap: canResend ? _resend : null,
                      child: Text(
                        canResend ? 'Resend code' : 'Resend code in $mm',
                        style: GoogleFonts.inter(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: canResend ? palette.ink : palette.mutedInk,
                          decoration: canResend ? TextDecoration.underline : TextDecoration.none,
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    GestureDetector(
                      onTap: () => Navigator.of(context).maybePop(),
                      child: Text('Wrong email? Go back', style: GoogleFonts.inter(fontSize: 14, color: palette.mutedInk)),
                    ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 20),
              child: Align(
                alignment: Alignment.centerRight,
                child: RoundNextButton(palette: palette, enabled: _code.text.length == kEmailOtpLength, loading: _verifying, onTap: _verify),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
