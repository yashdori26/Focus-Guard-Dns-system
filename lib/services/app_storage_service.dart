import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/app_models.dart';

/// Centralized local persistent storage service for FocusDNS settings,
/// blocked apps, categories, timers, and protection states.
class AppStorageService {
  static const String _keyWebsites = 'focus_blocked_websites';
  static const String _keyCategories = 'focus_blocked_categories';
  static const String _keyProtectionOn = 'focus_protection_on';
  static const String _keyStrictMode = 'focus_strict_mode';
  static const String _keyStrictUntilMs = 'focus_strict_until_ms';
  static const String _keyPerAppTimers = 'focus_per_app_timers';
  static const String _keyRoutineConfig = 'focus_routine_config';
  static const String _keyRoutineActiveState = 'focus_routine_active_state';
  static const String _keyThemeMode = 'focus_theme_mode';
  static const String _keyDenylist = 'focus_custom_denylist';
  static const String _keyAllowlist = 'focus_custom_allowlist';
  static const String _keyPrefixSecurity = 'focus_sec_';
  static const String _keyPrefixPrivacy = 'focus_priv_';

  static SharedPreferences? _cachedPrefs;

  static Future<SharedPreferences> _getPrefs() async {
    _cachedPrefs ??= await SharedPreferences.getInstance();
    return _cachedPrefs!;
  }

  // --- Blocked Websites / Apps ---
  static Future<List<BlockedItem>?> loadBlockedWebsites() async {
    try {
      final prefs = await _getPrefs();
      final raw = prefs.getString(_keyWebsites);
      if (raw == null || raw.isEmpty) return null;
      final List<dynamic> decoded = json.decode(raw);
      return decoded.map((e) => BlockedItem.fromJson(e as Map<String, dynamic>)).toList();
    } catch (e) {
      debugPrint('[AppStorageService] Error loading websites: $e');
      return null;
    }
  }

  static Future<void> saveBlockedWebsites(List<BlockedItem> items) async {
    try {
      final prefs = await _getPrefs();
      final list = items.map((e) => e.toJson()).toList();
      await prefs.setString(_keyWebsites, json.encode(list));
    } catch (e) {
      debugPrint('[AppStorageService] Error saving websites: $e');
    }
  }

  // --- Blocked Categories ---
  static Future<List<BlockedItem>?> loadBlockedCategories() async {
    try {
      final prefs = await _getPrefs();
      final raw = prefs.getString(_keyCategories);
      if (raw == null || raw.isEmpty) return null;
      final List<dynamic> decoded = json.decode(raw);
      return decoded.map((e) => BlockedItem.fromJson(e as Map<String, dynamic>)).toList();
    } catch (e) {
      debugPrint('[AppStorageService] Error loading categories: $e');
      return null;
    }
  }

  static Future<void> saveBlockedCategories(List<BlockedItem> items) async {
    try {
      final prefs = await _getPrefs();
      final list = items.map((e) => e.toJson()).toList();
      await prefs.setString(_keyCategories, json.encode(list));
    } catch (e) {
      debugPrint('[AppStorageService] Error saving categories: $e');
    }
  }

  // --- Protection State ---
  static Future<bool?> loadProtectionState() async {
    try {
      final prefs = await _getPrefs();
      if (!prefs.containsKey(_keyProtectionOn)) return null;
      return prefs.getBool(_keyProtectionOn);
    } catch (_) {
      return null;
    }
  }

  static Future<void> saveProtectionState(bool isOn) async {
    try {
      final prefs = await _getPrefs();
      await prefs.setBool(_keyProtectionOn, isOn);
    } catch (_) {}
  }

  // --- Strict Mode ---
  static Future<bool?> loadStrictMode() async {
    try {
      final prefs = await _getPrefs();
      if (!prefs.containsKey(_keyStrictMode)) return null;
      return prefs.getBool(_keyStrictMode);
    } catch (_) {
      return null;
    }
  }

  static Future<void> saveStrictMode(bool isStrict) async {
    try {
      final prefs = await _getPrefs();
      await prefs.setBool(_keyStrictMode, isStrict);
    } catch (_) {}
  }

  static Future<int?> loadStrictUntilEpochMs() async {
    try {
      final prefs = await _getPrefs();
      if (!prefs.containsKey(_keyStrictUntilMs)) return null;
      return prefs.getInt(_keyStrictUntilMs);
    } catch (_) {
      return null;
    }
  }

  static Future<void> saveStrictUntilEpochMs(int? epochMs) async {
    try {
      final prefs = await _getPrefs();
      if (epochMs == null) {
        await prefs.remove(_keyStrictUntilMs);
      } else {
        await prefs.setInt(_keyStrictUntilMs, epochMs);
      }
    } catch (_) {}
  }

  // --- Per-App Timers ---
  static Future<String?> loadPerAppTimersJson() async {
    try {
      final prefs = await _getPrefs();
      return prefs.getString(_keyPerAppTimers);
    } catch (_) {
      return null;
    }
  }

