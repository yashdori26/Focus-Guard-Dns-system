import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'routine_state_machine.dart';

/// An individual journal log entry representing an event in the routine lifecycle.
@immutable
class RoutineJournalRecord {
  final String recordId;
  final DateTime timestamp;
  final RoutinePhaseState phase;
  final int cycleIndex;
  final int focusMinutesRecorded;
  final int breakMinutesRecorded;
  final bool wasInterventionKill;
  final String integrityHash;

  const RoutineJournalRecord({
    required this.recordId,
    required this.timestamp,
    required this.phase,
    required this.cycleIndex,
    required this.focusMinutesRecorded,
    required this.breakMinutesRecorded,
    required this.wasInterventionKill,
    required this.integrityHash,
  });

  Map<String, dynamic> toJson() => {
    'recordId': recordId,
    'timestamp': timestamp.toIso8601String(),
    'phase': phase.name,
    'cycleIndex': cycleIndex,
    'focusMinutesRecorded': focusMinutesRecorded,
    'breakMinutesRecorded': breakMinutesRecorded,
    'wasInterventionKill': wasInterventionKill,
    'integrityHash': integrityHash,
  };

  factory RoutineJournalRecord.fromJson(Map<String, dynamic> json) {
    return RoutineJournalRecord(
      recordId: json['recordId'] as String,
      timestamp: DateTime.parse(json['timestamp'] as String),
      phase: RoutinePhaseState.values.byName(json['phase'] as String),
      cycleIndex: (json['cycleIndex'] as num).toInt(),
      focusMinutesRecorded: (json['focusMinutesRecorded'] as num).toInt(),
      breakMinutesRecorded: (json['breakMinutesRecorded'] as num).toInt(),
      wasInterventionKill: json['wasInterventionKill'] as bool? ?? false,
      integrityHash: json['integrityHash'] as String? ?? '',
    );
  }

  static String computeHash({
    required String recordId,
    required DateTime timestamp,
    required RoutinePhaseState phase,
    required int cycleIndex,
    required int focusMinutes,
    required int breakMinutes,
  }) {
    final payload = '$recordId|${timestamp.toIso8601String()}|${phase.name}|$cycleIndex|$focusMinutes|$breakMinutes|FOCUS_DNS_SECURE_SALT';
    return sha256.convert(utf8.encode(payload)).toString();
  }
}

/// Cryptographically verified local journal repository storing routine events and crash-recovery state.
class RoutinePersistenceJournal {
  static const String _prefKeyRecords = 'focus_dns_routine_journal_records';
  static const String _prefKeyActiveSnapshot = 'focus_dns_routine_active_snapshot';

  final SharedPreferences? _prefs;

  RoutinePersistenceJournal([this._prefs]);

  Future<SharedPreferences> _getPrefs() async {
    return _prefs ?? await SharedPreferences.getInstance();
  }

  /// Appends a new verified record to the journal.
  Future<RoutineJournalRecord> appendRecord({
    required RoutinePhaseState phase,
    required int cycleIndex,
    required int focusMinutes,
    required int breakMinutes,
    bool wasInterventionKill = false,
  }) async {
    final prefs = await _getPrefs();
    final now = DateTime.now();
    final recordId = 'REC_${now.millisecondsSinceEpoch}_${cycleIndex}';

    final hash = RoutineJournalRecord.computeHash(
      recordId: recordId,
      timestamp: now,
      phase: phase,
      cycleIndex: cycleIndex,
      focusMinutes: focusMinutes,
      breakMinutes: breakMinutes,
    );

    final record = RoutineJournalRecord(
      recordId: recordId,
      timestamp: now,
      phase: phase,
      cycleIndex: cycleIndex,
      focusMinutesRecorded: focusMinutes,
      breakMinutesRecorded: breakMinutes,
      wasInterventionKill: wasInterventionKill,
      integrityHash: hash,
    );

    final rawList = prefs.getStringList(_prefKeyRecords) ?? [];
    rawList.add(jsonEncode(record.toJson()));

    // Keep up to 1,000 historical records
    if (rawList.length > 1000) {
      rawList.removeRange(0, rawList.length - 1000);
    }

    await prefs.setStringList(_prefKeyRecords, rawList);
    return record;
  }

