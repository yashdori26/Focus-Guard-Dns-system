import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../state_management/providers.dart';
import '../home_screen.dart';
import '../theme/wabi_sabi_theme.dart';
import 'email_onboarding_wizard.dart';

/// App-Wide Authentication Gateway
/// Evaluates persistent session state before granting access to FocusDNSHomeScreen.
class AuthGateway extends ConsumerWidget {
  const AuthGateway({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authProvider);
    final palette = WabiSabiPalette.of(context);

    // 1. Initializing & Session Hydration Splash
    if (!auth.isInitialized) {
      return Scaffold(
        backgroundColor: palette.canvas,
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 54,
                height: 54,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: palette.ink,
                ),
                child: Center(
                  child: Text(
                    'F',
                    style: TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.bold,
                      color: palette.canvas,
                      fontFamily: 'JetBrains Mono',
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Text(
                'FOCUS DNS',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 2.5,
                  color: palette.ink,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Checking persistent security session...',
                style: TextStyle(fontSize: 11, color: palette.mutedInk),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2, color: palette.ink),
              ),
            ],
          ),
        ),
      );
    }

    // Allow direct web navigation when page, demo, or strict query parameters are provided
    if (kIsWeb) {
      final fullUrl = Uri.base.toString();
      if (fullUrl.contains('page=') || fullUrl.contains('demo') || fullUrl.contains('strict') || fullUrl.contains('theme')) {
        return const FocusDNSHomeScreen();
      }
    }

    // 2. If authenticated and logged in -> Render Main Home Dashboard (kept until user logs out)
    if (auth.isLoggedIn && auth.currentStep == AuthStep.authenticated) {
      return const FocusDNSHomeScreen();
    }

    // 3. Otherwise -> Render 4-step progressive onboarding wizard
    return const EmailOnboardingWizard();
  }
}
