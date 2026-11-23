import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// App category classifications for differential restriction policies.
enum AppCategory {
  social,
  shortFormVideo,
  longFormVideo,
  gaming,
  communication,
  browser,
  shopping,
  adult,
  gambling,
  productivity,
  system,
}

/// Dopamine extraction risk rating assigned to addictive applications.
enum DopamineRiskRating {
  low,
  moderate,
  high,
  extremeDopamineTrap,
}

/// Immutable record of an individual application managed by the Per-App Lockout Engine.
@immutable
class ManagedAppRecord {
  final String appId;
  final String appName;
  final String packageName;
  final List<String> secondaryPackages;
  final List<String> networkDomains;
  final AppCategory category;
  final DopamineRiskRating riskRating;
  final String iconGlyph;
  final int allocatedLockMinutes;
  final int remainingLockSeconds;
  final DateTime? targetEndTime;
  final bool isLocked;
  final int totalInterventionBlocks;
  final int accumulatedReclaimedMinutes;

  const ManagedAppRecord({
    required this.appId,
    required this.appName,
    required this.packageName,
    this.secondaryPackages = const [],
    this.networkDomains = const [],
    required this.category,
    this.riskRating = DopamineRiskRating.moderate,
    required this.iconGlyph,
    required this.allocatedLockMinutes,
    this.remainingLockSeconds = 0,
    this.targetEndTime,
    this.isLocked = false,
    this.totalInterventionBlocks = 0,
    this.accumulatedReclaimedMinutes = 0,
  });

  bool get isLockActive => isLocked && remainingLockSeconds > 0;

  ManagedAppRecord copyWith({
    String? appId,
    String? appName,
    String? packageName,
    List<String>? secondaryPackages,
    List<String>? networkDomains,
    AppCategory? category,
    DopamineRiskRating? riskRating,
    String? iconGlyph,
    int? allocatedLockMinutes,
    int? remainingLockSeconds,
    DateTime? targetEndTime,
    bool? isLocked,
    int? totalInterventionBlocks,
    int? accumulatedReclaimedMinutes,
  }) {
    return ManagedAppRecord(
      appId: appId ?? this.appId,
      appName: appName ?? this.appName,
      packageName: packageName ?? this.packageName,
      secondaryPackages: secondaryPackages ?? this.secondaryPackages,
      networkDomains: networkDomains ?? this.networkDomains,
      category: category ?? this.category,
      riskRating: riskRating ?? this.riskRating,
      iconGlyph: iconGlyph ?? this.iconGlyph,
      allocatedLockMinutes: (allocatedLockMinutes ?? this.allocatedLockMinutes).clamp(5, 480),
      remainingLockSeconds: (remainingLockSeconds ?? this.remainingLockSeconds).clamp(0, 480 * 60),
      targetEndTime: targetEndTime ?? this.targetEndTime,
      isLocked: isLocked ?? this.isLocked,
      totalInterventionBlocks: totalInterventionBlocks ?? this.totalInterventionBlocks,
      accumulatedReclaimedMinutes: accumulatedReclaimedMinutes ?? this.accumulatedReclaimedMinutes,
    );
  }

  Map<String, dynamic> toJson() => {
    'appId': appId,
    'appName': appName,
    'packageName': packageName,
    'secondaryPackages': secondaryPackages,
    'networkDomains': networkDomains,
    'category': category.name,
    'riskRating': riskRating.name,
    'iconGlyph': iconGlyph,
    'allocatedLockMinutes': allocatedLockMinutes,
    'remainingLockSeconds': remainingLockSeconds,
    'targetEndTime': targetEndTime?.toIso8601String(),
    'isLocked': isLocked,
    'totalInterventionBlocks': totalInterventionBlocks,
    'accumulatedReclaimedMinutes': accumulatedReclaimedMinutes,
  };

  factory ManagedAppRecord.fromJson(Map<String, dynamic> json) {
    return ManagedAppRecord(
      appId: json['appId'] as String,
      appName: json['appName'] as String,
      packageName: json['packageName'] as String,
      secondaryPackages: (json['secondaryPackages'] as List<dynamic>?)?.map((e) => e as String).toList() ?? const [],
      networkDomains: (json['networkDomains'] as List<dynamic>?)?.map((e) => e as String).toList() ?? const [],
      category: AppCategory.values.byName(json['category'] as String? ?? 'social'),
      riskRating: DopamineRiskRating.values.byName(json['riskRating'] as String? ?? 'moderate'),
      iconGlyph: json['iconGlyph'] as String? ?? '📱',
      allocatedLockMinutes: ((json['allocatedLockMinutes'] as num?)?.toInt() ?? 60).clamp(5, 480),
      remainingLockSeconds: (json['remainingLockSeconds'] as num?)?.toInt() ?? 0,
      targetEndTime: json['targetEndTime'] != null ? DateTime.parse(json['targetEndTime'] as String) : null,
      isLocked: json['isLocked'] as bool? ?? false,
      totalInterventionBlocks: (json['totalInterventionBlocks'] as num?)?.toInt() ?? 0,
      accumulatedReclaimedMinutes: (json['accumulatedReclaimedMinutes'] as num?)?.toInt() ?? 0,
    );
  }
}

/// Persistent relational storage layer for per-app lockout configs and telemetry counters.
class PerAppDatabase {
  static const String _prefKeyApps = 'focus_dns_managed_apps_catalog_v2';
  final SharedPreferences? _prefs;

  PerAppDatabase([this._prefs]);

  Future<SharedPreferences> _getPrefs() async {
    return _prefs ?? await SharedPreferences.getInstance();
  }

  /// Loads all configured apps from storage.
  Future<Map<String, ManagedAppRecord>> loadAllApps() async {
    final prefs = await _getPrefs();
    final raw = prefs.getString(_prefKeyApps);
    if (raw == null) return {};

    try {
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      final map = <String, ManagedAppRecord>{};
      decoded.forEach((key, val) {
        map[key] = ManagedAppRecord.fromJson(val as Map<String, dynamic>);
      });
      return map;
    } catch (e) {
      debugPrint('[PerAppDatabase] Error parsing apps catalog: $e');
      return {};
    }
  }

  /// Saves the complete map of managed apps to persistent storage.
  Future<void> saveAllApps(Map<String, ManagedAppRecord> apps) async {
    final prefs = await _getPrefs();
    final map = <String, dynamic>{};
    apps.forEach((key, record) {
      map[key] = record.toJson();
    });
    await prefs.setString(_prefKeyApps, jsonEncode(map));
  }

  /// Updates or inserts a single managed app record atomically.
  Future<void> upsertApp(ManagedAppRecord app) async {
    final all = await loadAllApps();
    all[app.appId] = app;
    await saveAllApps(all);
  }

  /// Removes an app from active managed list.
  Future<void> removeApp(String appId) async {
    final all = await loadAllApps();
    if (all.containsKey(appId)) {
      all.remove(appId);
      await saveAllApps(all);
    }
  }

  /// Resets all active locks to unlocked.
  Future<void> unlockAll() async {
    final all = await loadAllApps();
    final updated = <String, ManagedAppRecord>{};
    all.forEach((key, record) {
      updated[key] = record.copyWith(
        isLocked: false,
        remainingLockSeconds: 0,
        targetEndTime: null,
      );
    });
    await saveAllApps(updated);
  }
}
