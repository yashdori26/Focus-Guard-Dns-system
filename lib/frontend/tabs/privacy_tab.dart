import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/enums.dart';
import '../../state_management/providers.dart';
import '../theme/wabi_sabi_theme.dart';
import '../ui_helpers.dart';

class PrivacyTab extends ConsumerWidget {
  const PrivacyTab({super.key});

  void _onToggle(BuildContext context, WidgetRef ref, StrictModeState strictState, PrivacyFeature feature, bool val) {
    final palette = WabiSabiPalette.of(context);
    if (!val && feature == PrivacyFeature.disguisedTrackers && strictState.isStrict) {
      ScaffoldMessenger.of(context).clearSnackBars();
      final mins = (strictState.remainingSeconds / 60).ceil();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            strictState.remainingSeconds > 0
                ? '🔒 Strict Mode active ($mins min remaining). Cannot disable tracker protection until timer expires.'
                : '🔒 Strict Mode active. Cannot disable tracker protection until session ends.',
          ),
          backgroundColor: palette.surface,
        ),
      );
      return;
    }
    ref.read(privacyProvider.notifier).toggle(feature, val);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final privacyState = ref.watch(privacyProvider);
    final strictState = ref.watch(strictModeProvider);
    final palette = WabiSabiPalette.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        secCard(
          'Blocklists',
          'Select and manage the primary lists used to block ads and invasive tracking scripts.',
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: palette.canvas,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: palette.border),
            ),
            child: Row(
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: palette.surface,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: palette.border),
                  ),
                  child: Center(
                    child: Icon(Icons.shield_outlined, color: palette.ink, size: 18),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'FocusDNS Ads & Trackers Blocklist',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: palette.ink,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '43,921 rules applied',
                        style: TextStyle(fontSize: 10, color: palette.mutedInk),
                      ),
                    ],
                  ),
                ),
                Icon(Icons.check_circle_outline, color: palette.ink, size: 20),
              ],
            ),
          ),
        ),
        secCard(
          'Tracking Protection',
          'Enhance privacy by stopping sophisticated evasive trackers.',
          child: Column(
            children: [
              switchRow(
                'Block Disguised Third-Party Trackers',
                'Block first-party subdomains configured via CNAME to bypass ad-blockers.',
                privacyState[PrivacyFeature.disguisedTrackers] ?? true,
                (val) => _onToggle(context, ref, strictState, PrivacyFeature.disguisedTrackers, val),
              ),
              Divider(color: palette.border, height: 16),
              switchRow(
                'Allow Affiliate & Referral Links',
                'Do not block links modified by search engines or influencers for referral commissions.',
                privacyState[PrivacyFeature.affiliateLinks] ?? false,
                (val) => _onToggle(context, ref, strictState, PrivacyFeature.affiliateLinks, val),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
