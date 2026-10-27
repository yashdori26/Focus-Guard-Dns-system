import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'tabs/allowlist_tab.dart';
import 'tabs/denylist_tab.dart';
import 'tabs/logs_tab.dart';
import 'tabs/privacy_tab.dart';
import 'tabs/security_tab.dart';
import 'tabs/settings_tab.dart';
import 'tabs/setup_tab.dart';
import 'theme/wabi_sabi_theme.dart';

/// Secondary screens reachable from the "More" tab.
class MoreTab extends StatelessWidget {
  final WabiSabiPalette palette;
  const MoreTab({super.key, required this.palette});

  static const _groups = <_MoreGroup>[
    _MoreGroup(
      'NETWORK & PROTECTION',
      [
        _MoreItem('Setup', 'VPN and app blocker permissions', Icons.tune_rounded, 'setup'),
        _MoreItem('Security', 'Threat intelligence & tamper protection', Icons.shield_outlined, 'security'),
        _MoreItem('Privacy', 'Trackers, ad blocking & telemetry', Icons.visibility_off_outlined, 'privacy'),
      ],
    ),
    _MoreGroup(
      'RULES & DOMAINS',
      [
        _MoreItem('Allowlist', 'Bypass rules & always allowed domains', Icons.check_circle_outline_rounded, 'allowlist'),
        _MoreItem('Denylist', 'Custom blocked domains & wildcards', Icons.block_rounded, 'denylist'),
      ],
    ),
    _MoreGroup(
      'SYSTEM & PREFERENCES',
      [
        _MoreItem('Settings', 'Theme appearance, DNS profile & logs', Icons.settings_outlined, 'settings'),
      ],
    ),
  ];

  Widget _bodyFor(String id) {
    switch (id) {
      case 'setup':
        return const SetupTab();
      case 'security':
        return const SecurityTab();
      case 'privacy':
        return const PrivacyTab();
      case 'allowlist':
        return const AllowlistTab();
      case 'denylist':
        return const DenylistTab();
      case 'settings':
        return const SettingsTab();
      default:
        return const LogsTab();
    }
  }

  void _open(BuildContext context, _MoreItem item) {
    Navigator.of(context).push(
      PageRouteBuilder(
        transitionDuration: const Duration(milliseconds: 260),
        reverseTransitionDuration: const Duration(milliseconds: 200),
        pageBuilder: (context, animation, secondaryAnimation) => Scaffold(
          backgroundColor: palette.canvas,
          appBar: AppBar(
            backgroundColor: palette.canvas,
            elevation: 0,
            iconTheme: IconThemeData(color: palette.ink),
            title: Text(
              item.title,
              style: GoogleFonts.plusJakartaSans(
                color: palette.ink,
                fontSize: 18,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.3,
              ),
            ),
          ),
          body: SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: _bodyFor(item.id),
            ),
          ),
        ),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          final slide = Tween<Offset>(
            begin: const Offset(0.06, 0.0),
            end: Offset.zero,
          ).animate(CurvedAnimation(parent: animation, curve: Curves.easeOutCubic));

          return FadeTransition(
            opacity: animation,
            child: SlideTransition(position: slide, child: child),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 6, 20, 28),
      children: [
        for (final group in _groups) ...[
          Padding(
            padding: const EdgeInsets.only(left: 4, top: 14, bottom: 8),
            child: Text(
              group.header,
              style: GoogleFonts.plusJakartaSans(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.1,
                color: palette.mutedInk,
              ),
            ),
          ),
          Container(
            decoration: BoxDecoration(
              color: palette.surface,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: palette.border, width: 1),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(17),
              child: Column(
                children: [
                  for (int i = 0; i < group.items.length; i++) ...[
                    _BouncingMoreTile(
                      item: group.items[i],
                      palette: palette,
                      onTap: () => _open(context, group.items[i]),
                    ),
                    if (i < group.items.length - 1)
                      Divider(height: 1, thickness: 1, color: palette.border, indent: 64),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
        ],
      ],
    );
  }
}

class _BouncingMoreTile extends StatefulWidget {
  final _MoreItem item;
  final WabiSabiPalette palette;
  final VoidCallback onTap;

  const _BouncingMoreTile({
    required this.item,
    required this.palette,
    required this.onTap,
  });

  @override
  State<_BouncingMoreTile> createState() => _BouncingMoreTileState();
}

class _BouncingMoreTileState extends State<_BouncingMoreTile> {
  bool _isPressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      key: Key('more_${widget.item.id}'),
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => setState(() => _isPressed = true),
      onTapUp: (_) {
        setState(() => _isPressed = false);
        widget.onTap();
      },
      onTapCancel: () => setState(() => _isPressed = false),
      child: AnimatedScale(
        scale: _isPressed ? 0.985 : 1.0,
        duration: const Duration(milliseconds: 120),
        curve: Curves.easeOutCubic,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          color: _isPressed ? widget.palette.border.withOpacity(0.3) : Colors.transparent,
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(10),
                  color: widget.palette.canvas,
                  border: Border.all(color: widget.palette.border, width: 1),
                ),
                child: Center(
                  child: Icon(widget.item.icon, color: widget.palette.ink, size: 20),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.item.title,
                      style: GoogleFonts.plusJakartaSans(
                        color: widget.palette.ink,
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.2,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      widget.item.subtitle,
                      style: GoogleFonts.plusJakartaSans(
                        color: widget.palette.mutedInk,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w400,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded, color: widget.palette.mutedInk, size: 20),
            ],
          ),
        ),
      ),
    );
  }
}

class _MoreGroup {
  final String header;
  final List<_MoreItem> items;
  const _MoreGroup(this.header, this.items);
}

class _MoreItem {
  final String title;
  final String subtitle;
  final IconData icon;
  final String id;
  const _MoreItem(this.title, this.subtitle, this.icon, this.id);
}
