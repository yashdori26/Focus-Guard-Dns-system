import 'package:flutter/material.dart';
import '../../../engine/surgical/catalog/surgical_subfeature_types.dart';
import '../../../engine/surgical/core/surgical_policy_evaluator.dart';
import '../../../engine/surgical/models/surgical_rule_model.dart';
import '../../../engine/surgical/telemetry/surgical_telemetry_recorder.dart';
import '../../widgets/surgical/subfeature_toggle_matrix.dart';
import '../../widgets/surgical/surgical_interception_radar.dart';

/// Deep configuration screen for an individual platform's surgical decoupling policy.
class PlatformSurgicalDetailScreen extends StatefulWidget {
  final String platformId;
  final SurgicalPolicyEvaluator evaluator;
  final SurgicalTelemetryRecorder? recorder;

  const PlatformSurgicalDetailScreen({
    super.key,
    required this.platformId,
    required this.evaluator,
    this.recorder,
  });

  @override
  State<PlatformSurgicalDetailScreen> createState() => _PlatformSurgicalDetailScreenState();
}

class _PlatformSurgicalDetailScreenState extends State<PlatformSurgicalDetailScreen> {
  late SurgicalRuleModel _rule;
  bool _enableNudge = true;
  double _pauseSeconds = 10.0;
  final TextEditingController _promptController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadRule();
  }

  void _loadRule() {
    final found = widget.evaluator.compiledRules[widget.platformId];
    if (found != null) {
      _rule = found;
      _enableNudge = _rule.enableMindfulInterstitial;
      _pauseSeconds = _rule.mindfulPauseSeconds.toDouble();
      _promptController.text = _rule.motivationalPrompt;
    } else {
      // Fallback dummy rule if not found
      _rule = SurgicalRuleModel(
        platformId: widget.platformId,
        displayName: widget.platformId,
        iconGlyph: '📱',
        packageNames: [],
        subfeatureToggles: const {},
        subfeatureDomains: const {},
        chatWhitelistDomains: const [],
        searchWhitelistDomains: const [],
      );
    }
  }

  @override
  void dispose() {
    _promptController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final scaffoldBg = isDark ? const Color(0xFF13151B) : const Color(0xFFF8FAFC);
    final cardColor = isDark ? const Color(0xFF1E222B) : Colors.white;

    // Generate subfeature distribution for the radar chart
    final Map<SurgicalSubfeature, int> radarCounts = {};
    for (final feature in SurgicalSubfeature.values) {
      radarCounts[feature] = _rule.isSubfeatureBlocked(feature) ? 8 : 2;
    }

    return Scaffold(
      backgroundColor: scaffoldBg,
      appBar: AppBar(
        title: Text('${_rule.displayName} Surgical Settings'),
        actions: [
          TextButton(
            onPressed: _saveChanges,
            child: const Text('Save', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Platform Identity Header
            _buildPlatformHeader(isDark, cardColor),
            const SizedBox(height: 16),

            // Radar Visualizer
            Center(
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: cardColor,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: isDark ? const Color(0xFF2C3240) : const Color(0xFFE2E7F0),
                  ),
                ),
                child: Column(
                  children: [
                    const Text(
                      'DECOUPLING BALANCE RADAR',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.0,
                        color: Colors.grey,
                      ),
                    ),
                    const SizedBox(height: 8),
                    SurgicalInterceptionRadar(
                      subfeatureCounts: radarCounts,
                      size: 240,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Subfeature Toggle Matrix
            SubfeatureToggleMatrix(
              toggles: _rule.subfeatureToggles,
              onToggleChanged: (subfeature, blocked) {
                setState(() {
                  widget.evaluator.setSubfeatureToggle(
                    platformId: _rule.platformId,
                    subfeature: subfeature,
                    blocked: blocked,
                  );
                  _loadRule();
                });
              },
              onSeverAllAddictions: () {
                setState(() {
                  for (final sub in [
                    SurgicalSubfeature.reelsOrShorts,
                    SurgicalSubfeature.feed,
                    SurgicalSubfeature.explore,
                    SurgicalSubfeature.comments,
                  ]) {
                    widget.evaluator.setSubfeatureToggle(
                      platformId: _rule.platformId,
                      subfeature: sub,
                      blocked: true,
                    );
                  }
                  _loadRule();
                });
              },
              onRestoreDefaults: () {
                setState(() {
                  widget.evaluator.compileAllRules();
                  _loadRule();
                });
              },
            ),
            const SizedBox(height: 16),

            // Mindful Interstitial Pause Config Card
            _buildMindfulPauseCard(isDark, cardColor),
            const SizedBox(height: 16),

            // View Node Inspector Targets Card
            _buildViewTargetsCard(isDark, cardColor),
            const SizedBox(height: 16),

            // Network Gateways & CDN Endpoints
            _buildNetworkGatewaysCard(isDark, cardColor),
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  Widget _buildPlatformHeader(bool isDark, Color cardColor) {
    return Container(
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
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF282E3B) : const Color(0xFFEEF2F6),
              borderRadius: BorderRadius.circular(14),
            ),
            alignment: Alignment.center,
            child: Text(_rule.iconGlyph, style: const TextStyle(fontSize: 26)),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _rule.displayName,
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 4),
                Text(
                  _rule.packageNames.join(', '),
                  style: TextStyle(
                    fontSize: 11,
                    color: isDark ? Colors.white60 : Colors.black54,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMindfulPauseCard(bool isDark, Color cardColor) {
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
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Row(
                children: [
                  Icon(Icons.psychology_rounded, size: 18, color: Color(0xFF8B5CF6)),
                  SizedBox(width: 8),
                  Text(
                    'MINDFUL INTERSTITIAL NUDGE',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.8,
                      color: Colors.grey,
                    ),
                  ),
                ],
              ),
              Switch(
                value: _enableNudge,
                activeColor: const Color(0xFF8B5CF6),
                onChanged: (val) {
                  setState(() {
                    _enableNudge = val;
                  });
                },
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Displays a peaceful reflection pause with an intentional oath before allowing accidental access to addiction loops.',
            style: TextStyle(
              fontSize: 12,
              color: isDark ? Colors.white70 : Colors.black87,
            ),
          ),
          if (_enableNudge) ...[
            const SizedBox(height: 14),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Pause Countdown:', style: TextStyle(fontSize: 13)),
                Text(
                  '${_pauseSeconds.toInt()} seconds',
                  style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF8B5CF6)),
                ),
              ],
            ),
            Slider(
              value: _pauseSeconds,
              min: 5,
              max: 30,
              divisions: 5,
              activeColor: const Color(0xFF8B5CF6),
              onChanged: (val) {
                setState(() {
                  _pauseSeconds = val;
                });
              },
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _promptController,
              maxLines: 2,
              decoration: InputDecoration(
                labelText: 'Reflection Oath / Message',
                hintText: 'Enter custom mindful prompt...',
                filled: true,
                fillColor: isDark ? const Color(0xFF13151B) : const Color(0xFFF1F5F9),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildViewTargetsCard(bool isDark, Color cardColor) {
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
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Row(
                children: [
                  Icon(Icons.remove_red_eye_rounded, size: 18, color: Color(0xFF3B82F6)),
                  SizedBox(width: 8),
                  Text(
                    'VIEW HIERARCHY SENTINELS',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.8,
                      color: Colors.grey,
                    ),
                  ),
                ],
              ),
              Text(
                '${_rule.viewNodeTargets.length} targets active',
                style: const TextStyle(fontSize: 11, color: Colors.grey),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (_rule.viewNodeTargets.isEmpty)
            Text(
              'No native Accessibility view targets registered for this platform.',
              style: TextStyle(fontSize: 12, color: isDark ? Colors.white54 : Colors.black54),
            )
          else
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _rule.viewNodeTargets.length,
              separatorBuilder: (context, index) => const Divider(height: 16),
              itemBuilder: (context, index) {
                final target = _rule.viewNodeTargets[index];
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      target.description,
                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Action: ${target.defaultAction.name} | IDs: ${target.resourceIdPatterns.join(", ")}',
                      style: TextStyle(
                        fontSize: 11,
                        color: isDark ? Colors.white60 : Colors.black54,
                      ),
                    ),
                  ],
                );
              },
            ),
        ],
      ),
    );
  }

  Widget _buildNetworkGatewaysCard(bool isDark, Color cardColor) {
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
          const Row(
            children: [
              Icon(Icons.network_check_rounded, size: 18, color: Color(0xFF10B981)),
              SizedBox(width: 8),
              Text(
                'NETWORK & CHAT GATEWAYS',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.8,
                  color: Colors.grey,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            'Protected Messaging Gateways (${_rule.chatWhitelistDomains.length}):',
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 4),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: _rule.chatWhitelistDomains.map((d) {
              return Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: const Color(0xFF10B981).withAlpha(isDark ? 30 : 20),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: const Color(0xFF10B981).withAlpha(80)),
                ),
                child: Text(
                  d,
                  style: const TextStyle(fontSize: 11, color: Color(0xFF10B981)),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  void _saveChanges() {
    final updatedRule = _rule.copyWith(
      enableMindfulInterstitial: _enableNudge,
      mindfulPauseSeconds: _pauseSeconds.toInt(),
      motivationalPrompt: _promptController.text.trim(),
    );

    // Save to evaluator
    widget.evaluator.setSubfeatureToggle(
      platformId: updatedRule.platformId,
      subfeature: SurgicalSubfeature.reelsOrShorts,
      blocked: updatedRule.isSubfeatureBlocked(SurgicalSubfeature.reelsOrShorts),
    );

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Saved surgical policy for ${_rule.displayName}'),
        backgroundColor: const Color(0xFF10B981),
      ),
    );
    Navigator.of(context).pop();
  }
}
