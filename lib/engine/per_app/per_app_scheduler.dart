import 'dart:async';
import 'package:flutter/foundation.dart';
import '../../backend/blocker_service.dart';
import '../../backend/vpn_service.dart';
import 'installed_apps_catalog.dart';
import 'per_app_database.dart';

/// Central high-concurrency scheduler managing multi-app timers and atomic native synchronization.
class PerAppScheduler extends ChangeNotifier {
  final PerAppDatabase _database;
  Map<String, ManagedAppRecord> _apps = {};
  Timer? _ticker;
  final bool enableAutomaticTicker;

  PerAppScheduler({
    PerAppDatabase? database,
    this.enableAutomaticTicker = true,
  }) : _database = database ?? PerAppDatabase() {
    _initialize();
  }

  Map<String, ManagedAppRecord> get apps => Map.unmodifiable(_apps);
  List<ManagedAppRecord> get allAppsList => _apps.values.toList();
  List<ManagedAppRecord> get activeLockedApps => _apps.values.where((a) => a.isLockActive).toList();

  Future<void> _initialize() async {
    final loaded = await _database.loadAllApps();
    if (loaded.isEmpty) {
      _apps = InstalledAppsCatalog.getInitialPresetsMap();
      await _database.saveAllApps(_apps);
    } else {
      _apps = loaded;
    }
    _reconcileExpiredTimers(DateTime.now());
    notifyListeners();
  }

  /// Sets the allocated lock duration for an app (5 minutes to 480 minutes / 8 hours).
  Future<void> setAllocatedMinutes(String appId, int minutes) async {
    final app = _apps[appId];
    if (app == null || app.isLockActive) return; // Cannot modify running lock

    final clamped = minutes.clamp(5, 480);
    _apps[appId] = app.copyWith(allocatedLockMinutes: clamped);
    notifyListeners();
    await _database.saveAllApps(_apps);
  }

  /// Engages a lockout on an individual application.
  Future<void> lockApp(String appId, {int? customMinutes}) async {
    final app = _apps[appId];
    if (app == null) return;

    final minutes = customMinutes ?? app.allocatedLockMinutes;
    final seconds = minutes * 60;
    final now = DateTime.now();

    _apps[appId] = app.copyWith(
      allocatedLockMinutes: minutes,
      remainingLockSeconds: seconds,
      targetEndTime: now.add(Duration(seconds: seconds)),
      isLocked: true,
    );

    notifyListeners();
    await _database.saveAllApps(_apps);
    await _syncPlatformRules();
    _armTickerIfNeeded();
  }

  /// Unlocks an individual application immediately.
  Future<void> unlockApp(String appId) async {
    final app = _apps[appId];
    if (app == null) return;

    _apps[appId] = app.copyWith(
      isLocked: false,
      remainingLockSeconds: 0,
      targetEndTime: null,
    );

    notifyListeners();
    await _database.saveAllApps(_apps);
    await _syncPlatformRules();
  }

  /// Locks multiple apps matching a specific category.
  Future<void> lockCategory(AppCategory category, {int? durationMinutes}) async {
    final now = DateTime.now();
    _apps.forEach((id, app) {
      if (app.category == category) {
        final minutes = durationMinutes ?? app.allocatedLockMinutes;
        final seconds = minutes * 60;
        _apps[id] = app.copyWith(
          allocatedLockMinutes: minutes,
          remainingLockSeconds: seconds,
          targetEndTime: now.add(Duration(seconds: seconds)),
          isLocked: true,
        );
      }
    });

    notifyListeners();
    await _database.saveAllApps(_apps);
    await _syncPlatformRules();
    _armTickerIfNeeded();
  }

  /// Adds a custom application to the managed registry.
  Future<void> addCustomApp(ManagedAppRecord app) async {
    _apps[app.appId] = app;
    notifyListeners();
    await _database.saveAllApps(_apps);
  }

  void _armTickerIfNeeded() {
    if (!enableAutomaticTicker) return;
    if (_ticker != null && _ticker!.isActive) return;

    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      _tick(DateTime.now());
    });
  }

  void _tick(DateTime now) {
    bool stateChanged = false;
    bool hasActiveLock = false;

    _apps.forEach((id, app) {
      if (app.isLocked && app.targetEndTime != null) {
        final diff = app.targetEndTime!.difference(now).inSeconds;
        if (diff > 0) {
          hasActiveLock = true;
          _apps[id] = app.copyWith(
            remainingLockSeconds: diff,
            accumulatedReclaimedMinutes: app.accumulatedReclaimedMinutes,
          );
          stateChanged = true;
        } else {
          // Timer expired for this specific app
          _apps[id] = app.copyWith(
            isLocked: false,
            remainingLockSeconds: 0,
            targetEndTime: null,
          );
          stateChanged = true;
        }
      }
    });

    if (stateChanged) {
      notifyListeners();
    }

    if (!hasActiveLock) {
      _ticker?.cancel();
      _ticker = null;
      _syncPlatformRules();
      _database.saveAllApps(_apps);
    }
  }

  void _reconcileExpiredTimers(DateTime now) {
    bool hasActive = false;
    _apps.forEach((id, app) {
      if (app.isLocked && app.targetEndTime != null) {
        final diff = app.targetEndTime!.difference(now).inSeconds;
        if (diff <= 0) {
          _apps[id] = app.copyWith(
            isLocked: false,
            remainingLockSeconds: 0,
            targetEndTime: null,
          );
        } else {
          hasActive = true;
          _apps[id] = app.copyWith(remainingLockSeconds: diff);
        }
      }
    });

    if (hasActive) {
      _armTickerIfNeeded();
    }
    _syncPlatformRules();
  }

  Future<void> _syncPlatformRules() async {
    final activePackages = <String>[];
    final activeDomains = <String>[];

    for (final app in activeLockedApps) {
      activePackages.add(app.packageName);
      activePackages.addAll(app.secondaryPackages);
      activeDomains.addAll(app.networkDomains);
    }

    try {
      await FocusDnsBlockerManager.setBlockedPackages(activePackages);
      await FocusDnsVpnManager.updateDnsRules(
        blockedDomains: activeDomains,
        allowedDomains: const [],
      );
    } catch (e) {
      debugPrint('[PerAppScheduler] Error syncing platform rules: $e');
    }
  }

  /// Test hook for simulating monotonic time passage without waiting.
  @visibleForTesting
  void tickForTesting(DateTime simulatedTime) {
    _tick(simulatedTime);
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }
}
