import 'package:flutter/material.dart';

enum OverlayThemeStyle {
  cyberpunkDark,
  forestZen,
  crimsonWarning,
  minimalistSlate,
}

/// Screen allowing customization and live preview of the floating Android WindowManager lockout HUD.
class OverlayCustomizerScreen extends StatefulWidget {
  const OverlayCustomizerScreen({super.key});

  @override
  State<OverlayCustomizerScreen> createState() => _OverlayCustomizerScreenState();
}

class _OverlayCustomizerScreenState extends State<OverlayCustomizerScreen> {
  OverlayThemeStyle _selectedTheme = OverlayThemeStyle.cyberpunkDark;
  bool _showInterventionCount = true;
  bool _showProductiveSwapButton = true;
  String _customMotto = 'Guard your attention. It is your only non-renewable asset.';

  Color _getBgColor() {
    switch (_selectedTheme) {
      case OverlayThemeStyle.cyberpunkDark:
        return const Color(0xFF090D16);
      case OverlayThemeStyle.forestZen:
        return const Color(0xFF062C1E);
      case OverlayThemeStyle.crimsonWarning:
        return const Color(0xFF2B0B0E);
      case OverlayThemeStyle.minimalistSlate:
        return const Color(0xFF1E293B);
    }
  }

  Color _getAccentColor() {
    switch (_selectedTheme) {
      case OverlayThemeStyle.cyberpunkDark:
        return const Color(0xFF38BDF8);
      case OverlayThemeStyle.forestZen:
        return const Color(0xFF10B981);
      case OverlayThemeStyle.crimsonWarning:
        return const Color(0xFFEF4444);
      case OverlayThemeStyle.minimalistSlate:
        return const Color(0xFF94A3B8);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bgColor = _getBgColor();
    final accentColor = _getAccentColor();

    return Scaffold(
      backgroundColor: const Color(0xFF090D16),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0F172A),
        elevation: 0,
        title: const Text(
          'Lockout Overlay HUD Customizer',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Live HUD Preview',
              style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),

            // Live Mock Phone Preview
            Container(
              height: 280,
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: bgColor,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: accentColor.withValues(alpha: 0.5), width: 2),
                boxShadow: [
                  BoxShadow(
                    color: accentColor.withValues(alpha: 0.15),
                    blurRadius: 16,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.shield_rounded, color: accentColor, size: 40),
                  const SizedBox(height: 10),
                  const Text(
                    'Instagram is Strictly Locked',
                    style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Time Remaining: 3h 45m',
                    style: TextStyle(color: accentColor, fontSize: 14, fontWeight: FontWeight.w600),
                  ),
                  if (_showInterventionCount) ...[
                    const SizedBox(height: 6),
                    const Text(
                      'Blocked launch attempts: 7 today',
                      style: TextStyle(color: Colors.white54, fontSize: 11),
                    ),
                  ],
                  const SizedBox(height: 12),
                  Text(
                    '"$_customMotto"',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.white70,
                      fontStyle: FontStyle.italic,
                      fontSize: 11,
                    ),
                  ),
                  if (_showProductiveSwapButton) ...[
                    const SizedBox(height: 14),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: accentColor,
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      ),
                      onPressed: () {},
                      child: const Text('Open Kindle Instead', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 12)),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 24),

            const Text(
              'Theme Aesthetics',
              style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                _buildThemeChip(OverlayThemeStyle.cyberpunkDark, 'Cyberpunk'),
                const SizedBox(width: 8),
                _buildThemeChip(OverlayThemeStyle.forestZen, 'Forest Zen'),
                const SizedBox(width: 8),
                _buildThemeChip(OverlayThemeStyle.crimsonWarning, 'Crimson'),
                const SizedBox(width: 8),
                _buildThemeChip(OverlayThemeStyle.minimalistSlate, 'Slate'),
              ],
            ),
            const SizedBox(height: 24),

            // Toggles
            SwitchListTile(
              title: const Text('Show Blocked Intervention Counter', style: TextStyle(color: Colors.white, fontSize: 14)),
              subtitle: const Text('Displays how many times you attempted to open the locked app.', style: TextStyle(color: Colors.white54, fontSize: 12)),
              value: _showInterventionCount,
              activeColor: const Color(0xFF3B82F6),
              onChanged: (val) => setState(() => _showInterventionCount = val),
            ),
            SwitchListTile(
              title: const Text('Show Productive Swap Launcher', style: TextStyle(color: Colors.white, fontSize: 14)),
              subtitle: const Text('Displays a 1-tap shortcut to open Kindle, Notion, or Duolingo.', style: TextStyle(color: Colors.white54, fontSize: 12)),
              value: _showProductiveSwapButton,
              activeColor: const Color(0xFF3B82F6),
              onChanged: (val) => setState(() => _showProductiveSwapButton = val),
            ),
            const SizedBox(height: 16),

            // Motto Editor
            const Text(
              'Custom Motivational Motto',
              style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            TextField(
              style: const TextStyle(color: Colors.white),
              controller: TextEditingController(text: _customMotto),
              onChanged: (val) => _customMotto = val,
              decoration: InputDecoration(
                filled: true,
                fillColor: const Color(0xFF131B2E),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildThemeChip(OverlayThemeStyle style, String label) {
    final isSelected = _selectedTheme == style;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _selectedTheme = style),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: isSelected ? const Color(0xFF3B82F6) : const Color(0xFF131B2E),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: isSelected ? const Color(0xFF60A5FA) : Colors.white12,
            ),
          ),
          child: Center(
            child: Text(
              label,
              style: TextStyle(
                color: isSelected ? Colors.white : Colors.white70,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                fontSize: 11,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
