import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../state_management/providers.dart';
import 'tabs/allowlist_tab.dart';
import 'tabs/analytics_tab.dart';
import 'tabs/deep_focus_tab.dart';
import 'tabs/denylist_tab.dart';
import 'tabs/logs_tab.dart';
import 'tabs/privacy_tab.dart';
import 'tabs/security_tab.dart';
import 'tabs/settings_tab.dart';
import 'tabs/setup_tab.dart';
import 'theme/wabi_sabi_theme.dart';

class AllProfileSettingsSheet extends ConsumerStatefulWidget {
  final int initialTabIndex;
  const AllProfileSettingsSheet({super.key, this.initialTabIndex = 0});

  @override
  ConsumerState<AllProfileSettingsSheet> createState() =>
      _AllProfileSettingsSheetState();
}

class _AllProfileSettingsSheetState
    extends ConsumerState<AllProfileSettingsSheet> {
  late int _selectedTabIndex;

  final List<String> _tabs = [
    'Setup',
    'Security',
    'Privacy',
    'Deep Focus',
    'Denylist',
    'Allowlist',
    'Analytics',
    'Logs',
    'Settings',
  ];

  @override
  void initState() {
    super.initState();
    _selectedTabIndex = widget.initialTabIndex;
    try {
      final tabParam = Uri.base.queryParameters['tab'];
      if (tabParam != null) {
        final parsed = int.tryParse(tabParam);
        if (parsed != null && parsed >= 0 && parsed < _tabs.length) {
          _selectedTabIndex = parsed;
        } else if (tabParam.toLowerCase() == 'setup') {
          _selectedTabIndex = 0;
        } else if (tabParam.toLowerCase() == 'security') {
          _selectedTabIndex = 1;
        }
      }
    } catch (_) {}
  }

  Widget _buildTabBodyContent() {
    switch (_selectedTabIndex) {
      case 0:
        return const SetupTab();
      case 1:
        return const SecurityTab();
      case 2:
        return const PrivacyTab();
      case 3:
        return const DeepFocusTab();
      case 4:
        return const DenylistTab();
      case 5:
        return const AllowlistTab();
      case 6:
        return const AnalyticsTab();
      case 7:
        return const LogsTab();
      case 8:
        return const SettingsTab();
      default:
        return const SizedBox.shrink();
    }
  }

  @override
  Widget build(BuildContext context) {
    final profileName = ref.watch(settingsProvider).profileName;
    final themeMode = ref.watch(themeModeProvider);
    final palette = themeMode == ThemeMode.light
        ? WabiSabiPalette.light
        : WabiSabiPalette.dark;

    return Container(
      height: MediaQuery.of(context).size.height * 0.90,
      decoration: BoxDecoration(
        color: palette.canvas,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        border: Border(
          top: BorderSide(color: palette.border, width: 1),
          left: BorderSide(color: palette.border, width: 1),
          right: BorderSide(color: palette.border, width: 1),
        ),
      ),
      child: Column(
        children: [
          // TOP DRAG HANDLE & CLOSE
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 16, 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: palette.ink,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      profileName,
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.bold,
                        color: palette.ink,
                        letterSpacing: -0.3,
                      ),
                    ),
                  ],
                ),
                IconButton(
                  icon: Icon(Icons.close, color: palette.mutedInk, size: 20),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
          ),

          // TAB BAR WITH WABI-SABI HAIRLINE
          Container(
            height: 44,
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: palette.border)),
            ),
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: _tabs.length,
              itemBuilder: (context, index) {
                final isActive = _selectedTabIndex == index;
                return GestureDetector(
                  onTap: () => setState(() => _selectedTabIndex = index),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 12,
                    ),
                    decoration: BoxDecoration(
                      border: Border(
                        bottom: BorderSide(
                          color: isActive
                              ? palette.ink
                              : Colors.transparent,
                          width: 2,
                        ),
                      ),
                    ),
                    child: Text(
                      _tabs[index],
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: isActive ? FontWeight.bold : FontWeight.w500,
                        color: isActive ? palette.ink : palette.mutedInk,
                      ),
                    ),
                  ),
                );
              },
            ),
          ),

          // TAB BODY
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: _buildTabBodyContent(),
            ),
          ),
        ],
      ),
    );
  }
}
