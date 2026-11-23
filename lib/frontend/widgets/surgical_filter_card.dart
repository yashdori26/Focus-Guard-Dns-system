import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../state_management/providers.dart';
import '../theme/wabi_sabi_theme.dart';

class SurgicalFilterCard extends ConsumerWidget {
  const SurgicalFilterCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final surgical = ref.watch(surgicalFilterProvider);
    final palette = WabiSabiPalette.of(context);

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: palette.border, width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: palette.ink.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(Icons.content_cut_rounded, color: palette.ink, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Surgical Feed vs Chat Filtering',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: palette.ink,
                        letterSpacing: -0.3,
                      ),
                    ),
                    Text(
                      'Blackhole infinite video feeds while keeping DMs & educational search alive',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 12,
                        color: palette.mutedInk,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // INSTAGRAM SECTION
          _buildAppSection(
            appTitle: 'Instagram (Reels vs DMs)',
            icon: '📸',
            palette: palette,
            children: [
              _buildSwitchRow(
                title: 'Block Reels & Explore Feed',
                desc: 'Blackholes reels video CDN delivery nodes',
                value: surgical.blockInstagramReels,
                onChanged: (v) => ref.read(surgicalFilterProvider.notifier).toggleInstagramReels(v),
                palette: palette,
              ),
              _buildSwitchRow(
                title: 'Keep Direct Messages Active',
                desc: 'Whitelists direct messaging gateways',
                value: surgical.allowInstagramDms,
                onChanged: (v) => ref.read(surgicalFilterProvider.notifier).toggleInstagramDms(v),
                palette: palette,
              ),
            ],
          ),

          const SizedBox(height: 12),

          // YOUTUBE SECTION
          _buildAppSection(
            appTitle: 'YouTube (Shorts vs Educational)',
            icon: '▶️',
            palette: palette,
            children: [
              _buildSwitchRow(
                title: 'Block YouTube Shorts URLs',
                desc: 'Kills infinite vertical video autoplay',
                value: surgical.blockYouTubeShorts,
                onChanged: (v) => ref.read(surgicalFilterProvider.notifier).toggleYouTubeShorts(v),
                palette: palette,
              ),
              _buildSwitchRow(
                title: 'Disable Algorithmic Recommendations',
                desc: 'Suppresses autoplay suggestions; search still works',
                value: surgical.blockYouTubeRecommendations,
                onChanged: (v) => ref.read(surgicalFilterProvider.notifier).toggleYouTubeRecommendations(v),
                palette: palette,
              ),
            ],
          ),

          const SizedBox(height: 12),

          // REDDIT SECTION
          _buildAppSection(
            appTitle: 'Reddit (Infinite Feed vs Subreddits)',
            icon: '👾',
            palette: palette,
            children: [
              _buildSwitchRow(
                title: 'Block Popular & Home Infinite Feeds',
                desc: 'Stops doomscrolling r/all and algorithmic feeds',
                value: surgical.blockRedditFeed,
                onChanged: (v) => ref.read(surgicalFilterProvider.notifier).toggleRedditFeed(v),
                palette: palette,
              ),
              _buildSwitchRow(
                title: 'Keep Chat & Direct Messages Active',
                desc: 'Allows direct messages with peers and colleagues',
                value: surgical.allowRedditDms,
                onChanged: (v) => ref.read(surgicalFilterProvider.notifier).toggleRedditDms(v),
                palette: palette,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildAppSection({
    required String appTitle,
    required String icon,
    required WabiSabiPalette palette,
    required List<Widget> children,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: palette.canvas,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: palette.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(icon, style: const TextStyle(fontSize: 16)),
              const SizedBox(width: 8),
              Text(
                appTitle,
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  color: palette.ink,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ...children,
        ],
      ),
    );
  }

  Widget _buildSwitchRow({
    required String title,
    required String desc,
    required bool value,
    required ValueChanged<bool> onChanged,
    required WabiSabiPalette palette,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: palette.ink,
                  ),
                ),
                Text(
                  desc,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 10.5,
                    color: palette.mutedInk,
                  ),
                ),
              ],
            ),
          ),
          Switch.adaptive(
            value: value,
            onChanged: onChanged,
            activeColor: palette.ink,
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
        ],
      ),
    );
  }
}
