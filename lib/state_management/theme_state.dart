import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class ThemeModeNotifier extends StateNotifier<ThemeMode> {
  ThemeModeNotifier() : super(_initialTheme());

  static ThemeMode _initialTheme() {
    try {
      final p = Uri.base.queryParameters['theme']?.toLowerCase();
      if (p == 'light') return ThemeMode.light;
      if (p == 'dark') return ThemeMode.dark;
    } catch (_) {}
    return ThemeMode.dark;
  }

  void toggle() {
    state = state == ThemeMode.dark ? ThemeMode.light : ThemeMode.dark;
  }

  void setMode(ThemeMode mode) {
    state = mode;
  }
}

final themeModeProvider =
    StateNotifierProvider<ThemeModeNotifier, ThemeMode>((ref) {
  return ThemeModeNotifier();
});
