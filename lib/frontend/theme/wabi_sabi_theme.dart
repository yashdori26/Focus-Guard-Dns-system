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
  final Color safeAccent;
  final Color warningAccent;
  final Color chipBg;
  final Color body;
  final Color hairlineStrong;
  final Color hairlineSoft;

  Color get accent => safeAccent;

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
    this.safeAccent = const Color(0xFF2F6B4F),
    this.warningAccent = const Color(0xFFB45309),
    this.body = const Color(0xFF4A443B),
    this.hairlineStrong = const Color(0xFF1F1B16),
    this.hairlineSoft = const Color(0xFFD9D2C3),
    required this.chipBg,
  });

  static const dark = WabiSabiPalette(
    canvas: Color(0xFF1A1713),
    surface: Color(0xFF24201A),
    border: Color(0xFF2E2A24),
    ink: Color(0xFFF2EBDD),
    mutedInk: Color(0xFFA89F8F),
    subtleInk: Color(0xFF7E7668),
    sealActive: Color(0xFF7FC4A0),
    sealActiveText: Color(0xFF1A1713),
    sealStrict: Color(0xFF24201A),
    sealStrictText: Color(0xFFF2EBDD),
    strictAccent: Color(0xFFE56A54),
    safeAccent: Color(0xFF7FC4A0),
    warningAccent: Color(0xFFF59E0B),
    body: Color(0xFFD4CBBB),
    hairlineStrong: Color(0xFFF2EBDD),
    hairlineSoft: Color(0xFF2E2A24),
    chipBg: Color(0xFF24201A),
  );

  static const light = WabiSabiPalette(
    canvas: Color(0xFFF6F1E7),
    surface: Color(0xFFFBF8F1),
    border: Color(0xFFD9D2C3),
    ink: Color(0xFF1F1B16),
    mutedInk: Color(0xFF6B6358),
    subtleInk: Color(0xFF8C8476),
    sealActive: Color(0xFF2F6B4F),
    sealActiveText: Colors.white,
    sealStrict: Color(0xFFFBF8F1),
    sealStrictText: Color(0xFF1F1B16),
    strictAccent: Color(0xFF9B2C1F),
    safeAccent: Color(0xFF2F6B4F),
    warningAccent: Color(0xFFB45309),
    body: Color(0xFF4A443B),
    hairlineStrong: Color(0xFF1F1B16),
    hairlineSoft: Color(0xFFD9D2C3),
    chipBg: Color(0xFFEFE8DB),
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
      dividerColor: WabiSabiPalette.dark.hairlineSoft,
      colorScheme: const ColorScheme.dark(
        surface: Color(0xFF1A1713),
        primary: Color(0xFF7FC4A0),
        onPrimary: Color(0xFF1A1713),
        onSurface: Color(0xFFF2EBDD),
        outline: Color(0xFF2E2A24),
      ),
    );
    return base.copyWith(
      pageTransitionsTheme: const PageTransitionsTheme(builders: {
        TargetPlatform.android: FadeForwardsPageTransitionsBuilder(),
        TargetPlatform.iOS: FadeForwardsPageTransitionsBuilder(),
      }),
      textTheme: GoogleFonts.interTextTheme(base.textTheme).apply(
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
      dividerColor: WabiSabiPalette.light.hairlineSoft,
      colorScheme: const ColorScheme.light(
        surface: Color(0xFFF6F1E7),
        primary: Color(0xFF2F6B4F),
        onPrimary: Colors.white,
        onSurface: Color(0xFF1F1B16),
        outline: Color(0xFFD9D2C3),
      ),
    );
    return base.copyWith(
      pageTransitionsTheme: const PageTransitionsTheme(builders: {
        TargetPlatform.android: FadeForwardsPageTransitionsBuilder(),
        TargetPlatform.iOS: FadeForwardsPageTransitionsBuilder(),
      }),
      textTheme: GoogleFonts.interTextTheme(base.textTheme).apply(
        bodyColor: WabiSabiPalette.light.ink,
        displayColor: WabiSabiPalette.light.ink,
      ),
    );
  }
}

/// Cohesive typography scale for Paper Editorial Theme
class WabiSabiTypography {
  static TextStyle header(WabiSabiPalette palette) => GoogleFonts.fraunces(
        fontSize: 22,
        fontWeight: FontWeight.w700,
        color: palette.ink,
        letterSpacing: -0.3,
      );

  static TextStyle hero(WabiSabiPalette palette) => GoogleFonts.fraunces(
        fontSize: 44,
        fontWeight: FontWeight.w700,
        height: 1.05,
        color: palette.ink,
        letterSpacing: -0.5,
      );

  static TextStyle sectionTitle(WabiSabiPalette palette) => GoogleFonts.fraunces(
        fontSize: 28,
        fontWeight: FontWeight.w500,
        color: palette.ink,
        letterSpacing: -0.3,
      );

  static TextStyle cardTitle(WabiSabiPalette palette) => GoogleFonts.fraunces(
        fontSize: 16,
        fontWeight: FontWeight.w600,
        color: palette.ink,
        letterSpacing: -0.2,
      );

  static TextStyle sectionHeader(WabiSabiPalette palette) => GoogleFonts.inter(
        fontSize: 13,
        fontWeight: FontWeight.w600,
        color: palette.mutedInk,
        letterSpacing: 1.0,
      );

  static TextStyle body(WabiSabiPalette palette) => GoogleFonts.inter(
        fontSize: 16,
        fontWeight: FontWeight.w400,
        color: palette.body,
        height: 1.5,
      );

  static TextStyle subtitle(WabiSabiPalette palette) => GoogleFonts.inter(
        fontSize: 13,
        fontWeight: FontWeight.w400,
        color: palette.mutedInk,
        height: 1.4,
      );

  static TextStyle metric(WabiSabiPalette palette) => GoogleFonts.fraunces(
        fontSize: 56,
        fontWeight: FontWeight.w700,
        color: palette.ink,
        letterSpacing: -1.0,
      );

  static TextStyle badge(WabiSabiPalette palette, {Color? color}) => GoogleFonts.inter(
        fontSize: 11,
        fontWeight: FontWeight.w600,
        color: color ?? palette.mutedInk,
        letterSpacing: 0.5,
      );

  static TextStyle button(WabiSabiPalette palette, {Color? color}) => GoogleFonts.inter(
        fontSize: 15,
        fontWeight: FontWeight.w600,
        color: color ?? Colors.white,
        letterSpacing: 0.2,
      );
}
