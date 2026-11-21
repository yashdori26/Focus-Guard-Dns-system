import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../backend/vpn_service.dart';
import '../models/app_models.dart';
import 'live_telemetry_provider.dart';

class LogsState {
  final String searchQuery;
  final List<QueryLog> logs;

  const LogsState({
    required this.searchQuery,
    required this.logs,
  });

  List<QueryLog> get filteredLogs {
    if (searchQuery.isEmpty) return logs;
    final q = searchQuery.toLowerCase();
    return logs
        .where((l) =>
            l.domain.toLowerCase().contains(q) ||
            l.subdomain.toLowerCase().contains(q))
        .toList();
  }

  LogsState copyWith({String? searchQuery, List<QueryLog>? logs}) {
    return LogsState(
      searchQuery: searchQuery ?? this.searchQuery,
      logs: logs ?? this.logs,
    );
  }
}

class LogsNotifier extends StateNotifier<LogsState> {

  StreamSubscription<Map<String, dynamic>>? _sub;

  LogsNotifier() : super(const LogsState(searchQuery: '', logs: [])) {
    _initLiveLogs();
  }

  Future<void> _initLiveLogs() async {
    // 1. Load initial telemetry logs from local VPN engine
    try {
      final telemetry = await FocusDnsVpnManager.getLiveTelemetry();
      final rawList = telemetry['recentQueries'] as List<dynamic>? ?? [];
      final initialLogs = rawList.map((e) {
        final item = LiveDnsQueryItem.fromMap(Map<String, dynamic>.from(e as Map));
        return QueryLog(
          id: item.id,
          subdomain: item.subdomain,
          domain: item.rootDomain,
          time: item.timeAgo,
          icon: item.iconText,
          isBlocked: item.isBlocked,
        );
      }).toList();
      if (mounted) {
        state = state.copyWith(logs: initialLogs);
      }
    } catch (_) {}

    // 2. Subscribe to incoming live query stream
    _sub = FocusDnsVpnManager.liveQueryStream.listen((data) {
      final item = LiveDnsQueryItem.fromMap(data);
      final log = QueryLog(
        id: item.id,
        subdomain: item.subdomain,
        domain: item.rootDomain,
        time: item.timeAgo,
        icon: item.iconText,
        isBlocked: item.isBlocked,
      );
      if (mounted) {
        state = state.copyWith(logs: [log, ...state.logs.take(99)]);
      }
    });
  }

  void setSearchQuery(String query) {
    state = state.copyWith(searchQuery: query);
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }
}

final logsProvider = StateNotifierProvider<LogsNotifier, LogsState>((ref) {
  return LogsNotifier();
});

