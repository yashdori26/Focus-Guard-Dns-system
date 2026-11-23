import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../engine/surgical/surgical_domain_definitions.dart';
import '../../engine/surgical/surgical_pattern_compiler.dart';
import '../theme/wabi_sabi_theme.dart';

/// Full-screen Studio for managing surgical feed vs chat rules and inspecting live network patterns.
class SurgicalFeedStudioScreen extends StatefulWidget {
  const SurgicalFeedStudioScreen({super.key});

  @override
  State<SurgicalFeedStudioScreen> createState() => _SurgicalFeedStudioScreenState();
}

class _SurgicalFeedStudioScreenState extends State<SurgicalFeedStudioScreen> {
  final Map<SurgicalPlatform, bool> _platformToggles = {
    SurgicalPlatform.instagram: true,
    SurgicalPlatform.youtube: true,
    SurgicalPlatform.reddit: true,
    SurgicalPlatform.tiktok: true,
    SurgicalPlatform.twitterX: true,
  };

  late SurgicalPatternCompiler _compiler;
  String _testInput = '';
  SurgicalDecision? _inspectionResult;

  @override
  void initState() {
    super.initState();
    _recompile();
  }

  void _recompile() {
    setState(() {
      _compiler = SurgicalPatternCompiler(platformToggles: _platformToggles);
      if (_testInput.isNotEmpty) {
        _inspectionResult = _compiler.evaluateUrlPath(_testInput);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final palette = WabiSabiPalette.of(context);

    return Scaffold(
      backgroundColor: palette.canvas,
      appBar: AppBar(
        backgroundColor: palette.canvas,
        elevation: 0,
        iconTheme: IconThemeData(color: palette.ink),
        title: Text(
          'Surgical Feed vs Chat Studio',
          style: GoogleFonts.plusJakartaSans(
            color: palette.ink,
            fontSize: 18,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.3,
          ),
        ),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          children: [
            // 1. Interactive Pattern Simulator Bar
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: palette.surface,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: palette.border),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'LIVE SURGICAL TRAFFIC INSPECTOR',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.1,
                      color: palette.mutedInk,
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    onChanged: (val) {
                      setState(() {
                        _testInput = val;
                        _inspectionResult = val.isEmpty ? null : _compiler.evaluateUrlPath(val);
                      });
                    },
                    decoration: InputDecoration(
                      hintText: 'e.g. reels.instagram.com, youtube.com/shorts, chat.reddit.com',
                      hintStyle: GoogleFonts.jetBrainsMono(fontSize: 11, color: palette.mutedInk),
                      filled: true,
                      fillColor: palette.canvas,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: palette.border),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: palette.border),
                      ),
                    ),
                    style: GoogleFonts.jetBrainsMono(fontSize: 12, color: palette.ink),
                  ),
                  if (_inspectionResult != null) ...[
                    const SizedBox(height: 12),
                    _buildInspectionResultBadge(_inspectionResult!, palette),
                  ],
                ],
              ),
            ),

            const SizedBox(height: 24),

            Text(
              'PLATFORM FEED-KILLER POLICIES',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.1,
                color: palette.mutedInk,
              ),
            ),
            const SizedBox(height: 10),

            // 2. Platform Toggles
            ...SurgicalDomainDefinitions.platformRules.values.map((rule) {
              final isEnabled = _platformToggles[rule.platform] ?? false;

              return Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: palette.surface,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: isEnabled ? palette.ink.withOpacity(0.3) : palette.border,
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(rule.iconGlyph, style: const TextStyle(fontSize: 24)),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                rule.displayName,
                                style: GoogleFonts.plusJakartaSans(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700,
                                  color: palette.ink,
                                ),
                              ),
                              Text(
                                isEnabled ? 'Surgical Filter Active' : 'Filter Disabled (Full App Allowed)',
                                style: GoogleFonts.plusJakartaSans(
                                  fontSize: 11,
                                  color: isEnabled ? const Color(0xFF27AE60) : palette.mutedInk,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Switch(
                          value: isEnabled,
                          activeColor: palette.ink,
                          onChanged: (val) {
                            setState(() {
                              _platformToggles[rule.platform] = val;
                              _recompile();
                            });
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: palette.canvas,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Column(
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(Icons.block_rounded, size: 14, color: palette.strictAccent),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  rule.feedDescription,
                                  style: GoogleFonts.plusJakartaSans(fontSize: 11, color: palette.mutedInk),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Icon(Icons.check_circle_outline_rounded, size: 14, color: Color(0xFF27AE60)),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  rule.chatDescription,
                                  style: GoogleFonts.plusJakartaSans(fontSize: 11, color: palette.mutedInk),
                                ),
                              ),
                            ],
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
    );
  }

  Widget _buildInspectionResultBadge(SurgicalDecision decision, WabiSabiPalette palette) {
    Color bg;
    Color fg;
    String label;
    IconData icon;

    switch (decision) {
      case SurgicalDecision.blackholeFeed:
        bg = palette.strictAccent.withOpacity(0.12);
        fg = palette.strictAccent;
        label = 'BLACKHOLED BY SINKHOLE: Addictive Infinite Feed Detected';
        icon = Icons.cancel_rounded;
        break;
      case SurgicalDecision.whitelistChat:
        bg = const Color(0xFF2ECC71).withOpacity(0.12);
        fg = const Color(0xFF27AE60);
        label = 'WHITELISTED: Direct Messaging / Chat Stream Preserved';
        icon = Icons.mark_chat_read_rounded;
        break;
      case SurgicalDecision.whitelistSearch:
        bg = const Color(0xFF3498DB).withOpacity(0.12);
        fg = const Color(0xFF2980B9);
        label = 'WHITELISTED: Educational Query / Search Endpoint';
        icon = Icons.school_rounded;
        break;
      case SurgicalDecision.passThrough:
        bg = palette.canvas;
        fg = palette.mutedInk;
        label = 'PASSTHROUGH: Standard Unfiltered Domain';
        icon = Icons.arrow_forward_rounded;
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: fg.withOpacity(0.4)),
      ),
      child: Row(
        children: [
          Icon(icon, size: 16, color: fg),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              label,
              style: GoogleFonts.plusJakartaSans(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: fg,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
