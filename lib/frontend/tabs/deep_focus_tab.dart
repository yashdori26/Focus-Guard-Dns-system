import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../models/app_models.dart';
import '../../state_management/providers.dart';
import '../theme/wabi_sabi_theme.dart';

class DeepFocusTab extends ConsumerWidget {
  const DeepFocusTab({super.key});

  void _showAddWebsiteModal(BuildContext context, WidgetRef ref) {
    final palette = WabiSabiPalette.of(context);
    const available = [
      BlockedItem(
        id: 'netflix',
        name: 'Netflix',
        icon: 'N',
        color: Color(0xFFE50914),
        packages: ['com.netflix.mediaclient', 'com.netflix.ninja'],
      ),
      BlockedItem(
        id: 'youtube',
        name: 'YouTube',
        icon: 'Y',
        color: Color(0xFFFF0000),
        packages: [
          'com.google.android.youtube',
          'com.google.android.apps.youtube.music',
          'com.google.android.apps.youtube.kids',
        ],
      ),
      BlockedItem(
        id: 'tiktok',
        name: 'TikTok',
        icon: 't',
        color: Color(0xFF000000),
        packages: [
          'com.zhiliaoapp.musically',
          'com.ss.android.ugc.trill',
          'com.zhiliaoapp.musically.go',
        ],
      ),
      BlockedItem(
        id: 'instagram',
        name: 'Instagram',
        icon: 'I',
        color: Color(0xFFE1306C),
        packages: [
          'com.instagram.android',
          'com.instagram.lite',
          'com.instagram.barcelona',
        ],
      ),
      BlockedItem(
        id: 'steam',
        name: 'Steam',
        icon: 'S',
        color: Color(0xFF171A21),
        packages: ['com.valvesoftware.android.steam.community'],
      ),
      BlockedItem(
        id: 'whatsapp',
        name: 'WhatsApp',
        icon: 'W',
        color: Color(0xFF25D366),
        packages: ['com.whatsapp', 'com.whatsapp.w4b'],
      ),
      BlockedItem(
        id: 'xbox',
        name: 'Xbox',
        icon: 'X',
        color: Color(0xFF107C10),
        packages: [
          'com.microsoft.xboxone.smartglass',
          'com.microsoft.xboxone.smartglass.beta',
        ],
      ),
      BlockedItem(
        id: 'discord',
        name: 'Discord',
        icon: 'D',
        color: Color(0xFF5865F2),
        packages: ['com.discord'],
      ),
    ];

    showModalBottomSheet(
      context: context,
      backgroundColor: palette.canvas,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return Container(
          padding: const EdgeInsets.all(20),
          height: 400,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Add Website or App',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: palette.ink,
                    ),
                  ),
                  IconButton(
                    icon: Icon(Icons.close, color: palette.mutedInk, size: 20),
                    onPressed: () => Navigator.pop(ctx),
                  ),
                ],
              ),
              Divider(color: palette.border),
              Expanded(
                child: ListView.builder(
                  itemCount: available.length,
                  itemBuilder: (context, i) {
                    final item = available[i];
                    return ListTile(
                      leading: Container(
                        width: 30,
                        height: 30,
                        decoration: BoxDecoration(
                          color: item.color,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Center(
                          child: Text(
                            item.icon,
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ),
                      title: Text(
                        item.name,
                        style: TextStyle(
                          color: palette.ink,
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                        ),
                      ),
                      trailing: ElevatedButton(
                        onPressed: () {
                          ref.read(deepFocusProvider.notifier).addWebsite(item);
                          Navigator.pop(ctx);
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: palette.ink,
                          foregroundColor: palette.canvas,
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                          minimumSize: Size.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        child: const Text('ADD', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  void _showAddCategoryModal(BuildContext context, WidgetRef ref) {
    final palette = WabiSabiPalette.of(context);
    const available = [
      BlockedItem(
        id: 'social',
        name: 'Social Networks',
        description: 'Blocks Facebook, Instagram, TikTok, Reddit, and Twitter/X.',
      ),
      BlockedItem(
        id: 'gaming',
        name: 'Online Gaming',
        description: 'Blocks Steam, PlayStation Network, Xbox Live, and Roblox.',
      ),
      BlockedItem(
        id: 'video',
        name: 'Video Streaming',
        description: 'Blocks YouTube, Netflix, Disney+, Prime Video, and Twitch.',
      ),
      BlockedItem(
        id: 'dating',
        name: 'Dating Services',
        description: 'Blocks all online dating platforms and mobile matchmaking apps.',
      ),
    ];

    showModalBottomSheet(
      context: context,
      backgroundColor: palette.canvas,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return Container(
          padding: const EdgeInsets.all(20),
          height: 400,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Add Category',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: palette.ink,
                    ),
                  ),
                  IconButton(
                    icon: Icon(Icons.close, color: palette.mutedInk, size: 20),
                    onPressed: () => Navigator.pop(ctx),
                  ),
                ],
              ),
              Divider(color: palette.border),
              Expanded(
                child: ListView.builder(
                  itemCount: available.length,
                  itemBuilder: (context, i) {
                    final item = available[i];
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8.0),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  item.name,
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.bold,
                                    color: palette.ink,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  item.description ?? '',
                                  style: TextStyle(fontSize: 11, color: palette.mutedInk),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 12),
                          ElevatedButton(
                            onPressed: () {
                              ref.read(deepFocusProvider.notifier).addCategory(item);
                              Navigator.pop(ctx);
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: palette.ink,
                              foregroundColor: palette.canvas,
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                              minimumSize: Size.zero,
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),
                            child: const Text('ADD', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(deepFocusProvider);
    final strictState = ref.watch(strictModeProvider);
    final palette = WabiSabiPalette.of(context);

    return Column(
      children: [
        _buildListCard(
          context: context,
          palette: palette,
          title: 'Websites, Apps & Games',
          desc: 'Restrict access to specific websites, apps and games.',
          buttonText: 'ADD A WEBSITE, APP OR GAME',
          onPressed: () => _showAddWebsiteModal(context, ref),
          items: state.websites.map((w) {
            return _listItem(
              palette: palette,
              icon: w.icon,
              iconColor: w.color,
              title: w.name,
              onRemove: () {
                if (strictState.isStrict) {
                  ScaffoldMessenger.of(context).clearSnackBars();
                  final mins = (strictState.remainingSeconds / 60).ceil();
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        strictState.remainingSeconds > 0
                            ? '🔒 Strict Mode active ($mins min remaining). Cannot unblock apps until timer expires.'
                            : '🔒 Strict Mode active. Cannot unblock apps until session ends.',
                      ),
                      backgroundColor: palette.surface,
                    ),
                  );
                  return;
                }
                ref.read(deepFocusProvider.notifier).removeWebsite(w.name);
              },
            );
          }).toList(),
        ),
        _buildListCard(
          context: context,
          palette: palette,
          title: 'Categories',
          desc: 'Restrict access to specific categories of websites and apps.',
          buttonText: 'ADD A CATEGORY',
          onPressed: () => _showAddCategoryModal(context, ref),
          items: state.categories.map((c) {
            return _listItem(
              palette: palette,
              title: c.name,
              desc: c.description,
              onRemove: () {
                if (strictState.isStrict) {
                  ScaffoldMessenger.of(context).clearSnackBars();
                  final mins = (strictState.remainingSeconds / 60).ceil();
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        strictState.remainingSeconds > 0
                            ? '🔒 Strict Mode active ($mins min remaining). Cannot unblock categories until timer expires.'
                            : '🔒 Strict Mode active. Cannot unblock categories until session ends.',
                      ),
                      backgroundColor: palette.surface,
                    ),
                  );
                  return;
                }
                ref.read(deepFocusProvider.notifier).removeCategory(c.name);
              },
            );
          }).toList(),
        ),
      ],
    );
  }

  Widget _buildListCard({
    required BuildContext context,
    required WabiSabiPalette palette,
    required String title,
    required String desc,
    required String buttonText,
    required VoidCallback onPressed,
    required List<Widget> items,
  }) {
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
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Text(
                  title,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: palette.ink,
                    letterSpacing: -0.3,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: items.isNotEmpty
                      ? palette.strictAccent.withOpacity(0.12)
                      : palette.canvas,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                    color: items.isNotEmpty
                        ? palette.strictAccent.withOpacity(0.3)
                        : palette.border,
                    width: 1,
                  ),
                ),
                child: Text(
                  items.isNotEmpty ? '${items.length} BLOCKED' : '0 BLOCKED',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.5,
                    color: items.isNotEmpty ? palette.strictAccent : palette.mutedInk,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            desc,
            style: GoogleFonts.plusJakartaSans(
              fontSize: 12.5,
              fontWeight: FontWeight.w400,
              color: palette.mutedInk,
              height: 1.45,
            ),
          ),
          const SizedBox(height: 14),
          if (items.isNotEmpty) ...[
            AnimatedSize(
              duration: const Duration(milliseconds: 250),
              curve: Curves.easeOutCubic,
              child: Column(children: items),
            ),
            const SizedBox(height: 10),
          ],
          ElevatedButton(
            onPressed: onPressed,
            style: ElevatedButton.styleFrom(
              backgroundColor: palette.ink,
              foregroundColor: palette.canvas,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              minimumSize: const Size(0, 36),
              elevation: 0,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.add_rounded, size: 16, color: palette.canvas),
                const SizedBox(width: 6),
                Text(
                  buttonText,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.3,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _listItem({
    required WabiSabiPalette palette,
    String? icon,
    Color? iconColor,
    required String title,
    String? desc,
    required VoidCallback onRemove,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 10),
      decoration: BoxDecoration(
        color: palette.canvas,
        borderRadius: BorderRadius.circular(12),
        border: Border(
          left: BorderSide(color: palette.strictAccent, width: 3),
          top: BorderSide(color: palette.border, width: 0.8),
          right: BorderSide(color: palette.border, width: 0.8),
          bottom: BorderSide(color: palette.border, width: 0.8),
        ),
      ),
      child: Row(
        children: [
          if (icon != null && iconColor != null) ...[
            Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color: iconColor,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Center(
                child: Text(
                  icon,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: palette.ink,
                    letterSpacing: -0.2,
                  ),
                ),
                if (desc != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    desc,
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w400,
                      color: palette.mutedInk,
                      height: 1.3,
                    ),
                  ),
                ],
              ],
            ),
          ),
          IconButton(
            icon: Icon(Icons.close_rounded, color: palette.mutedInk, size: 18),
            onPressed: onRemove,
            constraints: const BoxConstraints(),
            padding: const EdgeInsets.all(6),
            splashRadius: 18,
          ),
        ],
      ),
    );
  }
}
