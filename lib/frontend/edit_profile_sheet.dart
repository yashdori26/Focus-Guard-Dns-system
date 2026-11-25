import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../state_management/providers.dart';
import 'theme/wabi_sabi_theme.dart';
import 'widgets/motion.dart';

/// Minimal profile editor: change your display name, see your email.
class EditProfileSheet extends ConsumerStatefulWidget {
  const EditProfileSheet({super.key});

  @override
  ConsumerState<EditProfileSheet> createState() => _EditProfileSheetState();
}

class _EditProfileSheetState extends ConsumerState<EditProfileSheet> {
  late final TextEditingController _name;
  late final String _initial;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final auth = ref.read(authProvider);
    final settings = ref.read(settingsProvider);
    _initial = auth.activeProfileName.isNotEmpty ? auth.activeProfileName : settings.profileName;
    _name = TextEditingController(text: _initial);
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  bool get _changed => _name.text.trim().isNotEmpty && _name.text.trim() != _initial;

  Future<void> _save() async {
    if (!_changed || _saving) return;
    setState(() => _saving = true);
    final clean = _name.text.trim();
    await ref.read(authProvider.notifier).setActiveProfileName(clean);
    ref.read(settingsProvider.notifier).updateProfileName(clean);
    HapticFeedback.lightImpact();
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final themeMode = ref.watch(themeModeProvider);
    final palette = themeMode == ThemeMode.light ? WabiSabiPalette.light : WabiSabiPalette.dark;
    final auth = ref.watch(authProvider);
    final letter = _name.text.trim().isNotEmpty ? _name.text.trim()[0].toUpperCase() : 'F';

    return AnimatedPadding(
      duration: const Duration(milliseconds: 160),
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        decoration: BoxDecoration(
          color: palette.canvas,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(color: palette.border, borderRadius: BorderRadius.circular(2)))),
            const SizedBox(height: 22),
            FadeSlideIn(
              child: Row(
                children: [
                  Container(
                    width: 56,
                    height: 56,
                    decoration: BoxDecoration(shape: BoxShape.circle, color: palette.surface, border: Border.all(color: palette.border, width: 1.2)),
                    alignment: Alignment.center,
                    child: Text(letter, style: GoogleFonts.fraunces(fontSize: 24, fontWeight: FontWeight.w700, color: palette.ink)),
                  ),
                  const SizedBox(width: 14),
                  Text('Edit profile', style: GoogleFonts.fraunces(fontSize: 26, fontWeight: FontWeight.w700, color: palette.ink)),
                ],
              ),
            ),
            const SizedBox(height: 22),
            FadeSlideIn(
              delay: FadeSlideIn.stagger(1),
              child: TextField(
                key: const Key('edit_profile_name_field'),
                controller: _name,
                maxLength: 24,
                textCapitalization: TextCapitalization.words,
                onChanged: (_) => setState(() {}),
                onSubmitted: (_) => _save(),
                cursorColor: palette.ink,
                style: GoogleFonts.inter(fontSize: 20, fontWeight: FontWeight.w500, color: palette.ink),
                decoration: InputDecoration(
                  labelText: 'Name',
                  counterText: '',
                  labelStyle: GoogleFonts.inter(fontSize: 14, color: palette.mutedInk),
                  enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: palette.border, width: 1.5)),
                  focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: palette.ink, width: 2)),
                ),
              ),
            ),
            if (auth.email != null && auth.email!.isNotEmpty) ...[
              const SizedBox(height: 18),
              FadeSlideIn(
                delay: FadeSlideIn.stagger(2),
                child: Row(
                  children: [
                    Icon(Icons.mail_outline_rounded, size: 18, color: palette.mutedInk),
                    const SizedBox(width: 10),
                    Expanded(child: Text(auth.email!, overflow: TextOverflow.ellipsis, style: GoogleFonts.inter(fontSize: 15, color: palette.mutedInk))),
                    if (auth.isEmailVerified) Icon(Icons.verified_rounded, size: 18, color: palette.accent),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 24),
            FadeSlideIn(
              delay: FadeSlideIn.stagger(3),
              child: PressableScale(
                onTap: _changed ? _save : null,
                child: AnimatedContainer(
                  key: const Key('edit_profile_save_button'),
                  duration: const Duration(milliseconds: 180),
                  height: 54,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(color: _changed ? palette.ink : palette.border, borderRadius: BorderRadius.circular(27)),
                  child: _saving
                      ? SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.2, color: palette.canvas))
                      : Text('Save', style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.w700, color: _changed ? palette.canvas : palette.mutedInk)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
