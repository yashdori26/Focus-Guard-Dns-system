import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/app_lock_config.dart';
import '../models/app_usage_record.dart';
import '../models/recurring_schedule_rule.dart';

/// Atomic persistence journal for per-app lock configurations, recurring schedules, and usage logs.
class PerAppStorageJournal {
  static const String _keyConfigs = 'focus_dns_per_app_configs_v3';
  static const String _keySchedules = 'focus_dns_per_app_schedules_v3';
  static const String _keyUsagePrefix = 'focus_dns_usage_record_v3_';
  static const String _keyTamperLog = 'focus_dns_tamper_strikes_v3';

  final SharedPreferences? _prefs;

  PerAppStorageJournal([this._prefs]);

  Future<SharedPreferences> _getPrefs() async {
    return _prefs ?? await SharedPreferences.getInstance();
  }

  /// Loads all app lock configurations.
  Future<Map<String, AppLockConfig>> loadConfigs() async {
    final prefs = await _getPrefs();
    final raw = prefs.getString(_keyConfigs);
    if (raw == null) return {};

    try {
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      final result = <String, AppLockConfig>{};
      decoded.forEach((key, val) {
        result[key] = AppLockConfig.fromJson(val as Map<String, dynamic>);
      });
      return result;
    } catch (e) {
      debugPrint('[PerAppStorageJournal] Error parsing configs: $e');
      return {};
    }
  }

  /// Saves all app lock configurations.
  Future<void> saveConfigs(Map<String, AppLockConfig> configs) async {
    final prefs = await _getPrefs();
    final map = <String, dynamic>{};
    configs.forEach((key, val) => map[key] = val.toJson());
    await prefs.setString(_keyConfigs, jsonEncode(map));
  }

  /// Loads all recurring schedule rules.
  Future<Map<String, RecurringScheduleRule>> loadSchedules() async {
    final prefs = await _getPrefs();
    final raw = prefs.getString(_keySchedules);
    if (raw == null) return {};

    try {
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      final result = <String, RecurringScheduleRule>{};
      decoded.forEach((key, val) {
        result[key] = RecurringScheduleRule.fromJson(val as Map<String, dynamic>);
      });
      return result;
    } catch (e) {
      debugPrint('[PerAppStorageJournal] Error parsing schedules: $e');
      return {};
    }
  }

  /// Saves all recurring schedule rules.
  Future<void> saveSchedules(Map<String, RecurringScheduleRule> rules) async {
    final prefs = await _getPrefs();
    final map = <String, dynamic>{};
    rules.forEach((key, val) => map[key] = val.toJson());
    await prefs.setString(_keySchedules, jsonEncode(map));
  }

  /// Loads daily usage record for an app on a given date.
  Future<AppDailyUsageRecord?> loadUsageRecord(String appId, String dateKey) async {
    final prefs = await _getPrefs();
    final key = '$_keyUsagePrefix${dateKey}_$appId';
    final raw = prefs.getString(key);
    if (raw == null) return null;

    try {
      return AppDailyUsageRecord.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (e) {
      debugPrint('[PerAppStorageJournal] Error parsing usage record: $e');
      return null;
    }
  }

  /// Saves daily usage record for an app on a given date.
  Future<void> saveUsageRecord(AppDailyUsageRecord record) async {
    final prefs = await _getPrefs();
    final key = '$_keyUsagePrefix${record.dateKey}_${record.appId}';
    await prefs.setString(key, jsonEncode(record.toJson()));
  }

  /// Records a clock tamper event strike.
  Future<void> recordTamperStrike(DateTime timestamp, String details) async {
    final prefs = await _getPrefs();
    final existing = prefs.getStringList(_keyTamperLog) ?? [];
    existing.add('${timestamp.toIso8601String()}|$details');
    await prefs.setStringList(_keyTamperLog, existing);
  }

  /// Returns total recorded tamper strike count.
  Future<int> getTamperStrikesCount() async {
    final prefs = await _getPrefs();
    final list = prefs.getStringList(_keyTamperLog) ?? [];
    return list.length;
  }
}
