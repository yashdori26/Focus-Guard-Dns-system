import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'frontend/home_screen.dart';
import 'frontend/theme/wabi_sabi_theme.dart';
import 'state_management/providers.dart';

void main() {
  runApp(const ProviderScope(child: FocusDNSMobileApp()));
}

class FocusDNSMobileApp extends ConsumerWidget {
  const FocusDNSMobileApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(themeModeProvider);

    return MaterialApp(
      title: 'FocusDNS',
      debugShowCheckedModeBanner: false,
      theme: WabiSabiTheme.lightTheme,
      darkTheme: WabiSabiTheme.darkTheme,
      themeMode: themeMode,
      home: const FocusDNSHomeScreen(),
    );
  }
}
