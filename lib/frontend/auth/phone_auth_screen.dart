import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../state_management/providers.dart';
import '../theme/wabi_sabi_theme.dart';
import 'views/otp_verification_view.dart';
import 'views/phone_input_view.dart';
import 'views/profile_setup_view.dart';

/// Master Full-Screen Authentication Scaffold
/// Runs before launching the home screen until user is logged in.
class PhoneAuthScreen extends ConsumerWidget {
  const PhoneAuthScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = WabiSabiPalette.of(context);
    final auth = ref.watch(authProvider);
    final themeMode = ref.watch(themeModeProvider);

    int stepIndex = 0;
    if (auth.currentStep == AuthStep.otpVerification) {
      stepIndex = 1;
    } else if (auth.currentStep == AuthStep.profileSetup) {
      stepIndex = 2;
    }

    return Scaffold(
      backgroundColor: palette.canvas,
      body: SafeArea(
        child: Column(
          children: [
            const SizedBox(height: 12),

            // Top Header: Brand, Back Button & Theme Switcher
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  if (stepIndex > 0)
                    IconButton(
                      icon: Icon(Icons.arrow_back_ios_new_rounded, size: 18, color: palette.ink),
                      onPressed: () {
                        if (stepIndex == 1) {
                          ref.read(authProvider.notifier).goToStep(AuthStep.phoneInput);
                        } else if (stepIndex == 2) {
                          ref.read(authProvider.notifier).goToStep(AuthStep.otpVerification);
                        }
                      },
                    )
                  else
                    Row(
                      children: [
                        Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: palette.ink,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'FOCUS DNS',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 2.0,
                            color: palette.ink,
                          ),
                        ),
                      ],
                    ),

                  // Step Indicator Dots
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
                                  ? palette.ink.withValues(alpha: 0.4)
                                  : palette.border,
                        ),
                      );
                    }),
                  ),

                  // Light / Dark Theme Mode Toggle
                  IconButton(
                    icon: Icon(
                      themeMode == ThemeMode.light
                          ? Icons.dark_mode_outlined
                          : Icons.light_mode_outlined,
                      color: palette.ink,
                      size: 20,
                    ),
                    onPressed: () {
                      ref.read(themeModeProvider.notifier).toggle();
                    },
                  ),
                ],
              ),
            ),

            const SizedBox(height: 10),
            Divider(height: 1, color: palette.border.withValues(alpha: 0.5)),

            // Body Multi-Step Switcher
            Expanded(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 300),
                transitionBuilder: (child, animation) {
                  return FadeTransition(
                    opacity: animation,
                    child: SlideTransition(
                      position: Tween<Offset>(
                        begin: const Offset(0.04, 0),
                        end: Offset.zero,
                      ).animate(animation),
                      child: child,
                    ),
                  );
                },
                child: _buildCurrentView(auth.currentStep),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCurrentView(AuthStep step) {
    switch (step) {
      case AuthStep.emailInput:
      case AuthStep.phoneInput:
        return const PhoneInputView(key: ValueKey('step_phone'));
      case AuthStep.codeVerification:
      case AuthStep.otpVerification:
        return const OtpVerificationView(key: ValueKey('step_otp'));
      case AuthStep.profileSetup:
        return const ProfileSetupView(key: ValueKey('step_profile'));
      case AuthStep.permissionSetup:
      case AuthStep.initializing:
      case AuthStep.authenticated:
        return const Center(
          child: CircularProgressIndicator(),
        );
    }
  }
}
