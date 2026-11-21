import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../catalog/surgical_subfeature_types.dart';
import '../models/surgical_interception_event.dart';
import '../models/surgical_telemetry_snapshot.dart';
import '../models/view_node_target.dart';

/// Central recorder and time-series rolling aggregator for surgical decoupling telemetry.
class SurgicalTelemetryRecorder {
  static const String prefKeyEvents = 'surgical_telemetry_recent_events_v1';
  static const String prefKeyStats = 'surgical_telemetry_aggregated_stats_v1';

  final int maxEventCapacity;
  final Queue<SurgicalInterceptionEvent> _eventRingBuffer = Queue<SurgicalInterceptionEvent>();

  final StreamController<SurgicalInterceptionEvent> _eventStreamController =
      StreamController<SurgicalInterceptionEvent>.broadcast();

  final StreamController<SurgicalTelemetrySnapshot> _snapshotStreamController =
      StreamController<SurgicalTelemetrySnapshot>.broadcast();

  int _allowedChatCounter = 0;
  int _allowedSearchCounter = 0;
  int _activePlatformsCount = 12;

  final Map<int, int> _hourlyRollup = {}; // hour of day (0..23) -> count
  final Map<String, int> _dailyRollup = {}; // YYYY-MM-DD -> count

  SurgicalTelemetryRecorder({this.maxEventCapacity = 1000});

  /// Broadcast stream of individual incoming interception events.
  Stream<SurgicalInterceptionEvent> get eventStream => _eventStreamController.stream;

  /// Broadcast stream of periodic or triggered snapshot updates.
  Stream<SurgicalTelemetrySnapshot> get snapshotStream => _snapshotStreamController.stream;

  /// Read-only view of buffered interception events (newest first).
  List<SurgicalInterceptionEvent> get recentEvents => _eventRingBuffer.toList().reversed.toList();

  /// Total count of events currently buffered in memory.
  int get bufferedEventCount => _eventRingBuffer.length;

  /// Total count of permitted direct messages / chat packets.
  int get allowedChatCount => _allowedChatCounter;

  /// Total count of permitted intentional search queries.
  int get allowedSearchCount => _allowedSearchCounter;

  /// Records a new sub-feature interception event into the ring buffer and rollups.
  void recordInterception(SurgicalInterceptionEvent event) {
    if (_eventRingBuffer.length >= maxEventCapacity) {
      _eventRingBuffer.removeFirst();
    }
    _eventRingBuffer.addLast(event);

    // Update hourly rollup
    final hour = event.timestamp.hour;
    _hourlyRollup[hour] = (_hourlyRollup[hour] ?? 0) + 1;

    // Update daily rollup
    final dayKey = _dateToDayKey(event.timestamp);
    _dailyRollup[dayKey] = (_dailyRollup[dayKey] ?? 0) + 1;

    // Emit live event
    _eventStreamController.add(event);

    // Emit updated snapshot
    final currentSnapshot = computeCurrentSnapshot();
    _snapshotStreamController.add(currentSnapshot);
  }

  /// Records an allowed intentional communication (chat DM or intentional search query).
  void recordAllowedCommunication({
    required String platformId,
    required bool isChat,
    int count = 1,
  }) {
    if (isChat) {
      _allowedChatCounter += count;
    } else {
      _allowedSearchCounter += count;
    }

    final currentSnapshot = computeCurrentSnapshot();
    _snapshotStreamController.add(currentSnapshot);
  }

  /// Sets the number of actively monitored platforms.
  void setActivePlatformsCount(int count) {
    _activePlatformsCount = count;
  }

  /// Calculates a full real-time snapshot from the current buffer state.
  SurgicalTelemetrySnapshot computeCurrentSnapshot() {
    return SurgicalTelemetrySnapshot.fromEvents(
      events: _eventRingBuffer.toList(),
      allowedChats: _allowedChatCounter,
      allowedSearches: _allowedSearchCounter,
      activePlatforms: _activePlatformsCount,
    );
  }

  /// Filters events by platform, subfeature, or date range.
  List<SurgicalInterceptionEvent> queryEvents({
    String? platformId,
    SurgicalSubfeature? subfeature,
    DateTime? after,
    DateTime? before,
    DopamineHazardLevel? minHazard,
    int limit = 100,
  }) {
    var filtered = _eventRingBuffer.toList().reversed.where((e) {
      if (platformId != null && e.platformId.toLowerCase() != platformId.toLowerCase()) {
        return false;
      }
      if (subfeature != null && e.subfeature != subfeature) {
        return false;
      }
      if (after != null && e.timestamp.isBefore(after)) {
        return false;
      }
      if (before != null && e.timestamp.isAfter(before)) {
        return false;
      }
      if (minHazard != null && e.hazardLevel.index < minHazard.index) {
        return false;
      }
      return true;
    });

    return filtered.take(limit).toList();
  }

