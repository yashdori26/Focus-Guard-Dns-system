import 'package:flutter/foundation.dart';
import '../models/app_lock_config.dart';

/// Callback invoked when an app exhausts its daily time quota.
typedef OnQuotaDepletedCallback = void Function(String appId, String packageName);

/// Callback invoked when daily quotas roll over at midnight.
typedef OnMidnightRolloverCallback = void Function(String oldDateKey, String newDateKey);

/// Engine tracking daily screen-time allowances, quota exhaustion, and midnight rollover.
class PerAppQuotaEngine {
  final Map<String, AppLockConfig> _configs = {};
  String _currentDateKey;
  OnQuotaDepletedCallback? onQuotaDepleted;
  OnMidnightRolloverCallback? onMidnightRollover;

  PerAppQuotaEngine({
    DateTime? initialDate,
    this.onQuotaDepleted,
    this.onMidnightRollover,
  }) : _currentDateKey = _formatDateKey(initialDate ?? DateTime.now());

  String get currentDateKey => _currentDateKey;
  Map<String, AppLockConfig> get configs => Map.unmodifiable(_configs);

  static String _formatDateKey(DateTime dt) {
    final y = dt.year.toString().padLeft(4, '0');
    final m = dt.month.toString().padLeft(2, '0');
    final d = dt.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }

  /// Registers or updates an app lock config in the engine.
  void registerConfig(AppLockConfig config) {
    _configs[config.appId] = config;
  }

  /// Sets the daily quota minutes for an app.
  void setDailyQuota(String appId, int quotaMinutes) {
    final existing = _configs[appId];
    if (existing != null) {
      _configs[appId] = existing.copyWith(dailyQuotaMinutes: quotaMinutes);
    }
  }

  /// Records active foreground seconds used for an application.
  /// Returns true if this usage caused the quota to become exhausted.
  bool recordForegroundUsage(String appId, int secondsUsed, DateTime timestamp) {
    checkMidnightRollover(timestamp);

    final config = _configs[appId];
    if (config == null || config.mode != AppLockMode.dailyQuota) return false;

    final wasDepletedBefore = config.isQuotaDepleted;
    final updatedUsed = config.usedQuotaSecondsToday + secondsUsed;
    final updated = config.copyWith(usedQuotaSecondsToday: updatedUsed);
    _configs[appId] = updated;

    if (!wasDepletedBefore && updated.isQuotaDepleted) {
      // Quota just got exhausted!
      _configs[appId] = updated.copyWith(isCurrentlyLocked: true);
      onQuotaDepleted?.call(appId, config.packageName);
      return true;
    }
    return false;
  }

  /// Inspects current time and executes midnight quota rollover if day changed.
  bool checkMidnightRollover(DateTime now) {
    final nowKey = _formatDateKey(now);
    if (nowKey != _currentDateKey) {
      final oldKey = _currentDateKey;
      _currentDateKey = nowKey;

      // Reset quota for all apps
      _configs.forEach((appId, cfg) {
        if (cfg.mode == AppLockMode.dailyQuota) {
          _configs[appId] = cfg.copyWith(
            usedQuotaSecondsToday: 0,
            isCurrentlyLocked: false,
          );
        }
      });

      onMidnightRollover?.call(oldKey, nowKey);
      return true;
    }
    return false;
  }

  /// Returns remaining quota in seconds for an application.
  int getRemainingSeconds(String appId) {
    final config = _configs[appId];
    if (config == null) return 0;
    return config.remainingQuotaSecondsToday;
  }
}
