import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../state_management/providers.dart';
import '../screens/legal/privacy_policy_screen.dart';
import '../theme/wabi_sabi_theme.dart';
import '../widgets/motion.dart';
import 'auth_widgets.dart';
import 'email_entry_screen.dart';

/// Hinge-style welcome: logo, one line of copy, Create account / Sign in.
class WelcomeScreen extends ConsumerStatefulWidget {
  const WelcomeScreen({super.key});

  @override
  ConsumerState<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends ConsumerState<WelcomeScreen> with SingleTickerProviderStateMixin {
  late final AnimationController _drift = AnimationController(vsync: this, duration: const Duration(seconds: 9))..repeat();

  @override
  void dispose() {
    _drift.dispose();
    super.dispose();
  }

  Widget _orb(WabiSabiPalette palette, double size, double phase, Alignment base, double opacity) {
    return AnimatedBuilder(
      animation: _drift,
      builder: (_, __) {
        final t = _drift.value * 2 * math.pi + phase;
        return Align(
          alignment: Alignment(base.x + 0.12 * math.sin(t), base.y + 0.1 * math.cos(t)),
          child: Container(
            width: size,
            height: size,
            decoration: BoxDecoration(shape: BoxShape.circle, color: palette.accent.withValues(alpha: opacity)),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final themeMode = ref.watch(themeModeProvider);
    final palette = themeMode == ThemeMode.light ? WabiSabiPalette.light : WabiSabiPalette.dark;

    return Scaffold(
      backgroundColor: palette.canvas,
      body: Stack(
        children: [
          _orb(palette, 260, 0, const Alignment(-1.1, -0.9), 0.10),
          _orb(palette, 200, 2.1, const Alignment(1.2, -0.2), 0.08),
          _orb(palette, 240, 4.2, const Alignment(-0.8, 0.8), 0.07),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Column(
                children: [
                  const Spacer(flex: 3),
                  TweenAnimationBuilder<double>(
                    tween: Tween<double>(begin: 0.6, end: 1),
                    duration: const Duration(milliseconds: 700),
                    curve: Curves.elasticOut,
                    builder: (_, v, child) => Transform.scale(scale: v, child: child),
                    child: Container(
                      width: 92,
                      height: 92,
                      decoration: BoxDecoration(
                        color: palette.ink,
                        borderRadius: BorderRadius.circular(26),
                      ),
                      child: Icon(Icons.shield_outlined, size: 48, color: palette.canvas),
                    ),
                  ),
                  const SizedBox(height: 28),
                  FadeSlideIn(
                    delay: FadeSlideIn.stagger(3),
                    child: Text('FocusDNS',
                        style: GoogleFonts.fraunces(fontSize: 44, fontWeight: FontWeight.w700, color: palette.ink, letterSpacing: -1)),
                  ),
                  const SizedBox(height: 10),
                  FadeSlideIn(
                    delay: FadeSlideIn.stagger(5),
                    child: Text('Take your attention back.',
                        textAlign: TextAlign.center,
                        style: GoogleFonts.inter(fontSize: 17, color: palette.mutedInk)),
                  ),
                  const Spacer(flex: 4),
                  FadeSlideIn(
                    delay: FadeSlideIn.stagger(7),
                    child: Column(
                      children: [
                        PillButton(
                          key: const Key('welcome_create_button'),
                          palette: palette,
                          label: 'Create account',
                          onTap: () => Navigator.of(context).push(appRoute(const EmailEntryScreen(isNewAccount: true))),
                        ),
                        const SizedBox(height: 12),
                        PillButton(
                          key: const Key('welcome_signin_button'),
                          palette: palette,
                          label: 'Sign in',
                          filled: false,
                          onTap: () => Navigator.of(context).push(appRoute(const EmailEntryScreen(isNewAccount: false))),
                        ),
                        const SizedBox(height: 18),
                        Text.rich(
                          TextSpan(
                            style: GoogleFonts.inter(fontSize: 12.5, height: 1.5, color: palette.mutedInk),
                            children: [
                              const TextSpan(text: 'By continuing you agree that your focus data stays on this phone. Read how we handle data in our '),
                              WidgetSpan(
                                alignment: PlaceholderAlignment.baseline,
                                baseline: TextBaseline.alphabetic,
                                child: GestureDetector(
                                  key: const Key('welcome_privacy_link'),
                                  onTap: () => openPrivacyPolicy(context),
                                  child: Text('Privacy Policy',
                                      style: GoogleFonts.inter(fontSize: 12.5, fontWeight: FontWeight.w700, color: palette.ink, decoration: TextDecoration.underline)),
                                ),
                              ),
                              const TextSpan(text: '.'),
                            ],
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 16),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
