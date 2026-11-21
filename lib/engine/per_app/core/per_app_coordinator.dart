import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:focus_dns/backend/blocker_service.dart';
import 'package:focus_dns/backend/vpn_service.dart';
import '../catalog/app_category_metadata.dart';
import '../catalog/app_definition.dart';
import '../catalog/comprehensive_app_catalog.dart';
import '../models/app_lock_config.dart';
import '../models/friction_challenge_model.dart';
import '../models/recurring_schedule_rule.dart';
import '../models/strictness_profile.dart';
import '../per_app_database.dart';
import 'anti_tamper_clock.dart';
import 'per_app_priority_queue.dart';
import 'per_app_quota_engine.dart';
import 'per_app_recurring_engine.dart';
import 'per_app_storage_journal.dart';

/// Central master coordinator orchestrating independent timers, daily quotas, recurring schedules, and DNS/native blocking.
class PerAppCoordinator extends ChangeNotifier {
  final PerAppStorageJournal _journal;
  final AntiTamperClock _clock;
  final PerAppPriorityQueue _priorityQueue;
  final PerAppQuotaEngine _quotaEngine;
  final PerAppRecurringEngine _recurringEngine;

  Map<String, AppLockConfig> _configs = {};
  Map<String, AppDefinition> _catalog = {};
  Timer? _ticker;
  final bool enableAutomaticTicker;
  bool _isDisposed = false;

  @override
  void notifyListeners() {
    if (!_isDisposed) {
      super.notifyListeners();
    }
  }

  PerAppCoordinator({
    PerAppStorageJournal? journal,
    AntiTamperClock? clock,
    PerAppPriorityQueue? priorityQueue,
    PerAppQuotaEngine? quotaEngine,
    PerAppRecurringEngine? recurringEngine,
    this.enableAutomaticTicker = true,
  })  : _journal = journal ?? PerAppStorageJournal(),
        _clock = clock ?? AntiTamperClock(),
        _priorityQueue = priorityQueue ?? PerAppPriorityQueue(),
        _quotaEngine = quotaEngine ?? PerAppQuotaEngine(),
        _recurringEngine = recurringEngine ?? PerAppRecurringEngine() {
    _initialize();
  }

  AntiTamperClock get clock => _clock;
  PerAppQuotaEngine get quotaEngine => _quotaEngine;
  PerAppRecurringEngine get recurringEngine => _recurringEngine;
  Map<String, AppLockConfig> get configs => Map.unmodifiable(_configs);
  Map<String, AppDefinition> get catalog => Map.unmodifiable(_catalog);

  /// All currently active locked configurations.
  List<AppLockConfig> get activeLocks => _configs.values.where((c) => c.isCurrentlyLocked).toList();

  Future<void> _initialize() async {
    _catalog = ComprehensiveAppCatalog.getMapById();
    final savedConfigs = await _journal.loadConfigs();
    final savedSchedules = await _journal.loadSchedules();

    if (savedConfigs.isEmpty) {
      // Seed default configs from catalog
      for (final def in ComprehensiveAppCatalog.allDefinitions) {
        _configs[def.id] = AppLockConfig(
          appId: def.id,
          packageName: def.primaryPackage,
          allocatedTimerMinutes: def.defaultAllocatedLockMinutes,
          dailyQuotaMinutes: def.defaultDailyQuotaMinutes,
          strictness: def.isExtremeTrap ? StrictnessTier.strictUnbreakable : StrictnessTier.frictionProtected,
          mode: def.isExtremeTrap ? AppLockMode.permanentBlock : AppLockMode.unlocked,
          isCurrentlyLocked: def.isExtremeTrap,
        );
      }
      await _journal.saveConfigs(_configs);
    } else {
      _configs = savedConfigs;
    }

    // Register into quota engine
    _configs.forEach((_, cfg) => _quotaEngine.registerConfig(cfg));

    // Register schedules into recurring engine
    savedSchedules.forEach((_, rule) => _recurringEngine.addRule(rule));

    _reconcileState(_clock.monotonicNow);
    notifyListeners();
  }

