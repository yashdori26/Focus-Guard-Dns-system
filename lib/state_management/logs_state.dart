import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/app_models.dart';

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
  LogsNotifier()
      : super(const LogsState(
          searchQuery: '',
          logs: [
            QueryLog(
              id: '1',
              subdomain: 'w3-reporting.',
              domain: 'reddit.com',
              time: '5 mins ago',
              icon: 'r/',
            ),
            QueryLog(
              id: '2',
              subdomain: 'pi.',
              domain: 'reddit.com',
              time: '6 mins ago',
              icon: 'r/',
            ),
            QueryLog(
              id: '3',
              subdomain: 'gql-realtime.',
              domain: 'reddit.com',
              time: '10 mins ago',
              icon: 'r/',
            ),
            QueryLog(
              id: '4',
              subdomain: 'www.',
              domain: 'reddit.com',
              time: '12 mins ago',
              icon: 'r/',
            ),
            QueryLog(
              id: '5',
              subdomain: '...m7.cdn-settings.',
              domain: 'appsflyersdk.com',
              time: '15 mins ago',
              icon: 'A',
            ),
            QueryLog(
              id: '6',
              subdomain: 'telemetry.',
              domain: 'tiktokv.com',
              time: '20 mins ago',
              icon: 't',
            ),
            QueryLog(
              id: '7',
              subdomain: 'api.',
              domain: 'segment.io',
              time: '30 mins ago',
              icon: 'S',
            ),
          ],
        ));

  void setSearchQuery(String query) {
    state = state.copyWith(searchQuery: query);
  }
}

final logsProvider = StateNotifierProvider<LogsNotifier, LogsState>((ref) {
  return LogsNotifier();
});
