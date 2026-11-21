import 'package:flutter/foundation.dart';

/// The active enforcement mode governing an application.
enum AppLockMode {
  /// App is completely unlocked and accessible.
  unlocked,

  /// One-shot countdown timer (e.g., locked for 4 hours).
  independentTimer,

  /// Daily usage allowance (e.g., 30m maximum per day).
  dailyQuota,

  /// Recurring calendar schedule (e.g., locked Monday-Friday 9AM-5PM).
  recurringSchedule,

  /// Cooldown enforcer (e.g., after 15m continuous use, 45m forced lock).
  cooldownSession,

  /// Permanent block (e.g., Adult 18+ or Gambling always blocked).
  permanentBlock,
}

/// Strictness enforcement level for app locks.
enum StrictnessTier {
  /// Can be unlocked easily with a switch or password.
  flexible,

  /// Requires completing a friction challenge (math oath or cooldown delay).
  frictionProtected,

  /// Unbreakable lock: strictly zero bypass until timer or window concludes.
  strictUnbreakable,

  /// Hardcore mode: Device Admin protected, immune to reboots or package tampering.
  hardcoreDeviceAdmin,
}

/// Comprehensive lock configuration governing an individual managed application.
@immutable
class AppLockConfig {
  final String appId;
  final String packageName;
  final AppLockMode mode;
  final StrictnessTier strictness;
  final int allocatedTimerMinutes;
  final int dailyQuotaMinutes;
  final int usedQuotaSecondsToday;
  final int maxContinuousSessionMinutes;
  final int mandatoryCooldownMinutes;
  final DateTime? lockStartTime;
  final DateTime? lockTargetEndTime;
  final bool isCurrentlyLocked;
  final int totalInterventionsBlocked;
  final int totalMinutesSaved;

  const AppLockConfig({
    required this.appId,
    required this.packageName,
    this.mode = AppLockMode.unlocked,
    this.strictness = StrictnessTier.strictUnbreakable,
    this.allocatedTimerMinutes = 120,
    this.dailyQuotaMinutes = 30,
    this.usedQuotaSecondsToday = 0,
    this.maxContinuousSessionMinutes = 15,
    this.mandatoryCooldownMinutes = 45,
    this.lockStartTime,
    this.lockTargetEndTime,
    this.isCurrentlyLocked = false,
    this.totalInterventionsBlocked = 0,
    this.totalMinutesSaved = 0,
  });

  /// Computes remaining seconds for independent timer mode.
  int get remainingTimerSeconds {
    if (!isCurrentlyLocked || lockTargetEndTime == null) return 0;
    final diff = lockTargetEndTime!.difference(DateTime.now()).inSeconds;
    return diff > 0 ? diff : 0;
  }

  /// Computes remaining quota seconds today.
  int get remainingQuotaSecondsToday {
    final totalQuotaSec = dailyQuotaMinutes * 60;
    final remaining = totalQuotaSec - usedQuotaSecondsToday;
    return remaining > 0 ? remaining : 0;
  }

  /// Whether the daily quota has been completely exhausted.
  bool get isQuotaDepleted => usedQuotaSecondsToday >= (dailyQuotaMinutes * 60);

  /// Creates a copy with specified fields modified.
  AppLockConfig copyWith({
    String? appId,
    String? packageName,
    AppLockMode? mode,
    StrictnessTier? strictness,
    int? allocatedTimerMinutes,
    int? dailyQuotaMinutes,
    int? usedQuotaSecondsToday,
    int? maxContinuousSessionMinutes,
    int? mandatoryCooldownMinutes,
    DateTime? lockStartTime,
    DateTime? lockTargetEndTime,
    bool? isCurrentlyLocked,
    int? totalInterventionsBlocked,
    int? totalMinutesSaved,
  }) {
    return AppLockConfig(
      appId: appId ?? this.appId,
      packageName: packageName ?? this.packageName,
      mode: mode ?? this.mode,
      strictness: strictness ?? this.strictness,
      allocatedTimerMinutes: (allocatedTimerMinutes ?? this.allocatedTimerMinutes).clamp(5, 1440),
      dailyQuotaMinutes: (dailyQuotaMinutes ?? this.dailyQuotaMinutes).clamp(1, 480),
      usedQuotaSecondsToday: (usedQuotaSecondsToday ?? this.usedQuotaSecondsToday).clamp(0, 86400),
      maxContinuousSessionMinutes: (maxContinuousSessionMinutes ?? this.maxContinuousSessionMinutes).clamp(5, 120),
      mandatoryCooldownMinutes: (mandatoryCooldownMinutes ?? this.mandatoryCooldownMinutes).clamp(5, 240),
      lockStartTime: lockStartTime ?? this.lockStartTime,
      lockTargetEndTime: lockTargetEndTime ?? this.lockTargetEndTime,
      isCurrentlyLocked: isCurrentlyLocked ?? this.isCurrentlyLocked,
      totalInterventionsBlocked: totalInterventionsBlocked ?? this.totalInterventionsBlocked,
      totalMinutesSaved: totalMinutesSaved ?? this.totalMinutesSaved,
    );
  }

  Map<String, dynamic> toJson() => {
    'appId': appId,
    'packageName': packageName,
    'mode': mode.name,
    'strictness': strictness.name,
    'allocatedTimerMinutes': allocatedTimerMinutes,
    'dailyQuotaMinutes': dailyQuotaMinutes,
    'usedQuotaSecondsToday': usedQuotaSecondsToday,
    'maxContinuousSessionMinutes': maxContinuousSessionMinutes,
    'mandatoryCooldownMinutes': mandatoryCooldownMinutes,
    'lockStartTime': lockStartTime?.toIso8601String(),
    'lockTargetEndTime': lockTargetEndTime?.toIso8601String(),
    'isCurrentlyLocked': isCurrentlyLocked,
    'totalInterventionsBlocked': totalInterventionsBlocked,
    'totalMinutesSaved': totalMinutesSaved,
  };

  factory AppLockConfig.fromJson(Map<String, dynamic> json) {
    return AppLockConfig(
      appId: json['appId'] as String,
      packageName: json['packageName'] as String,
      mode: AppLockMode.values.byName(json['mode'] as String? ?? 'unlocked'),
      strictness: StrictnessTier.values.byName(json['strictness'] as String? ?? 'strictUnbreakable'),
      allocatedTimerMinutes: (json['allocatedTimerMinutes'] as num?)?.toInt() ?? 120,
      dailyQuotaMinutes: (json['dailyQuotaMinutes'] as num?)?.toInt() ?? 30,
      usedQuotaSecondsToday: (json['usedQuotaSecondsToday'] as num?)?.toInt() ?? 0,
      maxContinuousSessionMinutes: (json['maxContinuousSessionMinutes'] as num?)?.toInt() ?? 15,
      mandatoryCooldownMinutes: (json['mandatoryCooldownMinutes'] as num?)?.toInt() ?? 45,
      lockStartTime: json['lockStartTime'] != null ? DateTime.parse(json['lockStartTime'] as String) : null,
      lockTargetEndTime: json['lockTargetEndTime'] != null ? DateTime.parse(json['lockTargetEndTime'] as String) : null,
      isCurrentlyLocked: json['isCurrentlyLocked'] as bool? ?? false,
      totalInterventionsBlocked: (json['totalInterventionsBlocked'] as num?)?.toInt() ?? 0,
      totalMinutesSaved: (json['totalMinutesSaved'] as num?)?.toInt() ?? 0,
    );
  }
}
