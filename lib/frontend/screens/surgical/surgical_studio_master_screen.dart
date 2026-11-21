import 'dart:async';
import 'package:flutter/material.dart';
import '../../../engine/surgical/catalog/surgical_platform_catalog.dart';
import '../../../engine/surgical/catalog/surgical_subfeature_types.dart';
import '../../../engine/surgical/core/surgical_policy_evaluator.dart';
import '../../../engine/surgical/models/surgical_rule_model.dart';
import '../../../engine/surgical/models/surgical_telemetry_snapshot.dart';
import '../../../engine/surgical/telemetry/surgical_telemetry_recorder.dart';
import '../../widgets/surgical/platform_surgical_card.dart';
import '../../widgets/surgical/surgical_dissection_diagram.dart';
import 'custom_surgical_rule_builder_screen.dart';
import 'mindful_interstitial_customizer_screen.dart';
import 'platform_surgical_detail_screen.dart';
import 'surgical_live_interception_screen.dart';

/// Master Control Studio for Surgical Feed vs Chat Content Dissection & In-App Dopamine Decoupling.
class SurgicalStudioMasterScreen extends StatefulWidget {
  final SurgicalPolicyEvaluator? evaluator;
  final SurgicalTelemetryRecorder? telemetryRecorder;

  const SurgicalStudioMasterScreen({
    super.key,
    this.evaluator,
    this.telemetryRecorder,
  });

  @override
  State<SurgicalStudioMasterScreen> createState() => _SurgicalStudioMasterScreenState();
}

class _SurgicalStudioMasterScreenState extends State<SurgicalStudioMasterScreen> {
  late SurgicalPolicyEvaluator _evaluator;
  late SurgicalTelemetryRecorder _telemetry;
  late StreamSubscription<SurgicalTelemetrySnapshot> _snapshotSub;

  SurgicalTelemetrySnapshot _snapshot = SurgicalTelemetrySnapshot.empty();
  String _searchQuery = '';
  String _selectedCategory = 'All';

  final List<String> _categories = ['All', 'Social', 'Video', 'Professional', 'Custom'];

  @override
  void initState() {
    super.initState();
    _evaluator = widget.evaluator ?? SurgicalPolicyEvaluator();
    _telemetry = widget.telemetryRecorder ?? SurgicalTelemetryRecorder();

    // Populate some initial synthetic demo data if buffer is empty
    if (_telemetry.bufferedEventCount == 0) {
      _telemetry.populateSyntheticTestData(count: 18);
    }

    _snapshot = _telemetry.computeCurrentSnapshot();
    _snapshotSub = _telemetry.snapshotStream.listen((snap) {
      if (mounted) {
        setState(() {
          _snapshot = snap;
        });
      }
    });
  }

