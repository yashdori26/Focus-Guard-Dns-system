import 'package:flutter/material.dart';
import '../../../engine/surgical/catalog/surgical_subfeature_types.dart';
import '../../../engine/surgical/core/mindful_nudge_coordinator.dart';

/// Configurator screen for mindful interstitial pause delays, cognitive friction pledges,
/// and reflection oath themes.
class MindfulInterstitialCustomizerScreen extends StatefulWidget {
  final MindfulNudgeCoordinator? coordinator;

  const MindfulInterstitialCustomizerScreen({
    super.key,
    this.coordinator,
  });

  @override
  State<MindfulInterstitialCustomizerScreen> createState() =>
      _MindfulInterstitialCustomizerScreenState();
}

class _MindfulInterstitialCustomizerScreenState
    extends State<MindfulInterstitialCustomizerScreen> {
  late MindfulNudgeCoordinator _coordinator;

  double _countdownSeconds = 10.0;
  String _selectedTheme = 'Zen Minimalist';
  bool _requirePledge = false;
  double _dailyTokens = 3.0;

  final TextEditingController _pledgeController = TextEditingController(
    text: 'I choose deep work over short reels',
  );

  final List<String> _themes = [
    'Zen Minimalist',
    'Digital Stoic',
    'Neural Focus',
    'High Energy',
  ];

  @override
  void initState() {
    super.initState();
    _coordinator = widget.coordinator ?? MindfulNudgeCoordinator();
  }

  @override
  void dispose() {
    _pledgeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final scaffoldBg = isDark ? const Color(0xFF13151B) : const Color(0xFFF8FAFC);
    final cardColor = isDark ? const Color(0xFF1E222B) : Colors.white;

    return Scaffold(
      backgroundColor: scaffoldBg,
      appBar: AppBar(
        title: const Text('Mindful Nudge Settings'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Hero Intro Card
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: cardColor,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: isDark ? const Color(0xFF2C3240) : const Color(0xFFE2E7F0),
                ),
              ),
              child: Row(
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: const Color(0xFF8B5CF6).withAlpha(25),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: const Icon(
                      Icons.spa_rounded,
                      color: Color(0xFF8B5CF6),
                      size: 26,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Mindful Reflection Pause',
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Breaks automatic impulse loops with conscious friction.',
                          style: TextStyle(
                            fontSize: 11,
                            color: isDark ? Colors.white60 : Colors.black54,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Countdown Duration Slider
            _buildSectionCard(
              title: 'PAUSE COUNTDOWN DURATION',
              isDark: isDark,
              cardColor: cardColor,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Mandatory Pause Time:', style: TextStyle(fontSize: 14)),
                    Text(
                      '${_countdownSeconds.toInt()} seconds',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                        color: Color(0xFF8B5CF6),
                      ),
                    ),
                  ],
                ),
                Slider(
                  value: _countdownSeconds,
                  min: 5,
                  max: 60,
                  divisions: 11,
                  activeColor: const Color(0xFF8B5CF6),
                  onChanged: (val) {
                    setState(() {
                      _countdownSeconds = val;
                    });
                  },
                ),
                Text(
                  'Research shows a 10-second friction pause reduces impulse doomscrolling by 74%.',
                  style: TextStyle(
                    fontSize: 11,
                    color: isDark ? Colors.white54 : Colors.black54,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Theme Selection
            _buildSectionCard(
              title: 'REFLECTION VISUAL THEME',
              isDark: isDark,
              cardColor: cardColor,
              children: [
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: _themes.map((theme) {
                    final isSel = _selectedTheme == theme;
                    return ChoiceChip(
                      label: Text(theme),
                      selected: isSel,
                      selectedColor: const Color(0xFF8B5CF6).withAlpha(40),
                      labelStyle: TextStyle(
                        color: isSel ? const Color(0xFF8B5CF6) : null,
                        fontWeight: isSel ? FontWeight.bold : FontWeight.normal,
                      ),
                      onSelected: (val) {
                        setState(() {
                          _selectedTheme = theme;
                        });
                      },
                    );
                  }).toList(),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Cognitive Friction Pledge Challenge
            _buildSectionCard(
              title: 'COGNITIVE FRICTION PLEDGE',
              isDark: isDark,
              cardColor: cardColor,
              children: [
                Material(
                  color: Colors.transparent,
                  child: SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Require Typing Pledge to Bypass'),
                    subtitle: const Text(
                      'Forces deliberate neuro-cognitive intent before granting access.',
                      style: TextStyle(fontSize: 11),
                    ),
                    value: _requirePledge,
                    activeColor: const Color(0xFF8B5CF6),
                    onChanged: (val) {
                      setState(() {
                        _requirePledge = val;
                      });
                    },
                  ),
                ),
                if (_requirePledge) ...[
                  const SizedBox(height: 10),
                  TextField(
                    controller: _pledgeController,
                    decoration: InputDecoration(
                      labelText: 'Pledge Phrase to Type',
                      hintText: 'Enter required pledge...',
                      filled: true,
                      fillColor: isDark ? const Color(0xFF13151B) : const Color(0xFFF1F5F9),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 16),

            // Daily Bypass Token Allowance
            _buildSectionCard(
              title: 'DAILY BYPASS QUOTA',
              isDark: isDark,
              cardColor: cardColor,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Daily Allowed Bypasses:'),
                    Text(
                      '${_dailyTokens.toInt()} tokens/day',
                      style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF8B5CF6)),
                    ),
                  ],
                ),
                Slider(
                  value: _dailyTokens,
                  min: 1,
                  max: 10,
                  divisions: 9,
                  activeColor: const Color(0xFF8B5CF6),
                  onChanged: (val) {
                    setState(() {
                      _dailyTokens = val;
                    });
                  },
                ),
                Text(
                  'Once daily bypass tokens are exhausted, strict enforcement prevents opening until midnight.',
                  style: TextStyle(
                    fontSize: 11,
                    color: isDark ? Colors.white54 : Colors.black54,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),

            // Live Interactive Preview Button
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton.icon(
                onPressed: _showLivePreviewDialog,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF8B5CF6),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                ),
                icon: const Icon(Icons.preview_rounded),
                label: const Text(
                  'Test & Preview Mindful Nudge Dialog',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                ),
              ),
            ),
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionCard({
    required String title,
    required bool isDark,
    required Color cardColor,
    required List<Widget> children,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isDark ? const Color(0xFF2C3240) : const Color(0xFFE2E7F0),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.0,
              color: Colors.grey,
            ),
          ),
          const SizedBox(height: 12),
          ...children,
        ],
      ),
    );
  }

  void _showLivePreviewDialog() {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          title: const Row(
            children: [
              Icon(Icons.spa_rounded, color: Color(0xFF8B5CF6)),
              SizedBox(width: 10),
              Text('Pause for Focus'),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'You opened Instagram for Direct Messages. Are you sure you want to surrender your attention to Reels?',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 14),
              ),
              const SizedBox(height: 16),
              Container(
                width: 60,
                height: 60,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: const Color(0xFF8B5CF6), width: 3),
                ),
                alignment: Alignment.center,
                child: Text(
                  '${_countdownSeconds.toInt()}',
                  style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
              ),
              if (_requirePledge) ...[
                const SizedBox(height: 16),
                Text(
                  'Pledge: "${_pledgeController.text}"',
                  style: const TextStyle(fontSize: 12, fontStyle: FontStyle.italic),
                ),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Protect My Focus & Return'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Bypass'),
            ),
          ],
        );
      },
    );
  }
}
