import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/enums.dart';
import '../../state_management/providers.dart';
import '../theme/wabi_sabi_theme.dart';
import '../ui_helpers.dart';
import '../mdm_shield_card.dart';

class SettingsTab extends ConsumerStatefulWidget {
  const SettingsTab({super.key});

  @override
  ConsumerState<SettingsTab> createState() => _SettingsTabState();
}

class _SettingsTabState extends ConsumerState<SettingsTab> {
  late TextEditingController _nameController;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(
      text: ref.read(settingsProvider).profileName,
    );
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider);
    final themeMode = ref.watch(themeModeProvider);
    final palette = WabiSabiPalette.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // DEVICE ADMINISTRATOR & ANTI-UNINSTALL SHIELD
        const MdmShieldCard(),
        const SizedBox(height: 16),

        // THEME MODE SWITCHER
        secCard(
          'Appearance',
          'Switch between Warm Stone Paper (Light) and Charcoal Night (Dark).',
          child: Row(
            children: [
              Expanded(
                child: GestureDetector(
                  onTap: () => ref.read(themeModeProvider.notifier).setMode(ThemeMode.dark),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    decoration: BoxDecoration(
                      color: themeMode == ThemeMode.dark ? palette.ink : palette.canvas,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: palette.border),
                    ),
                    child: Center(
                      child: Text(
                        'Charcoal Dark',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: themeMode == ThemeMode.dark ? palette.canvas : palette.ink,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: GestureDetector(
                  onTap: () => ref.read(themeModeProvider.notifier).setMode(ThemeMode.light),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    decoration: BoxDecoration(
                      color: themeMode == ThemeMode.light ? palette.ink : palette.canvas,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: palette.border),
                    ),
                    child: Center(
                      child: Text(
                        'Stone Light',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: themeMode == ThemeMode.light ? palette.canvas : palette.ink,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),

        // PROFILE NAME
        secCard(
          'Profile Name',
          'Give your profile an identifiable name across your devices.',
          child: TextField(
            controller: _nameController,
            style: TextStyle(fontSize: 14, color: palette.ink),
            onChanged: (val) {
              ref.read(settingsProvider.notifier).updateProfileName(val);
            },
            decoration: InputDecoration(
              filled: true,
              fillColor: palette.canvas,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
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

        // LOG RETENTION
        secCard(
          'Log Retention',
          'Choose how long DNS query logs are stored on FocusDNS servers.',
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            decoration: BoxDecoration(
              color: palette.canvas,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: palette.border),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: settings.logRetention,
                isExpanded: true,
                dropdownColor: palette.surface,
                style: TextStyle(fontSize: 13, color: palette.ink),
                icon: Icon(Icons.arrow_drop_down, color: palette.mutedInk),
                items: const [
                  DropdownMenuItem(value: '1 hour', child: Text('1 hour')),
                  DropdownMenuItem(value: '1 day', child: Text('1 day')),
                  DropdownMenuItem(value: '1 week', child: Text('1 week')),
                  DropdownMenuItem(value: '1 month', child: Text('1 month')),
                ],
                onChanged: (val) {
                  if (val != null) {
                    ref.read(settingsProvider.notifier).updateLogRetention(val);
                  }
                },
              ),
            ),
          ),
        ),

        // WEB3 DOMAINS
        secCard(
          'Web3 Domains',
          'Resolve decentralized blockchain domains natively without browser extensions.',
          child: Column(
            children: [
              switchRow(
                'Ethereum Name Service (ENS)',
                'Resolve .eth blockchain domains',
                settings.web3[Web3Feature.ens] ?? true,
                (val) => ref
                    .read(settingsProvider.notifier)
                    .toggleWeb3(Web3Feature.ens, val),
              ),
              Divider(color: palette.border, height: 16),
              switchRow(
                'Unstoppable Domains',
                'Resolve .crypto, .nft, .x, .wallet domains',
                settings.web3[Web3Feature.unstoppable] ?? true,
                (val) => ref
                    .read(settingsProvider.notifier)
                    .toggleWeb3(Web3Feature.unstoppable, val),
              ),
              Divider(color: palette.border, height: 16),
              switchRow(
                'IPFS Gateway',
                'Resolve decentralized IPFS web content natively',
                settings.web3[Web3Feature.ipfs] ?? true,
                (val) => ref
                    .read(settingsProvider.notifier)
                    .toggleWeb3(Web3Feature.ipfs, val),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