  /// Generates a synthetic demo stream of interception events for testing and UI preview.
  void populateSyntheticTestData({int count = 25}) {
    final now = DateTime.now();
    final samplePlatforms = [
      ('instagram', 'Instagram', 'com.instagram.android'),
      ('youtube', 'YouTube', 'com.google.android.youtube'),
      ('reddit', 'Reddit', 'com.reddit.frontpage'),
      ('tiktok', 'TikTok', 'com.zhiliaoapp.musically'),
      ('twitter', 'X / Twitter', 'com.twitter.android'),
      ('linkedin', 'LinkedIn', 'com.linkedin.android'),
    ];

    final sampleSubfeatures = [
      (SurgicalSubfeature.reelsOrShorts, 'reels.instagram.com', ViewInterceptionAction.navigateBack),
      (SurgicalSubfeature.feed, 'graph.instagram.com/feed', ViewInterceptionAction.navigateToHome),
      (SurgicalSubfeature.explore, 'i.instagram.com/api/v1/discover', ViewInterceptionAction.showMindfulNudge),
      (SurgicalSubfeature.reelsOrShorts, 'video.twimg.com/shorts', ViewInterceptionAction.navigateBack),
      (SurgicalSubfeature.stories, 'stories.instagram.com', ViewInterceptionAction.navigateBack),
    ];

    for (int i = 0; i < count; i++) {
      final plat = samplePlatforms[i % samplePlatforms.length];
      final sub = sampleSubfeatures[i % sampleSubfeatures.length];
      final eventTime = now.subtract(Duration(minutes: (count - i) * 12));

      recordInterception(
        SurgicalInterceptionEvent(
          eventId: 'synth_${i}_${eventTime.millisecondsSinceEpoch}',
          timestamp: eventTime,
          platformId: plat.$1,
          platformName: plat.$2,
          subfeature: sub.$1,
          interceptedTarget: sub.$2,
          actionApplied: sub.$3,
          triggerSource: InterceptionTriggerSource.dnsQuery,
          packageName: plat.$3,
          estimatedSecondsSaved: SurgicalInterceptionEvent.defaultSecondsSaved(sub.$1),
          estimatedBytesBlocked: 3145728, // 3 MB
          hazardLevel: SurgicalInterceptionEvent.calculateHazardLevel(sub.$1),
          notes: 'Synthetic sample interception event #$i',
        ),
      );
    }

    _allowedChatCounter = count * 2;
    _allowedSearchCounter = count;
  }

  /// Persists recent events and statistics to SharedPreferences.
  Future<void> saveToPreferences() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final serializedEvents = _eventRingBuffer
          .take(100) // save up to 100 most recent events
          .map((e) => jsonEncode(e.toJson()))
          .toList();

      await prefs.setStringList(prefKeyEvents, serializedEvents);

      final statsMap = {
        'allowedChatCounter': _allowedChatCounter,
        'allowedSearchCounter': _allowedSearchCounter,
        'activePlatformsCount': _activePlatformsCount,
      };
      await prefs.setString(prefKeyStats, jsonEncode(statsMap));
    } catch (e) {
      debugPrint('SurgicalTelemetryRecorder: Failed to persist to SharedPreferences: $e');
    }
  }

  /// Restores persisted events and statistics from SharedPreferences.
  Future<void> loadFromPreferences() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final eventStrings = prefs.getStringList(prefKeyEvents) ?? [];

      _eventRingBuffer.clear();
      for (final str in eventStrings) {
        try {
          final json = jsonDecode(str) as Map<String, dynamic>;
          final event = SurgicalInterceptionEvent.fromJson(json);
          _eventRingBuffer.addLast(event);
        } catch (_) {}
      }

      final statsStr = prefs.getString(prefKeyStats);
      if (statsStr != null) {
        final statsJson = jsonDecode(statsStr) as Map<String, dynamic>;
        _allowedChatCounter = statsJson['allowedChatCounter'] as int? ?? 0;
        _allowedSearchCounter = statsJson['allowedSearchCounter'] as int? ?? 0;
        _activePlatformsCount = statsJson['activePlatformsCount'] as int? ?? 12;
      }

      _snapshotStreamController.add(computeCurrentSnapshot());
    } catch (e) {
      debugPrint('SurgicalTelemetryRecorder: Failed to restore from SharedPreferences: $e');
    }
  }

  /// Clears all buffered events and resets counters.
  void clearAll() {
    _eventRingBuffer.clear();
    _hourlyRollup.clear();
    _dailyRollup.clear();
    _allowedChatCounter = 0;
    _allowedSearchCounter = 0;
    _snapshotStreamController.add(computeCurrentSnapshot());
  }

  /// Closes stream controllers and releases resources.
  void dispose() {
    _eventStreamController.close();
    _snapshotStreamController.close();
  }

  String _dateToDayKey(DateTime dt) {
    final y = dt.year.toString().padLeft(4, '0');
    final m = dt.month.toString().padLeft(2, '0');
    final d = dt.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }
}
