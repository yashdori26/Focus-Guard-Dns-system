import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme/wabi_sabi_theme.dart';
import '../widgets/motion.dart';
import 'smtp_settings_sheet.dart';

/// Clean back bar matching the Wabi-Sabi app design with optional SMTP setup shortcut
class AuthBackBar extends StatelessWidget {
  final WabiSabiPalette palette;
  final VoidCallback? onBack;
  final bool showSmtpGear;

  const AuthBackBar({
    super.key,
    required this.palette,
    this.onBack,
    this.showSmtpGear = true,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 16, 0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          IconButton(
            key: const Key('auth_back_button'),
            onPressed: onBack ?? () => Navigator.of(context).maybePop(),
            icon: Icon(Icons.arrow_back_rounded, size: 24, color: palette.ink),
          ),
          if (showSmtpGear)
            IconButton(
              key: const Key('auth_smtp_setup_button'),
              tooltip: 'Email Sender Setup',
              onPressed: () => SmtpSettingsSheet.show(context),
              icon: Icon(Icons.tune_rounded, size: 22, color: palette.mutedInk),
            ),
        ],
      ),
    );
  }
}

/// Standardized Fraunces Editorial Headline matching the rest of FocusDNS
class AuthHeadline extends StatelessWidget {
  final WabiSabiPalette palette;
  final String text;
  const AuthHeadline(this.text, {super.key, required this.palette});

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: GoogleFonts.fraunces(
        fontSize: 28,
        height: 1.15,
        fontWeight: FontWeight.w700,
        color: palette.ink,
        letterSpacing: -0.4,
      ),
    );
  }
}

/// Tactile Card-Style Text Field matching FocusDNS forms and bottom sheets
class AuthCardTextField extends StatelessWidget {
  final TextEditingController controller;
  final String hintText;
  final IconData? icon;
  final bool autofocus;
  final bool obscureText;
  final TextInputType keyboardType;
  final TextInputAction textInputAction;
  final List<String>? autofillHints;
  final Widget? suffixIcon;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final Key? fieldKey;

  const AuthCardTextField({
    super.key,
    required this.controller,
    required this.hintText,
    this.icon,
    this.autofocus = false,
    this.obscureText = false,
    this.keyboardType = TextInputType.text,
    this.textInputAction = TextInputAction.done,
    this.autofillHints,
    this.suffixIcon,
    this.onChanged,
    this.onSubmitted,
    this.fieldKey,
  });

  @override
  Widget build(BuildContext context) {
    final palette = WabiSabiPalette.of(context);
    return Container(
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: palette.border, width: 1.2),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
      child: TextField(
        key: fieldKey,
        controller: controller,
        autofocus: autofocus,
        obscureText: obscureText,
        keyboardType: keyboardType,
        textInputAction: textInputAction,
        autofillHints: autofillHints,
        onChanged: onChanged,
        onSubmitted: onSubmitted,
        cursorColor: palette.ink,
        style: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.w500, color: palette.ink),
        decoration: InputDecoration(
          border: InputBorder.none,
          hintText: hintText,
          hintStyle: GoogleFonts.inter(fontSize: 14, color: palette.mutedInk.withOpacity(0.6)),
          icon: icon != null ? Icon(icon, size: 20, color: palette.mutedInk) : null,
          suffixIcon: suffixIcon,
        ),
      ),
    );
  }
}

/// Full-width tactile Wabi-Sabi button used across the whole application
class WabiSabiButton extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  final bool loading;
  final bool enabled;
  final bool filled;
  final Color? backgroundColor;
  final Color? textColor;
  final Key? buttonKey;

  const WabiSabiButton({
    super.key,
    required this.label,
    required this.onTap,
    this.loading = false,
    this.enabled = true,
    this.filled = true,
    this.backgroundColor,
    this.textColor,
    this.buttonKey,
  });

  @override
  Widget build(BuildContext context) {
    final palette = WabiSabiPalette.of(context);
    final active = enabled && !loading;
    final bg = backgroundColor ?? (filled ? palette.ink : Colors.transparent);
    final fg = textColor ?? (filled ? palette.canvas : palette.ink);

    return PressableScale(
      onTap: active ? onTap : null,
      child: AnimatedContainer(
        key: buttonKey ?? const Key('auth_next_button'),
        duration: const Duration(milliseconds: 180),
        width: double.infinity,
        height: 52,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: active ? bg : palette.border.withOpacity(0.5),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: active ? (filled ? bg : palette.border) : palette.border,
            width: 1.2,
          ),
        ),
        child: loading
            ? SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2.2, color: fg),
              )
            : Text(
                label,
                style: GoogleFonts.inter(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: active ? fg : palette.mutedInk,
                  letterSpacing: 0.2,
                ),
              ),
      ),
    );
  }
}

/// Backward compatibility alias for PillButton
class PillButton extends StatelessWidget {
  final WabiSabiPalette palette;
  final String label;
  final bool filled;
  final VoidCallback onTap;
  const PillButton({super.key, required this.palette, required this.label, required this.onTap, this.filled = true});

  @override
  Widget build(BuildContext context) {
    return WabiSabiButton(
      label: label,
      onTap: onTap,
      filled: filled,
    );
  }
}

/// Backward compatibility alias for RoundNextButton
class RoundNextButton extends StatelessWidget {
  final WabiSabiPalette palette;
  final bool enabled;
  final bool loading;
  final VoidCallback onTap;
  const RoundNextButton({super.key, required this.palette, required this.enabled, required this.onTap, this.loading = false});

  @override
  Widget build(BuildContext context) {
    return WabiSabiButton(
      label: 'Continue',
      onTap: onTap,
      enabled: enabled,
      loading: loading,
    );
  }
}
