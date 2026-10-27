import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../state_management/providers.dart';
import '../theme/wabi_sabi_theme.dart';

class DenylistTab extends ConsumerStatefulWidget {
  const DenylistTab({super.key});

  @override
  ConsumerState<DenylistTab> createState() => _DenylistTabState();
}

class _DenylistTabState extends ConsumerState<DenylistTab> {
  final TextEditingController _controller = TextEditingController();

  void _addDomain() {
    final text = _controller.text.trim();
    if (text.isNotEmpty) {
      ref.read(denylistProvider.notifier).add(text);
      _controller.clear();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final denylist = ref.watch(denylistProvider);
    final strictState = ref.watch(strictModeProvider);
    final palette = WabiSabiPalette.of(context);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: palette.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Denylist',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: palette.ink,
              letterSpacing: -0.2,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            'Block specific domains and subdomains from resolving. You can also use asterisks as wildcards (*.ads.com).',
            style: TextStyle(fontSize: 11, color: palette.mutedInk, height: 1.4),
          ),
          const SizedBox(height: 14),

          // INPUT ROW
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _controller,
                  style: TextStyle(fontSize: 13, color: palette.ink),
                  onSubmitted: (_) => _addDomain(),
                  decoration: InputDecoration(
                    hintText: 'Add a domain (e.g. tracking.com)',
                    hintStyle: TextStyle(color: palette.mutedInk, fontSize: 12),
                    filled: true,
                    fillColor: palette.canvas,
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(color: palette.border),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(color: palette.border),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(color: palette.ink),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              ElevatedButton(
                onPressed: _addDomain,
                style: ElevatedButton.styleFrom(
                  backgroundColor: palette.ink,
                  foregroundColor: palette.canvas,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                ),
                child: const Text(
                  'ADD',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // DOMAINS LIST
          if (denylist.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 24.0),
              child: Center(
                child: Text(
                  'No domains on denylist',
                  style: TextStyle(fontSize: 12, color: palette.mutedInk),
                ),
              ),
            )
          else
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: denylist.length,
              separatorBuilder: (_, __) =>
                  Divider(color: palette.border, height: 1),
              itemBuilder: (context, index) {
                final domain = denylist[index];
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8.0),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        domain,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          color: palette.ink,
                        ),
                      ),
                      IconButton(
                        icon: Icon(Icons.close, color: palette.mutedInk, size: 16),
                        onPressed: () {
                          if (strictState.isStrict) {
                            ScaffoldMessenger.of(context).clearSnackBars();
                            final mins = (strictState.remainingSeconds / 60).ceil();
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  strictState.remainingSeconds > 0
                                      ? '🔒 Strict Mode active ($mins min remaining). Cannot remove domains from denylist until timer expires.'
                                      : '🔒 Strict Mode active. Cannot remove domains from denylist until session ends.',
                                ),
                                backgroundColor: palette.surface,
                              ),
                            );
                            return;
                          }
                          ref.read(denylistProvider.notifier).remove(domain);
                        },
                        constraints: const BoxConstraints(),
                        padding: const EdgeInsets.all(4),
                      ),
                    ],
                  ),
                );
              },
            ),
        ],
      ),
    );
  }
}
