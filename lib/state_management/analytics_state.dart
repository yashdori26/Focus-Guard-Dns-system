import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../backend/vpn_service.dart';
import '../models/enums.dart';

class BlockedDomainMetric {
  final String domain;
  final int count;
  final String percentage;

  const BlockedDomainMetric({
    required this.domain,
    required this.count,
    required this.percentage,
  });

  factory BlockedDomainMetric.fromMap(Map<String, dynamic> map) {
    return BlockedDomainMetric(
      domain: map['domain']?.toString() ?? '',
      count: (map['count'] as num?)?.toInt() ?? 0,
      percentage: map['percentage']?.toString() ?? '0%',
    );
  }
}

class AnalyticsState {
  final TimeFilter filter;
  final int totalQueries;
  final int blockedQueries;
  final String blockedPercentage;
  final double threatRatio;
  final List<BlockedDomainMetric> topBlockedDomains;
  final List<int> bucketTotals;
  final List<int> bucketBlockeds;
  final bool isLoading;

  const AnalyticsState({
    required this.filter,
    this.totalQueries = 0,
    this.blockedQueries = 0,
    this.blockedPercentage = '0.0%',
    this.threatRatio = 0.0,
    this.topBlockedDomains = const [],
    this.bucketTotals = const [],
    this.bucketBlockeds = const [],
    this.isLoading = false,
  });

  AnalyticsState copyWith({
    TimeFilter? filter,
    int? totalQueries,
    int? blockedQueries,
    String? blockedPercentage,
    double? threatRatio,
    List<BlockedDomainMetric>? topBlockedDomains,
    List<int>? bucketTotals,
    List<int>? bucketBlockeds,
    bool? isLoading,
  }) {
    return AnalyticsState(
      filter: filter ?? this.filter,
      totalQueries: totalQueries ?? this.totalQueries,
      blockedQueries: blockedQueries ?? this.blockedQueries,
      blockedPercentage: blockedPercentage ?? this.blockedPercentage,
      threatRatio: threatRatio ?? this.threatRatio,
      topBlockedDomains: topBlockedDomains ?? this.topBlockedDomains,
      bucketTotals: bucketTotals ?? this.bucketTotals,
      bucketBlockeds: bucketBlockeds ?? this.bucketBlockeds,
      isLoading: isLoading ?? this.isLoading,
    );
  }
}

final analyticsFilterProvider = StateProvider<TimeFilter>((ref) {
  return TimeFilter.days7;
});

class AnalyticsNotifier extends StateNotifier<AnalyticsState> {
  StreamSubscription? _liveSub;

  AnalyticsNotifier() : super(const AnalyticsState(filter: TimeFilter.days7)) {
    refresh();
    // Refresh stats when live queries arrive
    _liveSub = FocusDnsVpnManager.liveQueryStream.listen((_) {
      refresh();
    });
  }

  int _hoursForFilter(TimeFilter filter) {
    switch (filter) {
      case TimeFilter.hours24:
        return 24;
      case TimeFilter.days7:
        return 168;
      case TimeFilter.days30:
        return 720;
    }
  }

  Future<void> setFilter(TimeFilter newFilter) async {
    state = state.copyWith(filter: newFilter, isLoading: true);
    await refresh();
  }

  Future<void> refresh() async {
    try {
      final hours = _hoursForFilter(state.filter);
      final stats = await FocusDnsVpnManager.getDbStats(timeframeHours: hours);
      final rawTop = stats['topBlockedDomains'] as List<dynamic>? ?? [];
      final topDomains = rawTop
          .map((e) => BlockedDomainMetric.fromMap(Map<String, dynamic>.from(e as Map)))
          .toList();

      final rawTotals = stats['bucketTotals'] as List<dynamic>? ?? [];
      final rawBlocked = stats['bucketBlockeds'] as List<dynamic>? ?? [];

      state = state.copyWith(
        totalQueries: (stats['totalQueries'] as num?)?.toInt() ?? 0,
        blockedQueries: (stats['blockedQueries'] as num?)?.toInt() ?? 0,
        blockedPercentage: stats['blockedPercentage']?.toString() ?? '0.0%',
        threatRatio: (stats['threatRatio'] as num?)?.toDouble() ?? 0.0,
        topBlockedDomains: topDomains,
        bucketTotals: rawTotals.map((e) => (e as num).toInt()).toList(),
        bucketBlockeds: rawBlocked.map((e) => (e as num).toInt()).toList(),
        isLoading: false,
      );
    } catch (_) {
      state = state.copyWith(isLoading: false);
    }
  }

  @override
  void dispose() {
    _liveSub?.cancel();
    super.dispose();
  }
}

final analyticsStateProvider = StateNotifierProvider<AnalyticsNotifier, AnalyticsState>((ref) {
  final notifier = AnalyticsNotifier();
  ref.listen(analyticsFilterProvider, (_, nextFilter) {
    notifier.setFilter(nextFilter);
  });
  return notifier;
});
