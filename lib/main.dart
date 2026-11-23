import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:focus_dns/models/app_models.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'frontend/home_screen.dart';
import 'frontend/screens/onboarding/onboarding_screen.dart';
import 'frontend/theme/wabi_sabi_theme.dart';
import 'services/auth_storage_service.dart';
import 'state_management/providers.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final prefs = await SharedPreferences.getInstance();
  final bool hasCompletedOnboarding = prefs.getBool('focus_onboarding_completed') ?? false;

  runApp(ProviderScope(
    child: FocusDNSMobileApp(
      home: hasCompletedOnboarding ? const FocusDNSHomeScreen() : const OnboardingScreen(),
    ),
  ));
}

class FocusDNSMobileApp extends ConsumerWidget {
  final Widget? home;
  const FocusDNSMobileApp({super.key, this.home});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(themeModeProvider);

    return MaterialApp(
      title: 'FocusDNS',
      debugShowCheckedModeBanner: false,
      theme: WabiSabiTheme.lightTheme,
      darkTheme: WabiSabiTheme.darkTheme,
      themeMode: themeMode,
      home: home ?? const FocusDNSHomeScreen(),
    );
  }
}
