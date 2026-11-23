import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/enums.dart';
import '../../state_management/providers.dart';
import '../theme/wabi_sabi_theme.dart';
import '../ui_helpers.dart';

class SecurityTab extends ConsumerWidget {
  const SecurityTab({super.key});

  void _onToggle(BuildContext context, WidgetRef ref, StrictModeState strictState, SecurityFeature feature, bool val) {
    final palette = WabiSabiPalette.of(context);
    if (!val && strictState.isStrict) {
      ScaffoldMessenger.of(context).clearSnackBars();
      final mins = (strictState.remainingSeconds / 60).ceil();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            strictState.remainingSeconds > 0
                ? '🔒 Strict Mode active ($mins min remaining). Cannot disable security features until timer expires.'
                : '🔒 Strict Mode active. Cannot disable security features until session ends.',
          ),
          backgroundColor: palette.surface,
        ),
      );
      return;
    }
    ref.read(securityProvider.notifier).toggle(feature, val);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final securityState = ref.watch(securityProvider);
    final strictState = ref.watch(strictModeProvider);

    return Column(
      children: [
        secCard(
          'Threat Intelligence Feeds',
          'Block malware, phishing, and command & control servers using aggregated threat intelligence feeds.',
          child: switchRow(
            'Threat Intelligence',
            'Block known malicious domains',
            securityState[SecurityFeature.threatIntel] ?? true,
            (val) => _onToggle(context, ref, strictState, SecurityFeature.threatIntel, val),
          ),
        ),
        secCard(
          'AI Threat Detection',
          'Identify and block zero-day attacks and newly generated malicious domains in real time using AI heuristics.',
          child: switchRow(
            'AI Threat Detection',
            'Block unknown zero-day threats',
            securityState[SecurityFeature.aiThreat] ?? false,
            (val) => _onToggle(context, ref, strictState, SecurityFeature.aiThreat, val),
          ),
        ),
        secCard(
          'Google Safe Browsing',
          'Check hostnames against Google Safe Browsing lists of unsafe web resources.',
          child: switchRow(
            'Google Safe Browsing',
            'Block dangerous and deceptive sites',
            securityState[SecurityFeature.googleSafe] ?? true,
            (val) => _onToggle(context, ref, strictState, SecurityFeature.googleSafe, val),
          ),
        ),
        secCard(
          'Cryptojacking Protection',
          'Block web pages and scripts from mining cryptocurrency on your devices without your explicit consent.',
          child: switchRow(
            'Cryptojacking Protection',
            'Block in-browser cryptocurrency mining',
            securityState[SecurityFeature.cryptojacking] ?? true,
            (val) => _onToggle(context, ref, strictState, SecurityFeature.cryptojacking, val),
          ),
        ),
        secCard(
          'DNS Rebinding Protection',
          'Prevent malicious public websites from routing DNS responses to local private IP networks (RFC 1918).',
          child: switchRow(
            'DNS Rebinding Protection',
            'Block attacks targeting local router & IoT',
            securityState[SecurityFeature.dnsRebinding] ?? true,
            (val) => _onToggle(context, ref, strictState, SecurityFeature.dnsRebinding, val),
          ),
        ),
        secCard(
          'Enforce SafeSearch',
          'Force strict SafeSearch across Google, Bing, and DuckDuckGo via canonical DNS virtual IP rewriting.',
          child: switchRow(
            'Enforce SafeSearch',
            'Filter explicit search engine results',
            securityState[SecurityFeature.safesearch] ?? true,
            (val) => _onToggle(context, ref, strictState, SecurityFeature.safesearch, val),
          ),
        ),
        secCard(
          'YouTube Restricted Mode',
          'Lock YouTube into Strict Restricted Mode across apps and web browsers via restrict.youtube.com rewrite.',
          child: switchRow(
            'YouTube Restricted Mode',
            'Hide mature & explicit videos',
            securityState[SecurityFeature.youtubeRestricted] ?? false,
            (val) => _onToggle(context, ref, strictState, SecurityFeature.youtubeRestricted, val),
          ),
        ),
      ],
    );
  }
}
