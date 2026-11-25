import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme/wabi_sabi_theme.dart';
import '../widgets/motion.dart';

/// Back chevron row shared by the Hinge-style auth screens.
class AuthBackBar extends StatelessWidget {
  final WabiSabiPalette palette;
  final VoidCallback? onBack;
  const AuthBackBar({super.key, required this.palette, this.onBack});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
      child: Align(
        alignment: Alignment.centerLeft,
        child: IconButton(
          key: const Key('auth_back_button'),
          onPressed: onBack ?? () => Navigator.of(context).maybePop(),
          icon: Icon(Icons.chevron_left_rounded, size: 32, color: palette.ink),
        ),
      ),
    );
  }
}

class AuthHeadline extends StatelessWidget {
  final WabiSabiPalette palette;
  final String text;
  const AuthHeadline(this.text, {super.key, required this.palette});

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: GoogleFonts.fraunces(fontSize: 34, height: 1.12, fontWeight: FontWeight.w700, color: palette.ink, letterSpacing: -0.6),
    );
  }
}

/// Round arrow button (bottom-right on Hinge). Shows a spinner while [loading].
class RoundNextButton extends StatelessWidget {
  final WabiSabiPalette palette;
  final bool enabled;
  final bool loading;
  final VoidCallback onTap;
  const RoundNextButton({super.key, required this.palette, required this.enabled, required this.onTap, this.loading = false});

  @override
  Widget build(BuildContext context) {
    final active = enabled && !loading;
    return PressableScale(
      onTap: active ? onTap : null,
      child: AnimatedContainer(
        key: const Key('auth_next_button'),
        duration: const Duration(milliseconds: 200),
        width: 60,
        height: 60,
        decoration: BoxDecoration(shape: BoxShape.circle, color: enabled ? palette.ink : palette.border),
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 180),
          child: loading
              ? Padding(
                  key: const ValueKey('spin'),
                  padding: const EdgeInsets.all(18),
                  child: CircularProgressIndicator(strokeWidth: 2.4, color: palette.canvas),
                )
              : Icon(Icons.arrow_forward_rounded, key: const ValueKey('arrow'), size: 28, color: enabled ? palette.canvas : palette.mutedInk),
        ),
      ),
    );
  }
}

/// Full-width pill button (Hinge welcome screen).
class PillButton extends StatelessWidget {
  final WabiSabiPalette palette;
  final String label;
  final bool filled;
  final VoidCallback onTap;
  const PillButton({super.key, required this.palette, required this.label, required this.onTap, this.filled = true});

  @override
  Widget build(BuildContext context) {
    return PressableScale(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        height: 56,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: filled ? palette.ink : Colors.transparent,
          borderRadius: BorderRadius.circular(28),
          border: Border.all(color: palette.ink, width: 1.6),
        ),
        child: Text(label, style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.w700, color: filled ? palette.canvas : palette.ink)),
      ),
    );
  }
}
