import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../state_management/providers.dart';
import '../../theme/wabi_sabi_theme.dart';
import '../../widgets/motion.dart';

/// Plain-language privacy policy. Describes what stays on the device and the few
/// things that do leave it, so users can make an informed choice.
class PrivacyPolicyScreen extends ConsumerWidget {
  const PrivacyPolicyScreen({super.key});

  static const List<List<String>> _sections = [
    [
      'What stays on your phone',
      'Your block rules, categories, allow and deny lists, focus sessions, query history, statistics and settings are stored in a database on this device. FocusDNS does not upload them or use them for ads.',
    ],
    [
      'Your email',
      'We use your email only to sign you in with a one-time code and to recognise your account. We do not sell it or share it for marketing.',
    ],
    [
      'DNS lookups',
      'To load a site that is not blocked, FocusDNS forwards the lookup to a public DNS resolver, the same step your phone does without FocusDNS. Blocked lookups never leave your phone.',
    ],
    [
      'Permissions we ask for',
      'VPN: to filter DNS on this device only. Accessibility: to close restricted apps and feeds. Battery: so protection keeps running in the background. We do not read your messages, passwords or screen contents.',
    ],
    [
      'Your control',
      'Log out any time and your local settings stay. Delete Account removes your account, profiles, rules and history from this device.',
    ],
    [
      'Questions',
      'If this policy changes, you will see the update here before it takes effect.',
    ],
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(themeModeProvider);
    final palette = themeMode == ThemeMode.light ? WabiSabiPalette.light : WabiSabiPalette.dark;

    return Scaffold(
      backgroundColor: palette.canvas,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
              child: IconButton(
                key: const Key('privacy_back_button'),
                onPressed: () => Navigator.of(context).pop(),
                icon: Icon(Icons.chevron_left_rounded, size: 32, color: palette.ink),
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
                children: [
                  FadeSlideIn(
                    child: Text('Privacy policy',
                        style: GoogleFonts.fraunces(fontSize: 34, height: 1.12, fontWeight: FontWeight.w700, color: palette.ink, letterSpacing: -0.6)),
                  ),
                  const SizedBox(height: 8),
                  FadeSlideIn(
                    delay: FadeSlideIn.stagger(1),
                    child: Text('The short version: your focus data stays on your phone.',
                        style: GoogleFonts.inter(fontSize: 15, height: 1.45, color: palette.mutedInk)),
                  ),
                  const SizedBox(height: 24),
                  for (var i = 0; i < _sections.length; i++)
                    FadeSlideIn(
                      delay: FadeSlideIn.stagger(i + 2),
                      child: Padding(
                        padding: const EdgeInsets.only(bottom: 22),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(_sections[i][0], style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.w700, color: palette.ink)),
                            const SizedBox(height: 6),
                            Text(_sections[i][1], style: GoogleFonts.inter(fontSize: 14.5, height: 1.5, color: palette.mutedInk)),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Opens the policy with the shared page transition.
void openPrivacyPolicy(BuildContext context) {
  Navigator.of(context).push(appRoute(const PrivacyPolicyScreen()));
}
