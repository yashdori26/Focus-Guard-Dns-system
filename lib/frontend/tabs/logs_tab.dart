import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../state_management/providers.dart';
import '../../models/app_models.dart';
import '../theme/wabi_sabi_theme.dart';

class LogsTab extends ConsumerStatefulWidget {
  final WabiSabiPalette? palette;
  const LogsTab({super.key, this.palette});

  @override
  ConsumerState<LogsTab> createState() => _LogsTabState();
}

class _LogsTabState extends ConsumerState<LogsTab> {
  final TextEditingController _searchController = TextEditingController();
  String _activeFilter = 'All'; // 'All', 'Blocked', 'Allowed'

  static final List<QueryLog> _sampleLogs = [
    const QueryLog(
      id: 's1',
      subdomain: 'api.',
      domain: 'instagram.com',
      time: 'Just now',
      icon: 'IG',
      isBlocked: false,
    ),
    const QueryLog(
      id: 's2',
      subdomain: 'rr1---sn-oxu.',
      domain: 'googlevideo.com',
      time: '2s ago',
      icon: 'YT',
      isBlocked: false,
    ),
    const QueryLog(
      id: 's3',
      subdomain: 'telemetry.',
      domain: 'tiktokv.com',
      time: '5s ago',
      icon: 'TT',
      isBlocked: true,
    ),
    const QueryLog(
      id: 's4',
      subdomain: 'adservice.',
      domain: 'google.com',
      time: '12s ago',
      icon: 'AD',
      isBlocked: true,
    ),
    const QueryLog(
      id: 's5',
      subdomain: 'gateway.',
      domain: 'discord.gg',
      time: '28s ago',
      icon: 'DC',
      isBlocked: false,
    ),
    const QueryLog(
      id: 's6',
      subdomain: 'pixel.',
      domain: 'facebook.com',
      time: '45s ago',
      icon: 'FB',
      isBlocked: true,
    ),
    const QueryLog(
      id: 's7',
      subdomain: 'v.',
      domain: 'redd.it',
      time: '1m ago',
      icon: 'RD',
      isBlocked: false,
    ),
    const QueryLog(
      id: 's8',
      subdomain: 'secure.',
      domain: 'netflix.com',
      time: '2m ago',
      icon: 'NF',
      isBlocked: false,
    ),
    const QueryLog(
      id: 's9',
      subdomain: 'tracker.',
      domain: 'doubleclick.net',
      time: '3m ago',
      icon: 'AD',
      isBlocked: true,
    ),
  ];

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final logsState = ref.watch(logsProvider);
    final palette = widget.palette ?? WabiSabiPalette.of(context);

    final bool useSample = kIsWeb && logsState.logs.isEmpty;
    final baseLogs = useSample ? _sampleLogs : logsState.logs;

    final query = (logsState.searchQuery.isNotEmpty ? logsState.searchQuery : _searchController.text).trim().toLowerCase();

    final filteredLogs = query.isEmpty
        ? baseLogs
        : baseLogs.where((l) =>
            l.domain.toLowerCase().contains(query) ||
            l.subdomain.toLowerCase().contains(query)).toList();

