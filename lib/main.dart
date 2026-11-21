import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:focus_dns/models/app_models.dart';
import 'frontend/auth/auth_gateway.dart';
import 'frontend/theme/wabi_sabi_theme.dart';
import 'state_management/providers.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const ProviderScope(child: FocusDNSMobileApp()));
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
      home: home ?? const AuthGateway(),
    );
  }
}