  /// Saves the active in-flight routine snapshot for crash-recovery.
  Future<void> saveActiveSnapshot(RoutineSnapshot snapshot) async {
    final prefs = await _getPrefs();
    if (!snapshot.isRunning) {
      await prefs.remove(_prefKeyActiveSnapshot);
      return;
    }

    final data = {
      'phase': snapshot.phase.name,
      'config': snapshot.config.toJson(),
      'currentCycle': snapshot.currentCycle,
      'remainingSeconds': snapshot.remainingSecondsInPhase,
      'totalDuration': snapshot.totalPhaseDurationSeconds,
      'cumulativeFocus': snapshot.cumulativeFocusSeconds,
      'cumulativeBreak': snapshot.cumulativeBreakSeconds,
      'targetEndTime': snapshot.phaseTargetEndTime?.toIso8601String(),
    };

    await prefs.setString(_prefKeyActiveSnapshot, jsonEncode(data));
  }

  /// Retrieves any pending in-flight snapshot that was interrupted by an app crash or device reboot.
  Future<RoutineSnapshot?> restoreActiveSnapshot() async {
    final prefs = await _getPrefs();
    final raw = prefs.getString(_prefKeyActiveSnapshot);
    if (raw == null) return null;

    try {
      final map = jsonDecode(raw) as Map<String, dynamic>;
      final targetEndStr = map['targetEndTime'] as String?;
      final targetEnd = targetEndStr != null ? DateTime.parse(targetEndStr) : null;

      // Check if target end has already passed while device was asleep
      if (targetEnd != null && DateTime.now().isAfter(targetEnd)) {
        await prefs.remove(_prefKeyActiveSnapshot);
        return null;
      }

      final phase = RoutinePhaseState.values.byName(map['phase'] as String);
      final config = RoutineScheduleConfig.fromJson(map['config'] as Map<String, dynamic>);
      final cycle = (map['currentCycle'] as num).toInt();
      final remaining = (map['remainingSeconds'] as num).toInt();

      return RoutineSnapshot(
        phase: phase,
        config: config,
        currentCycle: cycle,
        remainingSecondsInPhase: remaining,
        phaseTargetEndTime: targetEnd,
        statusMessage: 'Restored from persistent journal',
      );
    } catch (e) {
      debugPrint('[RoutineJournal] Error restoring snapshot: $e');
      await prefs.remove(_prefKeyActiveSnapshot);
      return null;
    }
  }

  /// Clears in-flight crash snapshot on normal routine finish.
  Future<void> clearActiveSnapshot() async {
    final prefs = await _getPrefs();
    await prefs.remove(_prefKeyActiveSnapshot);
  }

  /// Fetches all historical records and verifies integrity hashes.
  Future<List<RoutineJournalRecord>> getAllVerifiedRecords() async {
    final prefs = await _getPrefs();
    final rawList = prefs.getStringList(_prefKeyRecords) ?? [];
    final verified = <RoutineJournalRecord>[];

    for (final item in rawList) {
      try {
        final record = RoutineJournalRecord.fromJson(jsonDecode(item) as Map<String, dynamic>);
        final expectedHash = RoutineJournalRecord.computeHash(
          recordId: record.recordId,
          timestamp: record.timestamp,
          phase: record.phase,
          cycleIndex: record.cycleIndex,
          focusMinutes: record.focusMinutesRecorded,
          breakMinutes: record.breakMinutesRecorded,
        );

        if (expectedHash == record.integrityHash) {
          verified.add(record);
        } else {
          debugPrint('[RoutineJournal] Tamper detected on record ${record.recordId}! Skipping.');
        }
      } catch (e) {
        debugPrint('[RoutineJournal] Parse error: $e');
      }
    }

    return verified;
  }
}