  /// Locks an application with an independent countdown timer.
  Future<void> lockAppTimer(
    String appId, {
    int? durationMinutes,
    StrictnessTier? strictness,
  }) async {
    final existing = _configs[appId];
    final minutes = durationMinutes ?? existing?.allocatedTimerMinutes ?? 120;
    final now = _clock.monotonicNow;
    final targetEnd = now.add(Duration(minutes: minutes));

    final def = _catalog[appId];
    final packageName = existing?.packageName ?? def?.primaryPackage ?? appId;

    final updated = (existing ?? AppLockConfig(appId: appId, packageName: packageName)).copyWith(
      mode: AppLockMode.independentTimer,
      allocatedTimerMinutes: minutes,
      lockStartTime: now,
      lockTargetEndTime: targetEnd,
      isCurrentlyLocked: true,
      strictness: strictness ?? existing?.strictness ?? StrictnessTier.strictUnbreakable,
    );

    _configs[appId] = updated;
    _quotaEngine.registerConfig(updated);

    // Insert into priority queue
    _priorityQueue.insert(ScheduleTriggerEvent(
      eventId: 'timer_$appId',
      appId: appId,
      packageName: packageName,
      targetTimestamp: targetEnd,
      eventType: PriorityEventType.timerExpired,
    ));

    notifyListeners();
    await _journal.saveConfigs(_configs);
    await _syncPlatformRules();
    _armTickerIfNeeded();
  }

  /// Unlocks an application immediately (if strictness allows).
  Future<bool> unlockApp(String appId, {bool bypassStrictness = false}) async {
    final config = _configs[appId];
    if (config == null || !config.isCurrentlyLocked) return true;

    final profile = StrictnessProfile.of(config.strictness);
    if (!profile.allowsEmergencyUnlock && !bypassStrictness) {
      debugPrint('[PerAppCoordinator] Unlock rejected: strictness is ${config.strictness.name}');
      return false;
    }

    _configs[appId] = config.copyWith(
      isCurrentlyLocked: false,
      lockTargetEndTime: null,
      mode: config.mode == AppLockMode.independentTimer ? AppLockMode.unlocked : config.mode,
    );

    _priorityQueue.removeByAppId(appId);

    notifyListeners();
    await _journal.saveConfigs(_configs);
    await _syncPlatformRules();
    return true;
  }

  /// Configures an app to operate in daily quota allowance mode.
  Future<void> configureDailyQuota(String appId, int quotaMinutes) async {
    final existing = _configs[appId];
    if (existing == null) return;

    final updated = existing.copyWith(
      mode: AppLockMode.dailyQuota,
      dailyQuotaMinutes: quotaMinutes,
    );

    _configs[appId] = updated;
    _quotaEngine.registerConfig(updated);

    notifyListeners();
    await _journal.saveConfigs(_configs);
  }

  /// Locks all apps belonging to a given category.
  Future<void> lockCategory(AppCategory category, {int? durationMinutes}) async {
    final now = _clock.monotonicNow;

    for (final def in ComprehensiveAppCatalog.getByCategory(category)) {
      final existing = _configs[def.id];
      final minutes = durationMinutes ?? existing?.allocatedTimerMinutes ?? 120;
      final targetEnd = now.add(Duration(minutes: minutes));

      final updated = (existing ?? AppLockConfig(appId: def.id, packageName: def.primaryPackage)).copyWith(
        mode: AppLockMode.independentTimer,
        allocatedTimerMinutes: minutes,
        lockStartTime: now,
        lockTargetEndTime: targetEnd,
        isCurrentlyLocked: true,
      );

      _configs[def.id] = updated;
      _quotaEngine.registerConfig(updated);

      _priorityQueue.insert(ScheduleTriggerEvent(
        eventId: 'timer_${def.id}',
        appId: def.id,
        packageName: def.primaryPackage,
        targetTimestamp: targetEnd,
        eventType: PriorityEventType.timerExpired,
      ));
    }

    notifyListeners();
    await _journal.saveConfigs(_configs);
    await _syncPlatformRules();
    _armTickerIfNeeded();
  }

