import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/app_storage_service.dart';

class ThemeModeNotifier extends StateNotifier<ThemeMode> {
  ThemeModeNotifier() : super(_initialTheme()) {
    _loadPersistedTheme();
  }

  static ThemeMode _initialTheme() {
    try {
      final p = Uri.base.queryParameters['theme']?.toLowerCase();
      if (p == 'light') return ThemeMode.light;
      if (p == 'dark') return ThemeMode.dark;
    } catch (_) {}
    return ThemeMode.light;
  }

  Future<void> _loadPersistedTheme() async {
    final saved = await AppStorageService.loadThemeMode();
    if (!mounted) return;
    if (saved != null) {
      if (saved == 'light') state = ThemeMode.light;
      if (saved == 'dark') state = ThemeMode.dark;
    }
  }

  void toggle() {
    final next = state == ThemeMode.dark ? ThemeMode.light : ThemeMode.dark;
    state = next;
    AppStorageService.saveThemeMode(next == ThemeMode.light ? 'light' : 'dark');
  }

  void setMode(ThemeMode mode) {
    state = mode;
    AppStorageService.saveThemeMode(mode == ThemeMode.light ? 'light' : 'dark');
  }
}

final themeModeProvider =
    StateNotifierProvider<ThemeModeNotifier, ThemeMode>((ref) {
  return ThemeModeNotifier();
});
