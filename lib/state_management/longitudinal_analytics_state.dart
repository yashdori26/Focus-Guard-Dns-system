import 'package:flutter_riverpod/flutter_riverpod.dart';

enum AnalyticsTimeframe {
  day,
  week,
  month,
  year,
}

class FocusPeriodMetrics {
  final int totalFocusMinutes;
  final int totalBreakMinutes;
  final int completedSessions;
  final int totalSavedHours;
  final int blockedLaunchesAttempted;
  final int blockedDnsQueries;
  final double complianceRate; // e.g. 0.94 (94%)

  const FocusPeriodMetrics({
    required this.totalFocusMinutes,
    required this.totalBreakMinutes,
    required this.completedSessions,
    required this.totalSavedHours,
    required this.blockedLaunchesAttempted,
    required this.blockedDnsQueries,
    required this.complianceRate,
  });
}

class LongitudinalAnalyticsState {
  final AnalyticsTimeframe selectedTimeframe;
  final Map<AnalyticsTimeframe, FocusPeriodMetrics> timeframeData;

  const LongitudinalAnalyticsState({
    this.selectedTimeframe = AnalyticsTimeframe.week,
    this.timeframeData = const {},
  });

  FocusPeriodMetrics get currentMetrics =>
      timeframeData[selectedTimeframe] ??
      const FocusPeriodMetrics(
        totalFocusMinutes: 0,
        totalBreakMinutes: 0,
        completedSessions: 0,
        totalSavedHours: 0,
        blockedLaunchesAttempted: 0,
        blockedDnsQueries: 0,
        complianceRate: 1.0,
      );

  LongitudinalAnalyticsState copyWith({
    AnalyticsTimeframe? selectedTimeframe,
    Map<AnalyticsTimeframe, FocusPeriodMetrics>? timeframeData,
  }) {
    return LongitudinalAnalyticsState(
      selectedTimeframe: selectedTimeframe ?? this.selectedTimeframe,
      timeframeData: timeframeData ?? this.timeframeData,
    );
  }
}

class LongitudinalAnalyticsNotifier extends StateNotifier<LongitudinalAnalyticsState> {
  LongitudinalAnalyticsNotifier()
      : super(const LongitudinalAnalyticsState(
          selectedTimeframe: AnalyticsTimeframe.week,
          timeframeData: {
            AnalyticsTimeframe.day: FocusPeriodMetrics(
              totalFocusMinutes: 240,
              totalBreakMinutes: 30,
              completedSessions: 4,
              totalSavedHours: 3,
              blockedLaunchesAttempted: 19,
              blockedDnsQueries: 342,
              complianceRate: 0.96,
            ),
            AnalyticsTimeframe.week: FocusPeriodMetrics(
              totalFocusMinutes: 1480,
              totalBreakMinutes: 210,
              completedSessions: 26,
              totalSavedHours: 18,
              blockedLaunchesAttempted: 142,
              blockedDnsQueries: 2310,
              complianceRate: 0.92,
            ),
            AnalyticsTimeframe.month: FocusPeriodMetrics(
              totalFocusMinutes: 6120,
              totalBreakMinutes: 840,
              completedSessions: 104,
              totalSavedHours: 76,
              blockedLaunchesAttempted: 588,
              blockedDnsQueries: 9480,
              complianceRate: 0.94,
            ),
            AnalyticsTimeframe.year: FocusPeriodMetrics(
              totalFocusMinutes: 68400,
              totalBreakMinutes: 9800,
              completedSessions: 1140,
              totalSavedHours: 855,
              blockedLaunchesAttempted: 6420,
              blockedDnsQueries: 108400,
              complianceRate: 0.95,
            ),
          },
        ));

  void selectTimeframe(AnalyticsTimeframe timeframe) {
    state = state.copyWith(selectedTimeframe: timeframe);
  }
}

final longitudinalAnalyticsProvider =
    StateNotifierProvider<LongitudinalAnalyticsNotifier, LongitudinalAnalyticsState>((ref) {
  return LongitudinalAnalyticsNotifier();
});
