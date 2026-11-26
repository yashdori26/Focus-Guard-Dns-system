import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:focus_dns/models/app_models.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'backend/blocker_service.dart';
import 'frontend/auth/welcome_screen.dart';
import 'frontend/home_screen.dart';
import 'frontend/screens/onboarding/onboarding_screen.dart';
import 'frontend/theme/wabi_sabi_theme.dart';
import 'services/auth_storage_service.dart';
import 'state_management/providers.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final prefs = await SharedPreferences.getInstance();

  final hasCompletedOnboarding = prefs.getBool('focus_onboarding_completed') ?? false;
  final isLoggedIn = prefs.getBool('focus_dns_auth_is_logged_in') ?? false;

  // Determine initial launch screen:
  // 1. If onboarding has been completed or user is logged in: launch directly into HomeScreen!
  // 2. Otherwise: show WelcomeScreen.
  Widget initialScreen;
  if (hasCompletedOnboarding || isLoggedIn) {
    initialScreen = const FocusDNSHomeScreen();
  } else {
    initialScreen = const WelcomeScreen();
  }

  // Draw first frame immediately — zero blocking on IPC, platform channels, or SQLite
  runApp(ProviderScope(
    child: FocusDNSMobileApp(
      home: initialScreen,
    ),
  ));

  // Dual-layer persistence sync in background microtask: Reconcile with native SQLite LocalDb (focusdns.db)
  // Non-blocking so app never shows a white screen on startup or restart.
  Future.microtask(() async {
    try {
      final dbOnboarding = await FocusDnsBlockerManager.getKv('focus_onboarding_completed', '0');
      if (dbOnboarding == '1' && !hasCompletedOnboarding) {
        await prefs.setBool('focus_onboarding_completed', true);
      }

      final dbLoggedIn = await FocusDnsBlockerManager.getKv('focus_dns_auth_is_logged_in', '');
      if (dbLoggedIn == 'true' && !isLoggedIn) {
        await prefs.setBool('focus_dns_auth_is_logged_in', true);
      }

      final dbProfileName = await FocusDnsBlockerManager.getKv('focus_dns_auth_profile_name', '');
      if (dbProfileName.isNotEmpty) {
        final currentName = prefs.getString('focus_dns_auth_profile_name');
        if (currentName == null || currentName.isEmpty) {
          await prefs.setString('focus_dns_auth_profile_name', dbProfileName);
        }
      }
    } catch (e) {
      debugPrint('[Main] SQLite synchronization background notice: $e');
    }
  });
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
