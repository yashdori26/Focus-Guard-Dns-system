import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../backend/blocker_service.dart';
import '../backend/vpn_service.dart';
import '../services/app_storage_service.dart';

class AppBlockTimer {
  final String appId; // e.g. 'instagram'
  final String appName;
  final String icon;
  final List<String> packages;
  final List<String> domains;
  final int allocatedMinutes;
  final int remainingSeconds;
  final DateTime? targetEndTime;
  final bool isLocked;

  const AppBlockTimer({
    required this.appId,
    required this.appName,
    required this.icon,
    this.packages = const [],
    this.domains = const [],
    required this.allocatedMinutes,
    this.remainingSeconds = 0,
    this.targetEndTime,
    this.isLocked = false,
  });

  AppBlockTimer copyWith({
    String? appId,
    String? appName,
    String? icon,
    List<String>? packages,
    List<String>? domains,
    int? allocatedMinutes,
    int? remainingSeconds,
    DateTime? targetEndTime,
    bool? isLocked,
  }) {
    return AppBlockTimer(
      appId: appId ?? this.appId,
      appName: appName ?? this.appName,
      icon: icon ?? this.icon,
      packages: packages ?? this.packages,
      domains: domains ?? this.domains,
      allocatedMinutes: allocatedMinutes ?? this.allocatedMinutes,
      remainingSeconds: remainingSeconds ?? this.remainingSeconds,
      targetEndTime: targetEndTime ?? this.targetEndTime,
      isLocked: isLocked ?? this.isLocked,
    );
  }

  Map<String, dynamic> toJson() => {
    'appId': appId,
    'appName': appName,
    'icon': icon,
    'packages': packages,
    'domains': domains,
    'allocatedMinutes': allocatedMinutes,
    'remainingSeconds': remainingSeconds,
    'targetEndTime': targetEndTime?.toIso8601String(),
    'isLocked': isLocked,
  };

  factory AppBlockTimer.fromJson(Map<String, dynamic> json) => AppBlockTimer(
    appId: json['appId'] as String? ?? '',
    appName: json['appName'] as String? ?? '',
    icon: json['icon'] as String? ?? '',
    packages: (json['packages'] as List<dynamic>?)?.map((e) => e.toString()).toList() ?? const [],
    domains: (json['domains'] as List<dynamic>?)?.map((e) => e.toString()).toList() ?? const [],
    allocatedMinutes: json['allocatedMinutes'] as int? ?? 60,
    remainingSeconds: json['remainingSeconds'] as int? ?? 0,
    targetEndTime: json['targetEndTime'] != null ? DateTime.tryParse(json['targetEndTime'] as String) : null,
    isLocked: json['isLocked'] as bool? ?? false,
  );
}

class PerAppTimersNotifier extends StateNotifier<Map<String, AppBlockTimer>> {
  Timer? _ticker;
  final bool enableTicker;

  PerAppTimersNotifier({this.enableTicker = true}) : super(const {}) {
    _initPersistence();
  }

  static const Map<String, AppBlockTimer> defaultPresets = {
    'instagram': AppBlockTimer(
      appId: 'instagram',
      appName: 'Instagram',
      icon: '📸',
      packages: ['com.instagram.android'],
      domains: [
        'instagram.com',
        'cdninstagram.com',
        'ig.me',
        'threads.net',
        'threads.com',
        'fbcdn.net',
        'facebook.com',
        'meta.com',
      ],
      allocatedMinutes: 480, // 8 hours preset
      remainingSeconds: 0,
      isLocked: false,
    ),
    'youtube': AppBlockTimer(
      appId: 'youtube',
      appName: 'YouTube',
      icon: '▶️',
      packages: ['com.google.android.youtube'],
      domains: [
        'youtube.com',
        'googlevideo.com',
        'ytimg.com',
        'youtu.be',
        'youtubei.googleapis.com',
        'yt3.ggpht.com',
      ],
      allocatedMinutes: 120, // 2 hours preset
      remainingSeconds: 0,
      isLocked: false,
    ),
    'reddit': AppBlockTimer(
      appId: 'reddit',
      appName: 'Reddit',
      icon: '👾',
      packages: ['com.reddit.frontpage'],
      domains: [
        'reddit.com',
        'redd.it',
        'redditmedia.com',
        'redditstatic.com',
      ],
      allocatedMinutes: 360, // 6 hours preset
      remainingSeconds: 0,
      isLocked: false,
    ),
  };