    final displayedLogs = filteredLogs.where((l) {
      if (_activeFilter == 'Blocked') return l.isBlocked;
      if (_activeFilter == 'Allowed') return !l.isBlocked;
      return true;
    }).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // SUBHEADER & SECURITY STATUS
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 8,
          runSpacing: 4,
          children: [
            Text(
              'LIVE QUERY ACTIVITY',
              style: GoogleFonts.inter(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.1,
                color: palette.mutedInk,
              ),
            ),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                GestureDetector(
                  onTap: () => ref.read(logsProvider.notifier).refreshFromDb(),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.refresh, size: 14, color: palette.mutedInk),
                      const SizedBox(width: 4),
                      Text(
                        'Refresh History',
                        style: GoogleFonts.inter(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w600,
                          color: palette.mutedInk,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Container(
                  width: 6,
                  height: 6,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: palette.accent,
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  'Local SQLite DB',
                  style: GoogleFonts.inter(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w600,
                    color: palette.mutedInk,
                  ),
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 10),

        // SEARCH BAR (NEWSPAPER PAPER STYLE WITH INPUT DECORATION)
        TextField(
          controller: _searchController,
          style: GoogleFonts.inter(fontSize: 13, color: palette.ink),
          onChanged: (val) {
            ref.read(logsProvider.notifier).setSearchQuery(val);
            setState(() {});
          },
          decoration: InputDecoration(
            hintText: 'Search queries...',
            hintStyle: GoogleFonts.inter(color: palette.mutedInk, fontSize: 13),
            prefixIcon: Icon(Icons.search, color: palette.mutedInk, size: 18),
            suffixIcon: _searchController.text.isNotEmpty
                ? IconButton(
                    icon: Icon(Icons.clear, color: palette.mutedInk, size: 16),
                    onPressed: () {
                      _searchController.clear();
                      ref.read(logsProvider.notifier).setSearchQuery('');
                      setState(() {});
                    },
                  )
                : null,
            filled: true,
            fillColor: palette.surface,
            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(4),
              borderSide: BorderSide(color: palette.hairlineSoft, width: 1.0),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(4),
              borderSide: BorderSide(color: palette.hairlineSoft, width: 1.0),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(4),
              borderSide: BorderSide(color: palette.ink, width: 1.0),
            ),
          ),
        ),
        const SizedBox(height: 10),

        // FILTER CHIPS (All / Blocked / Allowed)
        Row(
          children: ['All', 'Blocked', 'Allowed'].map((filter) {
            final isSel = _activeFilter == filter;
            return GestureDetector(
              onTap: () => setState(() => _activeFilter = filter),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                curve: Curves.easeOutCubic,
                margin: const EdgeInsets.only(right: 8),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4.5),
                decoration: BoxDecoration(
                  color: isSel ? palette.ink : Colors.transparent,
                  borderRadius: BorderRadius.circular(3),
                  border: Border.all(
                    color: isSel ? palette.ink : palette.hairlineSoft,
                    width: 1.0,
                  ),
                ),
                child: Text(
                  filter,
                  style: GoogleFonts.inter(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: isSel ? palette.canvas : palette.mutedInk,
                  ),
                ),
              ),
            );
          }).toList(),
        ),
        const SizedBox(height: 12),

        // LOG ITEMS CARD (PAPER CONTAINER)
        Container(
          width: double.infinity,
          decoration: BoxDecoration(
            color: palette.surface,
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: palette.hairlineSoft, width: 1.0),
          ),
          child: displayedLogs.isEmpty
              ? Padding(
                  padding: const EdgeInsets.symmetric(vertical: 36.0, horizontal: 20),
                  child: Center(
                    child: Text(
                      'No matching DNS queries found',
                      style: GoogleFonts.inter(color: palette.mutedInk, fontSize: 13),
                    ),
                  ),
                )
              : ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: displayedLogs.length,
                  separatorBuilder: (_, __) =>
                      Divider(color: palette.hairlineSoft, height: 1, thickness: 1),
                  itemBuilder: (context, index) {
                    final log = displayedLogs[index];
                    return Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
                      child: Row(
                        children: [
                          Container(
                            width: 32,
                            height: 32,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: palette.canvas,
                              border: Border.all(color: palette.hairlineSoft, width: 1.0),
                            ),
                            child: Center(
                              child: Text(
                                log.icon,
                                style: GoogleFonts.inter(
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  color: palette.ink,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                RichText(
                                  overflow: TextOverflow.ellipsis,
                                  maxLines: 1,
                                  text: TextSpan(
                                    children: [
                                      TextSpan(
                                        text: log.subdomain,
                                        style: GoogleFonts.inter(
                                          color: palette.mutedInk,
                                          fontSize: 13,
                                          fontWeight: FontWeight.w400,
                                        ),
                                      ),
                                      TextSpan(
                                        text: log.domain,
                                        style: GoogleFonts.inter(
                                          color: palette.ink,
                                          fontWeight: FontWeight.bold,
                                          fontSize: 13,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  log.time,
                                  style: GoogleFonts.inter(
                                    color: palette.subtleInk,
                                    fontSize: 10,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
                            decoration: BoxDecoration(
                              color: log.isBlocked
                                  ? palette.strictAccent.withOpacity(0.12)
                                  : palette.safeAccent.withOpacity(0.12),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              log.isBlocked ? 'BLOCKED' : 'ALLOW',
                              style: GoogleFonts.inter(
                                fontSize: 9,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 0.5,
                                color: log.isBlocked
                                    ? palette.strictAccent
                                    : palette.safeAccent,
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
    );
  }
}
