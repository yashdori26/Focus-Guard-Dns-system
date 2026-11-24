import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../backend/vpn_service.dart';

class LiveDnsQueryItem {
  final String id;
  final String domain;
  final String subdomain;
  final String rootDomain;
  final String status; // "BLOCKED" or "ALLOWED"
  final String reason;
  final int latencyMs;
  final DateTime timestamp;

  const LiveDnsQueryItem({
    required this.id,
    required this.domain,
    required this.subdomain,
    required this.rootDomain,
    required this.status,
    required this.reason,
    required this.latencyMs,
    required this.timestamp,
  });

  bool get isBlocked => status == 'BLOCKED';

  String get iconText {
    final d = domain.toLowerCase();
    if (d.contains('youtube') || d.contains('googlevideo') || d.contains('ytimg')) return 'YT';
    if (d.contains('instagram') || d.contains('cdninstagram')) return 'IG';
    if (d.contains('tiktok') || d.contains('byteoversea')) return 'TT';
    if (d.contains('reddit')) return 'RD';
    if (d.contains('netflix') || d.contains('nflx')) return 'NF';
    if (d.contains('facebook') || d.contains('fbcdn')) return 'FB';
    if (d.contains('discord')) return 'DC';
    if (d.contains('steam')) return 'ST';
    if (d.contains('google') || d.contains('gstatic')) return 'G';
    if (d.contains('apple')) return 'AP';
    return 'DNS';
  }

  String get timeAgo {
    final diff = DateTime.now().difference(timestamp);
    if (diff.inSeconds < 5) return 'Just now';
    if (diff.inSeconds < 60) return '${diff.inSeconds}s ago';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    return '${diff.inHours}h ago';
  }

  factory LiveDnsQueryItem.fromMap(Map<String, dynamic> map) {
    final domain = (map['domain'] ?? '').toString();
    final parts = domain.split('.');
    String sub = '';
    String root = domain;
    if (parts.length > 2) {
      sub = '${parts.first}.';
      root = parts.sublist(1).join('.');
    }

    final tsMs = map['timestampMs'] as int? ?? DateTime.now().millisecondsSinceEpoch;

    return LiveDnsQueryItem(
      id: (map['id'] ?? '').toString(),
      domain: domain,
      subdomain: sub,
      rootDomain: root,
      status: (map['status'] ?? 'ALLOWED').toString(),
      reason: (map['reason'] ?? '').toString(),
      latencyMs: map['latencyMs'] as int? ?? 0,
      timestamp: DateTime.fromMillisecondsSinceEpoch(tsMs),
    );
  }
}

class LiveTelemetryState {
  final int totalQueries;
  final int blockedQueries;
  final int trackersBlocked;
  final String blockedPercentage;
  final double threatRatio;
  final int averageLatencyMs;
  final List<LiveDnsQueryItem> recentQueries;
  final bool isLoading;

  const LiveTelemetryState({
    this.totalQueries = 0,
    this.blockedQueries = 0,
    this.trackersBlocked = 0,
    this.blockedPercentage = '0.0%',
    this.threatRatio = 0.0,
    this.averageLatencyMs = 0,
    this.recentQueries = const [],
    this.isLoading = false,
  });

  LiveTelemetryState copyWith({
    int? totalQueries,
    int? blockedQueries,
    int? trackersBlocked,
    String? blockedPercentage,
    double? threatRatio,
    int? averageLatencyMs,
    List<LiveDnsQueryItem>? recentQueries,
    bool? isLoading,
  }) {
    return LiveTelemetryState(
      totalQueries: totalQueries ?? this.totalQueries,
      blockedQueries: blockedQueries ?? this.blockedQueries,
      trackersBlocked: trackersBlocked ?? this.trackersBlocked,
      blockedPercentage: blockedPercentage ?? this.blockedPercentage,
      threatRatio: threatRatio ?? this.threatRatio,
      averageLatencyMs: averageLatencyMs ?? this.averageLatencyMs,
      recentQueries: recentQueries ?? this.recentQueries,
      isLoading: isLoading ?? this.isLoading,
    );
  }
}

class LiveTelemetryNotifier extends StateNotifier<LiveTelemetryState> {
  Timer? _pollTimer;
  StreamSubscription<Map<String, dynamic>>? _querySubscription;

  LiveTelemetryNotifier({bool enablePolling = true}) : super(const LiveTelemetryState()) {
    if (enablePolling) {
      refresh();
      // Poll telemetry every 2 seconds for live accuracy
      _pollTimer = Timer.periodic(const Duration(seconds: 2), (_) => refresh());
      // Listen to push events for instantaneous UI reaction
      _querySubscription = FocusDnsVpnManager.liveQueryStream.listen((data) {
        final item = LiveDnsQueryItem.fromMap(data);
        final newTotal = state.totalQueries + 1;
        final newBlocked = item.isBlocked ? state.blockedQueries + 1 : state.blockedQueries;
        final newRatio = newTotal > 0 ? (newBlocked / newTotal) * 100.0 : 0.0;
        final updatedRecent = [item, ...state.recentQueries.take(49)];

        state = state.copyWith(
          totalQueries: newTotal,
          blockedQueries: newBlocked,
          threatRatio: newRatio,
          blockedPercentage: '${newRatio.toStringAsFixed(1)}%',
          recentQueries: updatedRecent,
        );
      });
    }
  }

  Future<void> refresh() async {
    final telemetry = await FocusDnsVpnManager.getLiveTelemetry();
    if (!mounted) return;

    final total = telemetry['totalQueries'] as int? ?? 0;
    final blocked = telemetry['blockedQueries'] as int? ?? 0;
    final trackers = telemetry['trackersBlocked'] as int? ?? (blocked > 0 ? (blocked * 0.7).round() : 0);
    final ratio = (telemetry['threatRatio'] as num?)?.toDouble() ?? 0.0;
    final avgLat = telemetry['averageLatencyMs'] as int? ?? 0;
    final pct = (telemetry['blockedPercentage'] ?? '0.0%').toString();

    final rawList = telemetry['recentQueries'] as List<dynamic>? ?? [];
    final recent = rawList
        .map((e) => LiveDnsQueryItem.fromMap(Map<String, dynamic>.from(e as Map)))
        .toList();

    state = state.copyWith(
      totalQueries: total,
      blockedQueries: blocked,
      trackersBlocked: trackers,
      threatRatio: ratio,
      averageLatencyMs: avgLat,
      blockedPercentage: pct,
      recentQueries: recent,
    );
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _querySubscription?.cancel();
    super.dispose();
  }
}

final liveTelemetryProvider =
    StateNotifierProvider<LiveTelemetryNotifier, LiveTelemetryState>((ref) {
  return LiveTelemetryNotifier();
});