  static Future<void> savePerAppTimersJson(String jsonStr) async {
    try {
      final prefs = await _getPrefs();
      await prefs.setString(_keyPerAppTimers, jsonStr);
    } catch (_) {}
  }

  // --- Routine Focus (Pomodoro) ---
  static Future<Map<String, int>?> loadRoutineConfig() async {
    try {
      final prefs = await _getPrefs();
      final raw = prefs.getString(_keyRoutineConfig);
      if (raw == null || raw.isEmpty) return null;
      final decoded = json.decode(raw) as Map<String, dynamic>;
      return {
        'sessionMinutes': decoded['sessionMinutes'] as int? ?? 45,
        'breakMinutes': decoded['breakMinutes'] as int? ?? 10,
        'totalCycles': decoded['totalCycles'] as int? ?? 3,
      };
    } catch (_) {
      return null;
    }
  }

  static Future<void> saveRoutineConfig({
    required int sessionMinutes,
    required int breakMinutes,
    required int totalCycles,
  }) async {
    try {
      final prefs = await _getPrefs();
      final map = {
        'sessionMinutes': sessionMinutes,
        'breakMinutes': breakMinutes,
        'totalCycles': totalCycles,
      };
      await prefs.setString(_keyRoutineConfig, json.encode(map));
    } catch (_) {}
  }

  static Future<void> saveActiveRoutineState({
    required bool isActive,
    required String phase,
    required int currentCycle,
    required bool isStrict,
    required bool isPaused,
    required int remainingSeconds,
    DateTime? targetEndTime,
    int? sessionMinutes,
    int? breakMinutes,
    int? totalCycles,
  }) async {
    try {
      final prefs = await _getPrefs();
      if (!isActive) {
        await prefs.remove(_keyRoutineActiveState);
        return;
      }
      final map = {
        'isActive': isActive,
        'phase': phase,
        'currentCycle': currentCycle,
        'isStrict': isStrict,
        'isPaused': isPaused,
        'remainingSeconds': remainingSeconds,
        'targetEndTime': targetEndTime?.millisecondsSinceEpoch,
        'sessionMinutes': sessionMinutes,
        'breakMinutes': breakMinutes,
        'totalCycles': totalCycles,
      };
      await prefs.setString(_keyRoutineActiveState, json.encode(map));
    } catch (_) {}
  }

  static Future<Map<String, dynamic>?> loadActiveRoutineState() async {
    try {
      final prefs = await _getPrefs();
      final raw = prefs.getString(_keyRoutineActiveState);
      if (raw == null) return null;
      return json.decode(raw) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  static Future<void> clearActiveRoutineState() async {
    try {
      final prefs = await _getPrefs();
      await prefs.remove(_keyRoutineActiveState);
    } catch (_) {}
  }

  // --- Theme Mode ---
  static Future<String?> loadThemeMode() async {
    try {
      final prefs = await _getPrefs();
      return prefs.getString(_keyThemeMode);
    } catch (_) {
      return null;
    }
  }

  static Future<void> saveThemeMode(String themeName) async {
    try {
      final prefs = await _getPrefs();
      await prefs.setString(_keyThemeMode, themeName);
    } catch (_) {}
  }

  // --- Denylist & Allowlist ---
  static Future<List<String>?> loadDenylist() async {
    try {
      final prefs = await _getPrefs();
      return prefs.getStringList(_keyDenylist);
    } catch (_) {
      return null;
    }
  }

  static Future<void> saveDenylist(List<String> domains) async {
    try {
      final prefs = await _getPrefs();
      await prefs.setStringList(_keyDenylist, domains);
    } catch (_) {}
  }

  static Future<List<String>?> loadAllowlist() async {
    try {
      final prefs = await _getPrefs();
      return prefs.getStringList(_keyAllowlist);
    } catch (_) {
      return null;
    }
  }

  static Future<void> saveAllowlist(List<String> domains) async {
    try {
      final prefs = await _getPrefs();
      await prefs.setStringList(_keyAllowlist, domains);
    } catch (_) {}
  }

  // --- Security & Privacy Features ---
  static Future<bool?> loadSecurityFeature(String key) async {
    try {
      final prefs = await _getPrefs();
      final fullKey = '$_keyPrefixSecurity$key';
      if (!prefs.containsKey(fullKey)) return null;
      return prefs.getBool(fullKey);
    } catch (_) {
      return null;
    }
  }

  static Future<void> saveSecurityFeature(String key, bool val) async {
    try {
      final prefs = await _getPrefs();
      await prefs.setBool('$_keyPrefixSecurity$key', val);
    } catch (_) {}
  }

  static Future<bool?> loadPrivacyFeature(String key) async {
    try {
      final prefs = await _getPrefs();
      final fullKey = '$_keyPrefixPrivacy$key';
      if (!prefs.containsKey(fullKey)) return null;
      return prefs.getBool(fullKey);
    } catch (_) {
      return null;
    }
  }

  static Future<void> savePrivacyFeature(String key, bool val) async {
    try {
      final prefs = await _getPrefs();
      await prefs.setBool('$_keyPrefixPrivacy$key', val);
    } catch (_) {}
  }
}
