import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../state_management/providers.dart';
import '../theme/wabi_sabi_theme.dart';

class LogsTab extends ConsumerStatefulWidget {
  const LogsTab({super.key});

  @override
  ConsumerState<LogsTab> createState() => _LogsTabState();
}

class _LogsTabState extends ConsumerState<LogsTab> {
  final TextEditingController _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final logsState = ref.watch(logsProvider);
    final filteredLogs = logsState.filteredLogs;
    final palette = WabiSabiPalette.of(context);

    return Column(
      children: [
        // SEARCH BAR
        TextField(
          controller: _searchController,
          style: TextStyle(fontSize: 13, color: palette.ink),
          onChanged: (val) {
            ref.read(logsProvider.notifier).setSearchQuery(val);
          },
          decoration: InputDecoration(
            hintText: 'Search queries...',
            hintStyle: TextStyle(color: palette.mutedInk, fontSize: 13),
            prefixIcon: Icon(Icons.search, color: palette.mutedInk, size: 18),
            suffixIcon: logsState.searchQuery.isNotEmpty
                ? IconButton(
                    icon: Icon(Icons.clear, color: palette.mutedInk, size: 16),
                    onPressed: () {
                      _searchController.clear();
                      ref.read(logsProvider.notifier).setSearchQuery('');
                    },
                  )
                : null,
            filled: true,
            fillColor: palette.surface,
            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: palette.border),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: palette.border),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: palette.ink),
            ),
          ),
        ),
        const SizedBox(height: 16),

        // LOG ITEMS LIST
        if (filteredLogs.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 40.0),
            child: Center(
              child: Text(
                'No matching DNS queries found',
                style: TextStyle(color: palette.mutedInk, fontSize: 13),
              ),
            ),
          )
        else
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: filteredLogs.length,
            separatorBuilder: (_, __) =>
                Divider(color: palette.border, height: 16),
            itemBuilder: (context, index) {
              final log = filteredLogs[index];
              return Row(
                children: [
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: palette.surface,
                      border: Border.all(color: palette.border),
                    ),
                    child: Center(
                      child: Text(
                        log.icon,
                        style: TextStyle(
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
                          text: TextSpan(
                            children: [
                              TextSpan(
                                text: log.subdomain,
                                style: TextStyle(
                                  color: palette.mutedInk,
                                  fontSize: 13,
                                ),
                              ),
                              TextSpan(
                                text: log.domain,
                                style: TextStyle(
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
                          style: TextStyle(
                            color: palette.subtleInk,
                            fontSize: 10,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    width: 6,
                    height: 6,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: palette.strictAccent,
                    ),
                  ),
                ],
              );
            },
          ),
      ],
    );
  }
}
