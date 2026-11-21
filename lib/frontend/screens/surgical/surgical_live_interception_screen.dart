import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../engine/surgical/catalog/surgical_subfeature_types.dart';
import '../../../engine/surgical/models/surgical_interception_event.dart';
import '../../../engine/surgical/models/view_node_target.dart';
import '../../../engine/surgical/telemetry/surgical_telemetry_recorder.dart';

/// Real-time live streaming audit monitor displaying sub-feature interceptions.
class SurgicalLiveInterceptionScreen extends StatefulWidget {
  final SurgicalTelemetryRecorder recorder;

  const SurgicalLiveInterceptionScreen({
    super.key,
    required this.recorder,
  });

  @override
  State<SurgicalLiveInterceptionScreen> createState() =>
      _SurgicalLiveInterceptionScreenState();
}

class _SurgicalLiveInterceptionScreenState
    extends State<SurgicalLiveInterceptionScreen> {
  late StreamSubscription<SurgicalInterceptionEvent> _eventSub;
  final List<SurgicalInterceptionEvent> _events = [];

  bool _isStreamPaused = false;
  String _filterType = 'All';
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _events.addAll(widget.recorder.recentEvents);

    _eventSub = widget.recorder.eventStream.listen((event) {
      if (!_isStreamPaused && mounted) {
        setState(() {
          _events.insert(0, event);
          if (_events.length > 500) {
            _events.removeLast();
          }
        });
      }
    });
  }

  @override
  void dispose() {
    _eventSub.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final scaffoldBg = isDark ? const Color(0xFF13151B) : const Color(0xFFF8FAFC);

    final filteredEvents = _events.where((e) {
      if (_searchQuery.isNotEmpty) {
        final q = _searchQuery.toLowerCase();
        final matchesPlat = e.platformName.toLowerCase().contains(q);
        final matchesTarget = e.interceptedTarget.toLowerCase().contains(q);
        if (!matchesPlat && !matchesTarget) return false;
      }

      if (_filterType == 'Reels') {
        return e.subfeature == SurgicalSubfeature.reelsOrShorts;
      } else if (_filterType == 'Feed') {
        return e.subfeature == SurgicalSubfeature.feed;
      } else if (_filterType == 'Explore') {
        return e.subfeature == SurgicalSubfeature.explore;
      }
      return true;
    }).toList();

    return Scaffold(
      backgroundColor: scaffoldBg,
      appBar: AppBar(
        title: const Text('Live Interception Stream'),
        actions: [
          IconButton(
            tooltip: _isStreamPaused ? 'Resume Stream' : 'Pause Stream',
            icon: Icon(
              _isStreamPaused ? Icons.play_arrow_rounded : Icons.pause_rounded,
              color: _isStreamPaused ? Colors.amber : const Color(0xFF10B981),
            ),
            onPressed: () {
              setState(() {
                _isStreamPaused = !_isStreamPaused;
              });
            },
          ),
          IconButton(
            tooltip: 'Simulate Event',
            icon: const Icon(Icons.science_rounded),
            onPressed: _simulateInterception,
          ),
          IconButton(
            tooltip: 'Clear Stream',
            icon: const Icon(Icons.delete_outline_rounded),
            onPressed: () {
              setState(() {
                _events.clear();
              });
            },
          ),
        ],
      ),
      body: Column(
        children: [
          // Filter Chips & Search Bar Header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            color: isDark ? const Color(0xFF1A1D24) : Colors.white,
            child: Column(
              children: [
                TextField(
                  onChanged: (val) {
                    setState(() {
                      _searchQuery = val.trim();
                    });
                  },
                  decoration: InputDecoration(
                    hintText: 'Filter by platform or domain...',
                    prefixIcon: const Icon(Icons.search_rounded, size: 20),
                    filled: true,
                    fillColor: isDark ? const Color(0xFF13151B) : const Color(0xFFF1F5F9),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: ['All', 'Reels', 'Feed', 'Explore'].map((f) {
                    final isSel = _filterType == f;
                    return Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: FilterChip(
                        label: Text(f),
                        selected: isSel,
                        onSelected: (val) {
                          setState(() {
                            _filterType = f;
                          });
                        },
                      ),
                    );
                  }).toList(),
                ),
              ],
            ),
          ),

          // Events Stream List
          Expanded(
            child: filteredEvents.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.radar_rounded,
                          size: 48,
                          color: isDark ? Colors.white30 : Colors.black26,
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'No interceptions recorded yet',
                          style: TextStyle(
                            fontSize: 14,
                            color: isDark ? Colors.white54 : Colors.black45,
                          ),
                        ),
                      ],
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.all(16),
                    itemCount: filteredEvents.length,
                    separatorBuilder: (context, index) => const SizedBox(height: 8),
                    itemBuilder: (context, index) {
                      final evt = filteredEvents[index];
                      return _buildEventTile(evt, isDark);
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildEventTile(SurgicalInterceptionEvent evt, bool isDark) {
    final cardColor = isDark ? const Color(0xFF1E222B) : Colors.white;
    final meta = SurgicalSubfeatureRegistry.getMetadata(evt.subfeature);

    Color hazardColor;
    switch (evt.hazardLevel) {
      case DopamineHazardLevel.critical:
        hazardColor = const Color(0xFFEF4444);
        break;
      case DopamineHazardLevel.high:
        hazardColor = const Color(0xFFF59E0B);
        break;
      case DopamineHazardLevel.moderate:
        hazardColor = const Color(0xFF3B82F6);
        break;
      case DopamineHazardLevel.mild:
        hazardColor = const Color(0xFF10B981);
        break;
    }

    final timeStr =
        '${evt.timestamp.hour.toString().padLeft(2, '0')}:${evt.timestamp.minute.toString().padLeft(2, '0')}:${evt.timestamp.second.toString().padLeft(2, '0')}';

    return Material(
      color: cardColor,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: () => _showEventDetailDialog(evt),
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isDark ? const Color(0xFF2C3240) : const Color(0xFFE2E7F0),
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: hazardColor.withAlpha(25),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(meta.icon, color: hazardColor, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          evt.platformName,
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                        ),
                        Text(
                          timeStr,
                          style: TextStyle(
                            fontSize: 10,
                            color: isDark ? Colors.white38 : Colors.black38,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      evt.interceptedTarget,
                      style: TextStyle(
                        fontSize: 11,
                        color: isDark ? Colors.white70 : Colors.black87,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Averted ~${(evt.estimatedSecondsSaved / 60).toStringAsFixed(1)} min doomscroll',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w500,
                        color: const Color(0xFF10B981),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showEventDetailDialog(SurgicalInterceptionEvent evt) {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(evt.displaySummary),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Platform: ${evt.platformName} (${evt.packageName})'),
              const SizedBox(height: 4),
              Text('Sub-feature: ${evt.subfeature.name}'),
              const SizedBox(height: 4),
              Text('Target: ${evt.interceptedTarget}'),
              const SizedBox(height: 4),
              Text('Action Applied: ${evt.actionApplied.name}'),
              const SizedBox(height: 4),
              Text('Trigger: ${evt.triggerSource.name}'),
              const SizedBox(height: 4),
              Text('Hazard Severity: ${evt.hazardLevel.name.toUpperCase()}'),
              const SizedBox(height: 4),
              Text('Time Reclaimed: ~${evt.estimatedSecondsSaved} seconds'),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () {
                Clipboard.setData(ClipboardData(text: evt.toJson().toString()));
                Navigator.of(context).pop();
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Copied event JSON to clipboard')),
                );
              },
              child: const Text('Copy JSON'),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Close'),
            ),
          ],
        );
      },
    );
  }

  void _simulateInterception() {
    final now = DateTime.now();
    final event = SurgicalInterceptionEvent(
      eventId: 'sim_${now.millisecondsSinceEpoch}',
      timestamp: now,
      platformId: 'instagram',
      platformName: 'Instagram',
      subfeature: SurgicalSubfeature.reelsOrShorts,
      interceptedTarget: 'reels.instagram.com',
      actionApplied: ViewInterceptionAction.navigateBack,
      triggerSource: InterceptionTriggerSource.dnsQuery,
      packageName: 'com.instagram.android',
      estimatedSecondsSaved: 300,
      estimatedBytesBlocked: 3145728,
      hazardLevel: DopamineHazardLevel.critical,
      notes: 'Simulated real-time Reels interception',
    );
    widget.recorder.recordInterception(event);
  }
}
