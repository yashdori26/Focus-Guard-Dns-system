import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Paper Design Theme Tokens & Typography
/// A light, warm, editorial, quiet look that feels like a mindful reading app.
class PaperPalette {
  final Color paper; // Background
  final Color ink; // Primary text & strong rules
  final Color body; // Body reading text
  final Color muted; // Captions, subtitles & eyebrows
  final Color accent; // Forest green primary action
  final Color onAccent; // Text on accent
  final Color danger; // Blocked or warning marker
  final Color hairlineStrong; // 100% ink rule
  final Color hairlineSoft; // Soft section divider
  final Color surface; // Raised surface / sheet

  const PaperPalette({
    required this.paper,
    required this.ink,
    required this.body,
    required this.muted,
    required this.accent,
    required this.onAccent,
    required this.danger,
    required this.hairlineStrong,
    required this.hairlineSoft,
    required this.surface,
  });

  /// Light "Paper" theme (Default)
  static const light = PaperPalette(
    paper: Color(0xFFF6F1E7),
    ink: Color(0xFF1F1B16),
    body: Color(0xFF4A443B),
    muted: Color(0xFF6B6358),
    accent: Color(0xFF2F6B4F),
    onAccent: Colors.white,
    danger: Color(0xFF9B2C1F),
    hairlineStrong: Color(0xFF1F1B16),
    hairlineSoft: Color(0xFFD9D2C3),
    surface: Color(0xFFFBF8F1),
  );

  /// "Paper at night" dark theme
  static const dark = PaperPalette(
    paper: Color(0xFF1A1713),
    ink: Color(0xFFF2EBDD),
    body: Color(0xFFD4CBBB),
    muted: Color(0xFFA89F8F),
    accent: Color(0xFF7FC4A0),
    onAccent: Color(0xFF1A1713),
    danger: Color(0xFFE56A54),
    hairlineStrong: Color(0xFFF2EBDD),
    hairlineSoft: Color(0xFF2E2A24),
    surface: Color(0xFF24201A),
  );

  static PaperPalette of(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return isDark ? dark : light;
  }
}

/// Paper Editorial Typography
class PaperTypography {
  /// Display hero headline (Fraunces 700, 44 / 1.05)
  static TextStyle hero(PaperPalette palette) => GoogleFonts.fraunces(
        fontSize: 44,
        fontWeight: FontWeight.w700,
        height: 1.05,
        color: palette.ink,
        letterSpacing: -0.5,
      );

  /// Big numerals for timers & counts (Fraunces 700, 56–64)
  static TextStyle bigNumeral(PaperPalette palette, {double size = 56}) =>
      GoogleFonts.fraunces(
        fontSize: size,
        fontWeight: FontWeight.w700,
        height: 1.0,
        color: palette.ink,
        letterSpacing: -1.0,
      );

  /// Editorial section titles (Fraunces 500, 28)
  static TextStyle sectionTitle(PaperPalette palette) => GoogleFonts.fraunces(
        fontSize: 28,
        fontWeight: FontWeight.w500,
        height: 1.15,
        color: palette.ink,
        letterSpacing: -0.3,
      );

  /// Subsection title (Fraunces 600, 20)
  static TextStyle subTitle(PaperPalette palette) => GoogleFonts.fraunces(
        fontSize: 20,
        fontWeight: FontWeight.w600,
        color: palette.ink,
        letterSpacing: -0.2,
      );

  /// Body reading text (Inter 400, 16 / 1.5)
  static TextStyle body(PaperPalette palette) => GoogleFonts.inter(
        fontSize: 16,
        fontWeight: FontWeight.w400,
        height: 1.5,
        color: palette.body,
      );

  /// List row item text (Inter 500, 15)
  static TextStyle row(PaperPalette palette) => GoogleFonts.inter(
        fontSize: 15,
        fontWeight: FontWeight.w500,
        height: 1.4,
        color: palette.ink,
      );

  /// Captions and secondary text (Inter 400, 13)
  static TextStyle caption(PaperPalette palette) => GoogleFonts.inter(
        fontSize: 13,
        fontWeight: FontWeight.w400,
        height: 1.4,
        color: palette.muted,
      );

  /// Eyebrow labels (Inter 13, letter-spacing 1.0, UPPERCASE, muted)
  static TextStyle eyebrow(PaperPalette palette) => GoogleFonts.inter(
        fontSize: 13,
        fontWeight: FontWeight.w600,
        letterSpacing: 1.0,
        color: palette.muted,
      );

  /// Primary button text (Inter 600, 15)
  static TextStyle buttonText(PaperPalette palette, {Color? color}) =>
      GoogleFonts.inter(
        fontSize: 15,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.2,
        color: color ?? palette.onAccent,
      );
}

/// Paper ThemeData Definition
class PaperTheme {
  static ThemeData get lightTheme {
    const palette = PaperPalette.light;
    return ThemeData(
      brightness: Brightness.light,
      scaffoldBackgroundColor: palette.paper,
      canvasColor: palette.paper,
      cardColor: palette.surface,
      dividerColor: palette.hairlineSoft,
      colorScheme: ColorScheme.light(
        surface: palette.paper,
        primary: palette.accent,
        onPrimary: palette.onAccent,
        onSurface: palette.ink,
        outline: palette.hairlineSoft,
      ),
      textTheme: GoogleFonts.interTextTheme().apply(
        bodyColor: palette.body,
        displayColor: palette.ink,
      ),
    );
  }

  static ThemeData get darkTheme {
    const palette = PaperPalette.dark;
    return ThemeData(
      brightness: Brightness.dark,
      scaffoldBackgroundColor: palette.paper,
      canvasColor: palette.paper,
      cardColor: palette.surface,
      dividerColor: palette.hairlineSoft,
      colorScheme: ColorScheme.dark(
        surface: palette.paper,
        primary: palette.accent,
        onPrimary: palette.onAccent,
        onSurface: palette.ink,
        outline: palette.hairlineSoft,
      ),
      textTheme: GoogleFonts.interTextTheme().apply(
        bodyColor: palette.body,
        displayColor: palette.ink,
      ),
    );
  }
}
