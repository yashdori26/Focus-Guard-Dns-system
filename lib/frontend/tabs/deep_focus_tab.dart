import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../backend/mdm_service.dart';
import '../../models/app_models.dart';
import '../../state_management/providers.dart';
import '../theme/wabi_sabi_theme.dart';
import '../widgets/app_logo.dart';

class DeepFocusTab extends ConsumerWidget {
  const DeepFocusTab({super.key});

  void _showAddWebsiteModal(BuildContext context, WidgetRef ref) {
    final palette = WabiSabiPalette.of(context);
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: palette.canvas,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return AddBlockedAppModal(ref: ref);
      },
    );
  }

  void _showUnifiedAddModal(BuildContext context, WidgetRef ref) {
    final palette = WabiSabiPalette.of(context);
    showModalBottomSheet(
      context: context,
      backgroundColor: palette.canvas,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                      color: palette.border,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'Add Restriction',
                  style: GoogleFonts.fraunces(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: palette.ink,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Choose what type of distraction to block',
                  style: GoogleFonts.inter(fontSize: 12, color: palette.mutedInk),
                ),
                const SizedBox(height: 14),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: palette.surface,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: palette.border),
                    ),
                    child: Icon(Icons.apps_rounded, color: palette.ink, size: 20),
                  ),
                  title: Text(
                    'App or Website',
                    style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600, color: palette.ink),
                  ),
                  subtitle: Text(
                    'Block YouTube, Instagram, Reddit, games, etc.',
                    style: GoogleFonts.inter(fontSize: 11, color: palette.mutedInk),
                  ),
                  trailing: Icon(Icons.chevron_right, color: palette.mutedInk, size: 20),
                  onTap: () {
                    Navigator.pop(ctx);
                    _showAddWebsiteModal(context, ref);
                  },
                ),
                Divider(color: palette.border, height: 12),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: palette.surface,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: palette.border),
                    ),
                    child: Icon(Icons.category_outlined, color: palette.ink, size: 20),
                  ),
                  title: Text(
                    'Category',
                    style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600, color: palette.ink),
                  ),
                  subtitle: Text(
                    'Block Adult, Gambling, Piracy, Social Networks, etc.',
                    style: GoogleFonts.inter(fontSize: 11, color: palette.mutedInk),
                  ),
                  trailing: Icon(Icons.chevron_right, color: palette.mutedInk, size: 20),
                  onTap: () {
                    Navigator.pop(ctx);
                    _showAddCategoryModal(context, ref);
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showAddCategoryModal(BuildContext context, WidgetRef ref) {
    final palette = WabiSabiPalette.of(context);
    final currentCatIds = ref.read(deepFocusProvider).categories.map((c) => c.id.toLowerCase()).toSet();
    final available = const [
      BlockedItem(
        id: 'porn',
        name: 'Adult & Pornography',
        icon: '🔞',
        color: Color(0xFFE11D48),
        description: 'Blocks explicit adult tube sites, webcam portals, and NSFW networks.',
      ),
      BlockedItem(
        id: 'social',
        name: 'Social Networks',
        icon: '📱',
        color: Color(0xFF2563EB),
        description: 'Blocks Facebook, Instagram, TikTok, Reddit, and Twitter/X.',
      ),
      BlockedItem(
        id: 'gaming',
        name: 'Online Gaming',
        icon: '🎮',
        color: Color(0xFF7C3AED),
        description: 'Blocks Steam, PlayStation Network, Xbox Live, and Roblox.',
      ),
      BlockedItem(
        id: 'dating',
        name: 'Dating Services',
        icon: '💘',
        color: Color(0xFFDB2777),
        description: 'Blocks all online dating platforms and mobile matchmaking apps.',
      ),
      BlockedItem(
        id: 'gambling',
        name: 'Gambling & Betting',
        icon: '🎲',
        color: Color(0xFFEA580C),
        description: 'Blocks all online gambling, casino, and betting websites.',
      ),
      BlockedItem(
        id: 'piracy',
        name: 'Piracy & Torrents',
        icon: '🏴‍☠️',
        color: Color(0xFF4F46E5),
        description: 'Blocks P2P torrent trackers, warez, and illegal streaming sites.',
      ),
      BlockedItem(
        id: 'video',
        name: 'Video Streaming',
        icon: '🎬',
        color: Color(0xFFD97706),
        description: 'Blocks YouTube, Netflix, Disney+, Prime Video, and Twitch.',
      ),
    ].where((cat) => !currentCatIds.contains(cat.id.toLowerCase())).toList();

    showModalBottomSheet(
      context: context,
      backgroundColor: palette.canvas,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return Container(
          padding: const EdgeInsets.all(20),
          height: 420,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: palette.border,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Add Category',
                    style: GoogleFonts.fraunces(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: palette.ink,
                    ),
                  ),
                  IconButton(
                    icon: Icon(Icons.close_rounded, color: palette.mutedInk, size: 20),
                    onPressed: () => Navigator.pop(ctx),
                  ),
                ],
              ),
              Divider(color: palette.border),
              Expanded(
                child: available.isEmpty
                    ? Center(
                        child: Text(
                          'All available categories are already added to your focus rules.',
                          style: GoogleFonts.inter(fontSize: 12.5, color: palette.mutedInk),
                        ),
                      )
                    : ListView.separated(
                        itemCount: available.length,
                        separatorBuilder: (_, __) => Divider(color: palette.hairlineSoft, height: 1),
                        itemBuilder: (context, i) {
                          final item = available[i];
                          return Padding(
                            padding: const EdgeInsets.symmetric(vertical: 10.0),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                Container(
                                  width: 36,
                                  height: 36,
                                  decoration: BoxDecoration(
                                    color: palette.surface,
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(color: palette.border, width: 0.8),
                                  ),
                                  child: Center(
                                    child: Text(item.icon, style: const TextStyle(fontSize: 17)),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        item.name,
                                        style: GoogleFonts.inter(
                                          fontSize: 13,
                                          fontWeight: FontWeight.w600,
                                          color: palette.ink,
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        item.description ?? '',
                                        style: GoogleFonts.inter(fontSize: 11, color: palette.mutedInk, height: 1.25),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 10),
                                ElevatedButton(
                                  onPressed: () {
                                    ref.read(deepFocusProvider.notifier).addCategory(item);
                                    Navigator.pop(ctx);
                                  },
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: palette.ink,
                                    foregroundColor: palette.canvas,
                                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                                    minimumSize: Size.zero,
                                    elevation: 0,
                                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(7),
                                    ),
                                  ),
                                  child: Text(
                                    '+ ADD',
                                    style: GoogleFonts.jetBrainsMono(
                                      fontSize: 10.5,
                                      fontWeight: FontWeight.w700,
                                      letterSpacing: 0.3,
                                    ),
                                  ),
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
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // EYEBROW
        Text(
          'FOCUSDNS · FOCUS',
          style: GoogleFonts.jetBrainsMono(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.3,
            color: palette.mutedInk,
          ),
        ),
        const SizedBox(height: 6),

        // HERO HEADLINE
        Text(
          'Quiet the noise.',
          style: GoogleFonts.fraunces(
            fontSize: 28,
            fontWeight: FontWeight.w700,
            color: palette.ink,
            height: 1.15,
            letterSpacing: -0.6,
          ),
        ),
        const SizedBox(height: 4),

        // SUBTITLE
        Text(
          'Choose what to block. Essentials stay online.',
          style: GoogleFonts.inter(
            fontSize: 12.5,
            color: palette.mutedInk,
            height: 1.3,
          ),
        ),
        const SizedBox(height: 16),

        // SECTION HEADER ROW
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'ACTIVE RESTRICTIONS',
              style: GoogleFonts.jetBrainsMono(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.1,
                color: palette.mutedInk,
              ),
            ),
            ElevatedButton.icon(
              key: const Key('add_restriction_button'),
              onPressed: () => _showUnifiedAddModal(context, ref),
              icon: const Icon(Icons.add_rounded, size: 14),
              label: Text(
                'Add',
                style: GoogleFonts.inter(fontSize: 11.5, fontWeight: FontWeight.w700),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: palette.ink,
                foregroundColor: palette.canvas,
                elevation: 0,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(7)),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),

        // CARD 1: WEBSITES, APPS & GAMES
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
              useAppLogo: true,
              appName: w.name,
              packageName: w.packages.isNotEmpty ? w.packages.first : w.id,
              title: w.name,
              isStrict: strictState.isStrict,
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

        // CARD 2: CATEGORIES
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
              icon: c.icon,
              iconColor: c.color,
              title: c.name,
              desc: c.description,
              isStrict: strictState.isStrict,
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

        // BOTTOM FOOTNOTE
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Text(
            'Essential utilities like maps, telephone calls, and UPI payments are permanently preserved online. Nothing is uploaded to external servers.',
            textAlign: TextAlign.center,
            style: GoogleFonts.inter(
              fontSize: 11.5,
              fontStyle: FontStyle.italic,
              color: palette.mutedInk.withOpacity(0.85),
              height: 1.4,
            ),
          ),
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
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: palette.border, width: 1.0),
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
                  style: GoogleFonts.fraunces(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: palette.ink,
                    letterSpacing: -0.3,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3.5),
                decoration: BoxDecoration(
                  color: items.isNotEmpty
                      ? palette.strictAccent.withOpacity(0.12)
                      : palette.canvas,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                    color: items.isNotEmpty
                        ? palette.strictAccent.withOpacity(0.3)
                        : palette.border,
                    width: 0.8,
                  ),
                ),
                child: Text(
                  items.isNotEmpty ? '${items.length} BLOCKED' : '0 BLOCKED',
                  style: GoogleFonts.jetBrainsMono(
                    fontSize: 9.5,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.5,
                    color: items.isNotEmpty ? palette.strictAccent : palette.mutedInk,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 5),
          Text(
            desc,
            style: GoogleFonts.inter(
              fontSize: 12,
              fontWeight: FontWeight.w400,
              color: palette.mutedInk,
              height: 1.35,
            ),
          ),
          const SizedBox(height: 14),
          if (items.isNotEmpty) ...[
            AnimatedSize(
              duration: const Duration(milliseconds: 250),
              curve: Curves.easeOutCubic,
              child: Column(children: items),
            ),
            const SizedBox(height: 8),
          ],
          ElevatedButton(
            onPressed: onPressed,
            style: ElevatedButton.styleFrom(
              backgroundColor: palette.ink,
              foregroundColor: palette.canvas,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
              minimumSize: const Size(0, 36),
              elevation: 0,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.add_rounded, size: 15, color: palette.canvas),
                const SizedBox(width: 6),
                Text(
                  buttonText,
                  style: GoogleFonts.inter(
                    fontSize: 11,
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
    bool useAppLogo = false,
    String? appName,
    String? packageName,
    String? icon,
    Color? iconColor,
    required String title,
    String? desc,
    bool isStrict = false,
    required VoidCallback onRemove,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 11),
      decoration: BoxDecoration(
        color: palette.canvas,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: palette.border, width: 0.9),
      ),
      child: Row(
        children: [
          if (useAppLogo) ...[
            AppLogo(
              appName: appName ?? title,
              packageName: packageName,
              size: 30,
            ),
            const SizedBox(width: 10),
          ] else if (icon != null) ...[
            Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(
                color: (iconColor ?? palette.ink).withOpacity(0.12),
                borderRadius: BorderRadius.circular(7),
                border: Border.all(color: (iconColor ?? palette.ink).withOpacity(0.25), width: 0.8),
              ),
              child: Center(
                child: Text(
                  icon,
                  style: const TextStyle(fontSize: 14),
                ),
              ),
            ),
            const SizedBox(width: 10),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: GoogleFonts.inter(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: palette.ink,
                    letterSpacing: -0.1,
                  ),
                ),
                if (desc != null && desc.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    desc,
                    style: GoogleFonts.inter(
                      fontSize: 11,
                      fontWeight: FontWeight.w400,
                      color: palette.mutedInk,
                      height: 1.25,
                    ),
                  ),
                ],
                Builder(builder: (context) {
                  final target = (appName ?? title).toLowerCase();
                  final isSurgical = target.contains('insta') ||
                      target.contains('youtube') ||
                      target.contains('tiktok') ||
                      target.contains('twitter') ||
                      target.contains('reddit');
                  if (!isSurgical) return const SizedBox.shrink();
                  return Padding(
                    padding: const EdgeInsets.only(top: 4.0),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: palette.safeAccent.withOpacity(0.12),
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(color: palette.safeAccent.withOpacity(0.3), width: 0.8),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.bolt_rounded, size: 10, color: palette.safeAccent),
                              const SizedBox(width: 3),
                              Text(
                                'Surgical Feeds Shielded',
                                style: GoogleFonts.inter(
                                  fontSize: 9.5,
                                  fontWeight: FontWeight.w600,
                                  color: palette.safeAccent,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  );
                }),
              ],
            ),
          ),
          if (isStrict)
            Tooltip(
              message: 'Locked during Strict Mode',
              child: Padding(
                padding: const EdgeInsets.all(6),
                child: Icon(
                  Icons.lock_outline_rounded,
                  color: palette.mutedInk.withOpacity(0.4),
                  size: 16,
                ),
              ),
            )
          else
            IconButton(
              icon: Icon(Icons.close_rounded, color: palette.mutedInk, size: 17),
              onPressed: onRemove,
              constraints: const BoxConstraints(),
              padding: const EdgeInsets.all(5),
              splashRadius: 16,
            ),
        ],
      ),
    );
  }
}

