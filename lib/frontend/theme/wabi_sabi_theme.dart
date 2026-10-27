import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class WabiSabiPalette {
  final Color canvas;
  final Color surface;
  final Color border;
  final Color ink;
  final Color mutedInk;
  final Color subtleInk;
  final Color sealActive;
  final Color sealActiveText;
  final Color sealStrict;
  final Color sealStrictText;
  final Color strictAccent;
  final Color chipBg;

  const WabiSabiPalette({
    required this.canvas,
    required this.surface,
    required this.border,
    required this.ink,
    required this.mutedInk,
    required this.subtleInk,
    required this.sealActive,
    required this.sealActiveText,
    required this.sealStrict,
    required this.sealStrictText,
    required this.strictAccent,
    required this.chipBg,
  });

  static const dark = WabiSabiPalette(
    canvas: Color(0xFF141413),
    surface: Color(0xFF1F1E1D),
    border: Color(0xFF292826),
    ink: Color(0xFFEDEDE8),
    mutedInk: Color(0xFFA8A69E),
    subtleInk: Color(0xFF7E7C74),
    sealActive: Color(0xFFEDEDE8),
    sealActiveText: Color(0xFF141413),
    sealStrict: Color(0xFF1E1D1B),
    sealStrictText: Color(0xFFEDEDE8),
    strictAccent: Color(0xFFE11D48),
    chipBg: Color(0xFF1C1C1A),
  );

  static const light = WabiSabiPalette(
    canvas: Color(0xFFF5F4F0),
    surface: Color(0xFFEBE9E2),
    border: Color(0xFFE4E2DC),
    ink: Color(0xFF1E1E1C),
    mutedInk: Color(0xFF5A5852),
    subtleInk: Color(0xFF6E6C66),
    sealActive: Color(0xFF1E1E1C),
    sealActiveText: Color(0xFFF5F4F0),
    sealStrict: Color(0xFFE5E3DC),
    sealStrictText: Color(0xFF1E1E1C),
    strictAccent: Color(0xFFE11D48),
    chipBg: Color(0xFFE4E2DC),
  );

  static WabiSabiPalette of(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return isDark ? dark : light;
  }
}

class WabiSabiTheme {
  static ThemeData get darkTheme {
    final base = ThemeData(
      brightness: Brightness.dark,
      scaffoldBackgroundColor: WabiSabiPalette.dark.canvas,
      canvasColor: WabiSabiPalette.dark.canvas,
      cardColor: WabiSabiPalette.dark.surface,
      dividerColor: WabiSabiPalette.dark.border,
      colorScheme: const ColorScheme.dark(
        surface: Color(0xFF141413),
        primary: Color(0xFFEDEDE8),
        onPrimary: Color(0xFF141413),
        onSurface: Color(0xFFEDEDE8),
        outline: Color(0xFF292826),
      ),
    );
    return base.copyWith(
      textTheme: GoogleFonts.plusJakartaSansTextTheme(base.textTheme).apply(
        bodyColor: WabiSabiPalette.dark.ink,
        displayColor: WabiSabiPalette.dark.ink,
      ),
    );
  }

  static ThemeData get lightTheme {
    final base = ThemeData(
      brightness: Brightness.light,
      scaffoldBackgroundColor: WabiSabiPalette.light.canvas,
      canvasColor: WabiSabiPalette.light.canvas,
      cardColor: WabiSabiPalette.light.surface,
      dividerColor: WabiSabiPalette.light.border,
      colorScheme: const ColorScheme.light(
        surface: Color(0xFFF5F4F0),
        primary: Color(0xFF1E1E1C),
        onPrimary: Color(0xFFF5F4F0),
        onSurface: Color(0xFF1E1E1C),
        outline: Color(0xFFE4E2DC),
      ),
    );
    return base.copyWith(
      textTheme: GoogleFonts.plusJakartaSansTextTheme(base.textTheme).apply(
        bodyColor: WabiSabiPalette.light.ink,
        displayColor: WabiSabiPalette.light.ink,
      ),
    );
  }
}

/// Cohesive typography scale for Wabi-Sabi Charcoal Extreme Minimalism
class WabiSabiTypography {
  static TextStyle header(WabiSabiPalette palette) => GoogleFonts.plusJakartaSans(
        fontSize: 20,
        fontWeight: FontWeight.w700,
        color: palette.ink,
        letterSpacing: -0.4,
      );

  static TextStyle cardTitle(WabiSabiPalette palette) => GoogleFonts.plusJakartaSans(
        fontSize: 15,
        fontWeight: FontWeight.w700,
        color: palette.ink,
        letterSpacing: -0.2,
      );

  static TextStyle sectionHeader(WabiSabiPalette palette) => GoogleFonts.plusJakartaSans(
        fontSize: 11,
        fontWeight: FontWeight.w700,
        color: palette.mutedInk,
        letterSpacing: 1.0,
      );

  static TextStyle body(WabiSabiPalette palette) => GoogleFonts.plusJakartaSans(
        fontSize: 13,
        fontWeight: FontWeight.w500,
        color: palette.ink,
        height: 1.45,
      );

  static TextStyle subtitle(WabiSabiPalette palette) => GoogleFonts.plusJakartaSans(
        fontSize: 12.5,
        fontWeight: FontWeight.w400,
        color: palette.mutedInk,
        height: 1.4,
      );

  static TextStyle metric(WabiSabiPalette palette) => GoogleFonts.plusJakartaSans(
        fontSize: 34,
        fontWeight: FontWeight.w800,
        color: palette.ink,
        letterSpacing: -0.8,
      );

  static TextStyle badge(WabiSabiPalette palette, {Color? color}) => GoogleFonts.plusJakartaSans(
        fontSize: 10.5,
        fontWeight: FontWeight.w700,
        color: color ?? palette.mutedInk,
        letterSpacing: 0.6,
      );

  static TextStyle button(WabiSabiPalette palette, {Color? color}) => GoogleFonts.plusJakartaSans(
        fontSize: 12,
        fontWeight: FontWeight.w700,
        color: color ?? palette.canvas,
        letterSpacing: 0.2,
      );
}