  Future<void> _initPersistence() async {
    final raw = await AppStorageService.loadPerAppTimersJson();
    if (!mounted) return;
    if (raw != null && raw.isNotEmpty) {
      try {
        final decoded = json.decode(raw) as Map<String, dynamic>;
        final map = <String, AppBlockTimer>{};
        final now = DateTime.now();
        var hasActiveLock = false;

        decoded.forEach((key, val) {
          final timer = AppBlockTimer.fromJson(val as Map<String, dynamic>);
          if (timer.isLocked && timer.targetEndTime != null) {
            final diff = timer.targetEndTime!.difference(now).inSeconds;
            if (diff > 0) {
              hasActiveLock = true;
              map[key] = timer.copyWith(remainingSeconds: diff);
            } else {
              map[key] = timer.copyWith(remainingSeconds: 0, targetEndTime: null, isLocked: false);
            }
          } else {
            map[key] = timer;
          }
        });

        defaultPresets.forEach((k, v) {
          if (!map.containsKey(k)) {
            map[k] = v;
          }
        });

        state = map;
        if (hasActiveLock) {
          _syncActiveBlocks();
          _startTickerIfNeeded();
        }
        return;
      } catch (e) {
        debugPrint('[PerAppTimers] Error loading persisted timers: $e');
      }
    }
    _initDefaultPresets();
  }

  void _persistState() {
    final map = state.map((k, v) => MapEntry(k, v.toJson()));
    AppStorageService.savePerAppTimersJson(json.encode(map));
  }

  void _initDefaultPresets() {
    state = Map.from(defaultPresets);
  }

  void setCustomMinutes(String appId, int minutes) {
    if (!state.containsKey(appId)) return;
    if (state[appId]!.isLocked) return; // Cannot alter while running
    final clamped = minutes.clamp(5, 480);
    state = {
      ...state,
      appId: state[appId]!.copyWith(allocatedMinutes: clamped),
    };
    _persistState();
  }

  void addCustomApp(AppBlockTimer app) {
    state = {...state, app.appId: app};
    _persistState();
  }

  void tickForTesting(DateTime simulatedNow) {
    var anyActive = false;
    final updatedMap = <String, AppBlockTimer>{};

    state.forEach((id, timerItem) {
      if (timerItem.isLocked && timerItem.targetEndTime != null) {
        final diff = timerItem.targetEndTime!.difference(simulatedNow).inSeconds;
        if (diff > 0) {
          anyActive = true;
          updatedMap[id] = timerItem.copyWith(remainingSeconds: diff);
        } else {
          updatedMap[id] = timerItem.copyWith(
            remainingSeconds: 0,
            targetEndTime: null,
            isLocked: false,
          );
        }
      } else {
        updatedMap[id] = timerItem;
      }
    });

    state = updatedMap;
    if (!anyActive) {
      _syncActiveBlocks();
    }
  }

  void startAppLock(String appId, {int? customMinutes}) {
    if (!state.containsKey(appId)) return;
    final item = state[appId]!;
    final minutes = customMinutes ?? item.allocatedMinutes;
    final seconds = minutes * 60;

    final updatedItem = item.copyWith(
      allocatedMinutes: minutes,
      remainingSeconds: seconds,
      targetEndTime: DateTime.now().add(Duration(seconds: seconds)),
      isLocked: true,
    );

    state = {...state, appId: updatedItem};
    _persistState();
    _syncActiveBlocks();
    _startTickerIfNeeded();
  }

  void _startTickerIfNeeded() {
    if (!enableTicker) return;
    if (_ticker != null && _ticker!.isActive) return;

    _ticker = Timer.periodic(const Duration(seconds: 1), (timer) {
      final now = DateTime.now();
      var anyActive = false;
      final updatedMap = <String, AppBlockTimer>{};

      state.forEach((id, timerItem) {
        if (timerItem.isLocked && timerItem.targetEndTime != null) {
          final diff = timerItem.targetEndTime!.difference(now).inSeconds;
          if (diff > 0) {
            anyActive = true;
            updatedMap[id] = timerItem.copyWith(remainingSeconds: diff);
          } else {
            // Timer finished for this specific app
            updatedMap[id] = timerItem.copyWith(
              remainingSeconds: 0,
              targetEndTime: null,
              isLocked: false,
            );
          }
        } else {
          updatedMap[id] = timerItem;
        }
      });

      state = updatedMap;

      if (!anyActive) {
        timer.cancel();
        _ticker = null;
        _persistState();
        _syncActiveBlocks();
      }
    });
  }

  void _syncActiveBlocks() {
    final activePackages = <String>[];
    final activeDomains = <String>[];

    state.values.where((e) => e.isLocked).forEach((e) {
      activePackages.addAll(e.packages);
      activeDomains.addAll(e.domains);
    });

    try {
      FocusDnsBlockerManager.setBlockedPackages(activePackages);
      FocusDnsVpnManager.updateDnsRules(
        blockedDomains: activeDomains,
        allowedDomains: [],
      );
    } catch (_) {}
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }
}

final perAppTimersProvider =
    StateNotifierProvider<PerAppTimersNotifier, Map<String, AppBlockTimer>>((ref) {
  return PerAppTimersNotifier();
});