/// Dynamic application & website picker modal that inspects all installed apps
/// on the user's phone, allowing them to search and pick any app directly.
class AddBlockedAppModal extends StatefulWidget {
  final WidgetRef ref;
  const AddBlockedAppModal({super.key, required this.ref});

  @override
  State<AddBlockedAppModal> createState() => _AddBlockedAppModalState();
}

class _AddBlockedAppModalState extends State<AddBlockedAppModal> {
  List<SplitTunnelAppItem> _allInstalledApps = [];
  List<SplitTunnelAppItem> _filteredApps = [];
  bool _isLoading = true;
  String _searchQuery = '';
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadApps();
  }

  static const List<List<String>> _famousApps = [
    ['YouTube', 'com.google.android.youtube'],
    ['Instagram', 'com.instagram.android'],
    ['Facebook', 'com.facebook.katana'],
    ['Reddit', 'com.reddit.frontpage'],
    ['TikTok', 'com.zhiliaoapp.musically'],
    ['Snapchat', 'com.snapchat.android'],
    ['X (Twitter)', 'com.twitter.android'],
    ['WhatsApp', 'com.whatsapp'],
    ['Telegram', 'org.telegram.messenger'],
    ['Netflix', 'com.netflix.mediaclient'],
    ['Amazon Prime Video', 'com.amazon.avod.thirdpartyclient'],
    ['Disney+ Hotstar', 'in.startv.hotstar'],
    ['Spotify', 'com.spotify.music'],
    ['Discord', 'com.discord'],
    ['Pinterest', 'com.pinterest'],
    ['LinkedIn', 'com.linkedin.android'],
    ['Twitch', 'tv.twitch.android.app'],
    ['Facebook Messenger', 'com.facebook.orca'],
    ['Threads', 'com.instagram.barcelona'],
    ['Roblox', 'com.roblox.client'],
  ];

  Future<void> _loadApps() async {
    List<SplitTunnelAppItem> installed = [];
    try {
      installed = await FocusMdmManager.getSplitTunnelApps();
    } catch (_) {}

    final famous = _famousApps
        .map((a) => SplitTunnelAppItem(
              packageName: a[1],
              appName: a[0],
              isSystemApp: false,
              isSelected: false,
            ))
        .toList();

    final seenPackages = <String>{};
    final combined = <SplitTunnelAppItem>[];

    for (final app in famous) {
      if (seenPackages.add(app.packageName.toLowerCase())) {
        combined.add(app);
      }
    }
    for (final app in installed) {
      if (!app.isSystemApp && seenPackages.add(app.packageName.toLowerCase())) {
        combined.add(app);
      }
    }

    if (mounted) {
      setState(() {
        _allInstalledApps = combined;
        _isLoading = false;
        _filterApps();
      });
    }
  }

  void _filterApps() {
    if (_searchQuery.trim().isEmpty) {
      _filteredApps = List.from(_allInstalledApps);
    } else {
      final q = _searchQuery.toLowerCase();
      _filteredApps = _allInstalledApps.where((app) {
        return app.appName.toLowerCase().contains(q) ||
            app.packageName.toLowerCase().contains(q);
      }).toList();
    }
  }

  Color _getAppColor(String name, String packageName) {
    final lowerName = name.toLowerCase();
    final lowerPkg = packageName.toLowerCase();

    if (lowerName.contains('youtube') || lowerPkg.contains('youtube')) return const Color(0xFFFF0000);
    if (lowerName.contains('reddit') || lowerPkg.contains('reddit')) return const Color(0xFFFF4500);
    if (lowerName.contains('instagram') || lowerPkg.contains('instagram')) return const Color(0xFFE1306C);
    if (lowerName.contains('tiktok') || lowerPkg.contains('musical')) return const Color(0xFF000000);
    if (lowerName.contains('facebook') || lowerPkg.contains('katana')) return const Color(0xFF1877F2);
    if (lowerName.contains('whatsapp') || lowerPkg.contains('whatsapp')) return const Color(0xFF25D366);
    if (lowerName.contains('netflix') || lowerPkg.contains('netflix')) return const Color(0xFFE50914);
    if (lowerName.contains('spotify') || lowerPkg.contains('spotify')) return const Color(0xFF1DB954);
    if (lowerName.contains('discord') || lowerPkg.contains('discord')) return const Color(0xFF5865F2);
    if (lowerName.contains('twitter') || lowerPkg.contains('twitter') || lowerName == 'x') return const Color(0xFF000000);
    if (lowerName.contains('chrome') || lowerPkg.contains('chrome')) return const Color(0xFF4285F4);
    if (lowerName.contains('telegram') || lowerPkg.contains('telegram')) return const Color(0xFF26A5E4);

    final hash = (name + packageName).codeUnits.fold<int>(0, (prev, elem) => prev + elem);
    final hue = (hash * 37) % 360;
    return HSLColor.fromAHSL(1.0, hue.toDouble(), 0.65, 0.45).toColor();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = WabiSabiPalette.of(context);
    final deepFocusState = widget.ref.watch(deepFocusProvider);

    return Container(
      height: MediaQuery.of(context).size.height * 0.85,
      padding: EdgeInsets.only(
        top: 12,
        left: 20,
        right: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 16,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Drag handle
          Center(
            child: Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: palette.border,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 12),
          // Title row
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Block App or Website',
                      style: GoogleFonts.fraunces(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: palette.ink,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _isLoading
                          ? 'Scanning installed applications...'
                          : 'Top ${_allInstalledApps.length} distracting apps',
                      style: GoogleFonts.inter(
                        fontSize: 11.5,
                        color: palette.mutedInk,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                key: const Key('modal_close_button'),
                icon: Icon(Icons.close_rounded, color: palette.mutedInk, size: 20),
                onPressed: () => Navigator.pop(context),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // Search box
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: palette.surface,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: palette.border, width: 1.0),
            ),
            child: TextField(
              controller: _searchController,
              style: GoogleFonts.inter(color: palette.ink, fontSize: 13),
              decoration: InputDecoration(
                icon: Icon(Icons.search_rounded, color: palette.mutedInk, size: 18),
                hintText: 'Search apps on phone or enter domain...',
                hintStyle: GoogleFonts.inter(color: palette.mutedInk.withOpacity(0.7), fontSize: 13),
                border: InputBorder.none,
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(vertical: 10),
                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(
                        icon: Icon(Icons.clear, color: palette.mutedInk, size: 16),
                        onPressed: () {
                          _searchController.clear();
                          setState(() {
                            _searchQuery = '';
                            _filterApps();
                          });
                        },
                      )
                    : null,
              ),
              onChanged: (val) {
                setState(() {
                  _searchQuery = val;
                  _filterApps();
                });
              },
            ),
          ),
          const SizedBox(height: 12),
          Divider(color: palette.border, height: 1),
          const SizedBox(height: 4),

          // App List
          Expanded(
            child: _isLoading
                ? Center(
                    child: CircularProgressIndicator(
                      strokeWidth: 2.5,
                      valueColor: AlwaysStoppedAnimation<Color>(palette.ink),
                    ),
                  )
                : ListView(
                    children: [
                      // If search query is not empty, offer custom domain block
                      if (_searchQuery.trim().isNotEmpty) ...[
                        ListTile(
                          contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                          leading: AppLogo(
                            appName: _searchQuery,
                            size: 32,
                          ),
                          title: Text(
                            'Block "$_searchQuery"',
                            style: GoogleFonts.inter(color: palette.ink, fontWeight: FontWeight.w600, fontSize: 13),
                          ),
                          trailing: ElevatedButton(
                            onPressed: () {
                              final query = _searchQuery.trim();
                              final item = BlockedItem(
                                id: query.toLowerCase(),
                                name: query,
                                icon: query.isNotEmpty ? query[0].toUpperCase() : 'W',
                                color: _getAppColor(query, query),
                                packages: [query],
                              );
                              widget.ref.read(deepFocusProvider.notifier).addWebsite(item);
                              _searchController.clear();
                              setState(() {
                                _searchQuery = '';
                                _filterApps();
                              });
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: palette.ink,
                              foregroundColor: palette.canvas,
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                              minimumSize: Size.zero,
                              elevation: 0,
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(7)),
                            ),
                            child: Text(
                              'BLOCK',
                              style: GoogleFonts.jetBrainsMono(fontSize: 10.5, fontWeight: FontWeight.w700),
                            ),
                          ),
                        ),
                        Divider(color: palette.hairlineSoft, height: 1),
                      ],
                      if (_filteredApps.isEmpty && _searchQuery.trim().isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 32),
                          child: Center(
                            child: Text(
                              'No installed apps found matching "$_searchQuery"',
                              style: GoogleFonts.inter(color: palette.mutedInk, fontSize: 12.5),
                            ),
                          ),
                        )
                      else
                        ..._filteredApps.map((app) {
                          final isBlocked = deepFocusState.websites.any((w) =>
                              w.packages.contains(app.packageName) ||
                              w.name.toLowerCase() == app.appName.toLowerCase());
                          final color = _getAppColor(app.appName, app.packageName);
                          final letter = app.appName.trim().isNotEmpty ? app.appName.trim()[0].toUpperCase() : 'A';

                          return ListTile(
                            contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                            leading: AppLogo(
                              appName: app.appName,
                              packageName: app.packageName,
                              size: 32,
                            ),
                            title: Text(
                              app.appName,
                              style: GoogleFonts.inter(
                                color: palette.ink,
                                fontWeight: FontWeight.w600,
                                fontSize: 13,
                              ),
                            ),
                            subtitle: Text(
                              app.packageName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.jetBrainsMono(
                                color: palette.mutedInk,
                                fontSize: 10,
                              ),
                            ),
                            trailing: isBlocked
                                ? Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4.5),
                                    decoration: BoxDecoration(
                                      color: palette.canvas,
                                      borderRadius: BorderRadius.circular(6),
                                      border: Border.all(color: palette.border),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(Icons.check_rounded, size: 12, color: palette.mutedInk),
                                        const SizedBox(width: 4),
                                        Text(
                                          'BLOCKED',
                                          style: GoogleFonts.jetBrainsMono(
                                            fontSize: 9.5,
                                            fontWeight: FontWeight.w700,
                                            color: palette.mutedInk,
                                            letterSpacing: 0.4,
                                          ),
                                        ),
                                      ],
                                    ),
                                  )
                                : ElevatedButton(
                                    onPressed: () {
                                      final item = BlockedItem(
                                        id: app.packageName,
                                        name: app.appName,
                                        icon: letter,
                                        color: color,
                                        packages: [app.packageName],
                                      );
                                      widget.ref.read(deepFocusProvider.notifier).addWebsite(item);
                                      setState(() {});
                                    },
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: palette.ink,
                                      foregroundColor: palette.canvas,
                                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                                      minimumSize: Size.zero,
                                      elevation: 0,
                                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(7)),
                                    ),
                                    child: Text(
                                      'BLOCK',
                                      style: GoogleFonts.jetBrainsMono(fontSize: 10.5, fontWeight: FontWeight.w700),
                                    ),
                                  ),
                          );
                        }),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}