  /// Adds a recurring weekly calendar schedule rule.
  Future<void> addRecurringSchedule(RecurringScheduleRule rule) async {
    _recurringEngine.addRule(rule);
    final saved = await _journal.loadSchedules();
    saved[rule.id] = rule;
    await _journal.saveSchedules(saved);

    _reconcileState(_clock.monotonicNow);
    notifyListeners();
    await _syncPlatformRules();
  }

  /// Removes a recurring schedule rule.
  Future<void> removeRecurringSchedule(String ruleId) async {
    _recurringEngine.removeRule(ruleId);
    final saved = await _journal.loadSchedules();
    saved.remove(ruleId);
    await _journal.saveSchedules(saved);

    _reconcileState(_clock.monotonicNow);
    notifyListeners();
    await _syncPlatformRules();
  }

  /// Records active foreground usage reported by Android native UsageStats service.
  void recordForegroundUsage(String appId, int secondsUsed) {
    final now = _clock.monotonicNow;
    final depleted = _quotaEngine.recordForegroundUsage(appId, secondsUsed, now);
    if (depleted) {
      _configs[appId] = _quotaEngine.configs[appId]!;
      notifyListeners();
      _syncPlatformRules();
      _journal.saveConfigs(_configs);
    }
  }

  void _armTickerIfNeeded() {
    if (!enableAutomaticTicker) return;
    if (_ticker != null && _ticker!.isActive) return;

    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      _tick(_clock.monotonicNow);
    });
  }

  void _tick(DateTime now) {
    // 1. Check Anti-Tamper clock
    _clock.verifyAgainstWallClock(DateTime.now());

    // 2. Check Priority Queue for expired timers
    final expiredEvents = _priorityQueue.popExpired(now);
    bool stateChanged = false;

    for (final event in expiredEvents) {
      if (event.eventType == PriorityEventType.timerExpired) {
        final config = _configs[event.appId];
        if (config != null && config.mode == AppLockMode.independentTimer) {
          _configs[event.appId] = config.copyWith(
            isCurrentlyLocked: false,
            lockTargetEndTime: null,
            mode: AppLockMode.unlocked,
          );
          stateChanged = true;
        }
      }
    }

    // 3. Check Recurring schedule rules
    final scheduledLockedAppIds = _recurringEngine.evaluateActiveAppIds(now);
    for (final appId in scheduledLockedAppIds) {
      final config = _configs[appId];
      if (config != null && !config.isCurrentlyLocked) {
        _configs[appId] = config.copyWith(
          isCurrentlyLocked: true,
          mode: AppLockMode.recurringSchedule,
        );
        stateChanged = true;
      }
    }

    // 4. Midnight Quota Rollover
    final rolledOver = _quotaEngine.checkMidnightRollover(now);
    if (rolledOver) {
      _configs.forEach((appId, cfg) {
        if (cfg.mode == AppLockMode.dailyQuota) {
          _configs[appId] = _quotaEngine.configs[appId]!;
          stateChanged = true;
        }
      });
    }

    if (stateChanged) {
      notifyListeners();
      _syncPlatformRules();
      _journal.saveConfigs(_configs);
    }

    if (activeLocks.isEmpty) {
      _ticker?.cancel();
      _ticker = null;
    }
  }

  void _reconcileState(DateTime now) {
    _tick(now);
  }

  Future<void> _syncPlatformRules() async {
    final activePackages = <String>[];
    final activeDomains = <String>[];

    for (final lock in activeLocks) {
      activePackages.add(lock.packageName);
      final def = _catalog[lock.appId];
      if (def != null) {
        activePackages.addAll(def.secondaryPackages);
        activeDomains.addAll(def.networkDomains);
        activeDomains.addAll(def.cdnDomains);
      }
    }

    try {
      await FocusDnsBlockerManager.setBlockedPackages(activePackages);
      await FocusDnsVpnManager.updateDnsRules(
        blockedDomains: activeDomains,
        allowedDomains: const [],
      );
    } catch (e) {
      debugPrint('[PerAppCoordinator] Error syncing platform rules: $e');
    }
  }

  /// For automated testing: simulate monotonic clock progression.
  @visibleForTesting
  void tickForTesting(DateTime simulatedTime) {
    _tick(simulatedTime);
  }

  @override
  void dispose() {
    _isDisposed = true;
    _ticker?.cancel();
    super.dispose();
  }
}