  @override
  void dispose() {
    _snapshotSub.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final scaffoldBg = isDark ? const Color(0xFF13151B) : const Color(0xFFF8FAFC);

    final allRules = _evaluator.compiledRules.values.toList();
    final filteredRules = allRules.where((rule) {
      if (_searchQuery.isNotEmpty) {
        final q = _searchQuery.toLowerCase();
        final matchesName = rule.displayName.toLowerCase().contains(q);
        final matchesPkg = rule.packageNames.any((p) => p.toLowerCase().contains(q));
        if (!matchesName && !matchesPkg) return false;
      }

      if (_selectedCategory == 'Social') {
        return ['instagram', 'reddit', 'tiktok', 'twitter', 'snapchat', 'facebook', 'threads'].contains(rule.platformId);
      } else if (_selectedCategory == 'Video') {
        return ['youtube', 'twitch', 'tiktok'].contains(rule.platformId);
      } else if (_selectedCategory == 'Professional') {
        return ['linkedin', 'discord'].contains(rule.platformId);
      } else if (_selectedCategory == 'Custom') {
        return !SurgicalPlatformCatalog.allPlatforms.any((p) => p.platformId == rule.platformId);
      }
      return true;
    }).toList();

    return Scaffold(
      backgroundColor: scaffoldBg,
      appBar: AppBar(
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Surgical Decoupling Studio',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17),
            ),
            Text(
              'Feed vs Chat Selective Content Dissection',
              style: TextStyle(fontSize: 11, color: Colors.grey),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Live Interception Stream',
            icon: const Icon(Icons.stream_rounded, color: Color(0xFF10B981)),
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (context) => SurgicalLiveInterceptionScreen(
                    recorder: _telemetry,
                  ),
                ),
              );
            },
          ),
          IconButton(
            tooltip: 'Mindful Interstitial Nudge Settings',
            icon: const Icon(Icons.psychology_rounded, color: Color(0xFF8B5CF6)),
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (context) => const MindfulInterstitialCustomizerScreen(),
                ),
              );
            },
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Hero Dissection Visualization Diagram
            SurgicalDissectionDiagram(
              blockedReelsCount: _snapshot.blockedReelsCount,
              allowedChatsCount: _snapshot.allowedChatCount,
              height: 180,
            ),
            const SizedBox(height: 16),

            // Telemetry Metric Stats Row
            _buildStatsCardsRow(isDark),
            const SizedBox(height: 16),

            // Master Engine Switch Banner
            _buildMasterSwitchBanner(isDark),
            const SizedBox(height: 16),

            // Category Filter Chips & Search Bar
            _buildSearchAndFilters(isDark),
            const SizedBox(height: 16),

            // Platforms List Header
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'MONITORED PLATFORMS (${filteredRules.length})',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.0,
                    color: Colors.grey,
                  ),
                ),
                Text(
                  'Tap platform to customize',
                  style: TextStyle(
                    fontSize: 11,
                    color: isDark ? Colors.white54 : Colors.black45,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),

            // Platform Cards List
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: filteredRules.length,
              separatorBuilder: (context, index) => const SizedBox(height: 10),
              itemBuilder: (context, index) {
                final rule = filteredRules[index];
                final count = _snapshot.platformInterceptionCounts[rule.platformId] ?? 0;

                return PlatformSurgicalCard(
                  rule: rule,
                  blockedCount: count,
                  onTap: () async {
                    await Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (context) => PlatformSurgicalDetailScreen(
                          platformId: rule.platformId,
                          evaluator: _evaluator,
                          recorder: _telemetry,
                        ),
                      ),
                    );
                    setState(() {});
                  },
                );
              },
            ),
            const SizedBox(height: 80),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          await Navigator.of(context).push(
            MaterialPageRoute(
              builder: (context) => CustomSurgicalRuleBuilderScreen(
                evaluator: _evaluator,
              ),
            ),
          );
          setState(() {});
        },
        backgroundColor: const Color(0xFF6366F1),
        icon: const Icon(Icons.add_rounded, color: Colors.white),
        label: const Text(
          'Add Custom Platform Rule',
          style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
        ),
      ),
    );
  }

  Widget _buildStatsCardsRow(bool isDark) {
    return Row(
      children: [
        Expanded(
          child: _buildMetricCard(
            title: 'Reels Blocked',
            value: '${_snapshot.blockedReelsCount}',
            subtitle: 'Autoplays severed',
            color: const Color(0xFFEF4444),
            icon: Icons.play_disabled_rounded,
            isDark: isDark,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _buildMetricCard(
            title: 'DMs Flowing',
            value: '${_snapshot.allowedChatCount}',
            subtitle: 'Chats protected',
            color: const Color(0xFF10B981),
            icon: Icons.mark_chat_read_rounded,
            isDark: isDark,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _buildMetricCard(
            title: 'Time Reclaimed',
            value: '${_snapshot.estimatedHoursReclaimed}h',
            subtitle: 'Focus preserved',
            color: const Color(0xFF6366F1),
            icon: Icons.hourglass_top_rounded,
            isDark: isDark,
          ),
        ),
      ],
    );
  }

  Widget _buildMetricCard({
    required String title,
    required String value,
    required String subtitle,
    required Color color,
    required IconData icon,
    required bool isDark,
  }) {
    final cardColor = isDark ? const Color(0xFF1E222B) : Colors.white;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(16),
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
              Icon(icon, size: 16, color: color),
              Container(
                width: 6,
                height: 6,
                decoration: BoxDecoration(color: color, shape: BoxShape.circle),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            title,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: isDark ? Colors.white70 : Colors.black87,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.bold,
              color: isDark ? Colors.white : Colors.black87,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            subtitle,
            style: TextStyle(
              fontSize: 10,
              color: isDark ? Colors.white54 : Colors.black54,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  Widget _buildMasterSwitchBanner(bool isDark) {
    final cardColor = isDark ? const Color(0xFF1E222B) : Colors.white;
    final active = _evaluator.isGlobalActive;

    return Material(
      color: cardColor,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: active
                ? const Color(0xFF10B981).withAlpha(100)
                : const Color(0xFFEF4444).withAlpha(100),
            width: 1.5,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: (active ? const Color(0xFF10B981) : const Color(0xFFEF4444)).withAlpha(25),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                active ? Icons.shield_rounded : Icons.shield_outlined,
                color: active ? const Color(0xFF10B981) : const Color(0xFFEF4444),
                size: 20,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    active ? 'Surgical Engine Active' : 'Surgical Engine Paused',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                      color: isDark ? Colors.white : Colors.black87,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    active
                        ? 'Decoupling feeds & reels while maintaining chat gateways.'
                        : 'Traffic is passing unfiltered across all platforms.',
                    style: TextStyle(
                      fontSize: 11,
                      color: isDark ? Colors.white60 : Colors.black54,
                    ),
                  ),
                ],
              ),
            ),
            Switch(
              value: active,
              activeColor: const Color(0xFF10B981),
              onChanged: (val) {
                setState(() {
                  _evaluator.isGlobalActive = val;
                });
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSearchAndFilters(bool isDark) {
    return Column(
      children: [
        // Search TextField
        TextField(
          onChanged: (val) {
            setState(() {
              _searchQuery = val.trim();
            });
          },
          decoration: InputDecoration(
            hintText: 'Search platform, package, or domain...',
            hintStyle: TextStyle(
              fontSize: 13,
              color: isDark ? Colors.white38 : Colors.black38,
            ),
            prefixIcon: const Icon(Icons.search_rounded, size: 20),
            filled: true,
            fillColor: isDark ? const Color(0xFF1E222B) : Colors.white,
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide(
                color: isDark ? const Color(0xFF2C3240) : const Color(0xFFE2E7F0),
              ),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide(
                color: isDark ? const Color(0xFF2C3240) : const Color(0xFFE2E7F0),
              ),
            ),
          ),
        ),
        const SizedBox(height: 10),

        // Filter Chips Row
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: _categories.map((cat) {
              final isSelected = _selectedCategory == cat;
              return Padding(
                padding: const EdgeInsets.only(right: 8),
                child: FilterChip(
                  label: Text(cat),
                  selected: isSelected,
                  selectedColor: const Color(0xFF6366F1).withAlpha(40),
                  checkmarkColor: const Color(0xFF6366F1),
                  labelStyle: TextStyle(
                    fontSize: 12,
                    fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                    color: isSelected
                        ? const Color(0xFF6366F1)
                        : (isDark ? Colors.white70 : Colors.black87),
                  ),
                  onSelected: (val) {
                    setState(() {
                      _selectedCategory = cat;
                    });
                  },
                ),
              );
            }).toList(),
          ),
        ),
      ],
    );
  }
}
