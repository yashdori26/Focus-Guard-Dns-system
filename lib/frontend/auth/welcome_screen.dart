import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../state_management/providers.dart';
import '../screens/legal/privacy_policy_screen.dart';
import '../theme/wabi_sabi_theme.dart';
import '../widgets/motion.dart';
import 'auth_widgets.dart';
import 'email_entry_screen.dart';

/// Cohesive Wabi-Sabi Welcome Screen matching the FocusDNS design system
class WelcomeScreen extends ConsumerWidget {
  const WelcomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(themeModeProvider);
    final palette = themeMode == ThemeMode.light ? WabiSabiPalette.light : WabiSabiPalette.dark;

    return Scaffold(
      backgroundColor: palette.canvas,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            children: [
              const Spacer(flex: 3),
              // Tactile Shield Emblem matching FocusDNS App Icon
              FadeSlideIn(
                child: Container(
                  width: 84,
                  height: 84,
                  decoration: BoxDecoration(
                    color: palette.surface,
                    borderRadius: BorderRadius.circular(22),
                    border: Border.all(color: palette.border, width: 1.5),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.04),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Icon(Icons.shield_rounded, size: 44, color: palette.accent),
                ),
              ),
              const SizedBox(height: 24),
              // Fraunces Header & Subtitle
              FadeSlideIn(
                delay: FadeSlideIn.stagger(1),
                child: Text(
                  'FocusDNS',
                  style: GoogleFonts.fraunces(
                    fontSize: 34,
                    fontWeight: FontWeight.w700,
                    color: palette.ink,
                    letterSpacing: -0.5,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              FadeSlideIn(
                delay: FadeSlideIn.stagger(2),
                child: Text(
                  'Private DNS & Threat Defense',
                  style: GoogleFonts.inter(
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                    color: palette.mutedInk,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              // Security Pill Badge
              FadeSlideIn(
                delay: FadeSlideIn.stagger(3),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                  decoration: BoxDecoration(
                    color: palette.surface,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: palette.border),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 7,
                        height: 7,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: palette.accent,
                        ),
                      ),
                      const SizedBox(width: 7),
                      Text(
                        '100% On-Device · Zero-Log Shield',
                        style: GoogleFonts.inter(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                          color: palette.mutedInk,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const Spacer(flex: 4),
              // Action Buttons
              FadeSlideIn(
                delay: FadeSlideIn.stagger(4),
                child: Column(
                  children: [
                    WabiSabiButton(
                      buttonKey: const Key('welcome_create_button'),
                      label: 'Create Account',
                      onTap: () => Navigator.of(context).push(appRoute(const EmailEntryScreen(isNewAccount: true))),
                    ),
                    const SizedBox(height: 12),
                    WabiSabiButton(
                      buttonKey: const Key('welcome_signin_button'),
                      label: 'Sign In',
                      filled: false,
                      onTap: () => Navigator.of(context).push(appRoute(const EmailEntryScreen(isNewAccount: false))),
                    ),
                    const SizedBox(height: 20),
                    Text.rich(
                      TextSpan(
                        style: GoogleFonts.inter(fontSize: 12, height: 1.5, color: palette.mutedInk),
                        children: [
                          const TextSpan(text: 'By continuing, you agree that your DNS data stays strictly on your phone. Read our '),
                          WidgetSpan(
                            alignment: PlaceholderAlignment.baseline,
                            baseline: TextBaseline.alphabetic,
                            child: GestureDetector(
                              key: const Key('welcome_privacy_link'),
                              onTap: () => openPrivacyPolicy(context),
                              child: Text(
                                'Privacy Policy',
                                style: GoogleFonts.inter(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  color: palette.ink,
                                  decoration: TextDecoration.underline,
                                ),
                              ),
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
    );
  }
}
