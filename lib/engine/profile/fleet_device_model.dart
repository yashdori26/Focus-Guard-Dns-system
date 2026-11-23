import 'package:flutter/foundation.dart';

/// Supported platform categories in the device fleet.
enum FleetPlatformType {
  android,
  chromeExtension,
  windows,
  macos,
  linux,
}

/// Representation of an active node within the user's multi-device fleet.
@immutable
class FleetDeviceModel {
  final String deviceId;
  final String deviceName;
  final FleetPlatformType platform;
  final String clientVersion;
  final DateTime lastHeartbeat;
  final bool isOnline;
  final String activeMode; // 'focus', 'break', 'unrestricted'
  final bool isStrictLockActive;
  final DateTime? strictLockedUntil;
  final int sessionRemainingSeconds;
  final int distractionsBlockedToday;
  final int minutesReclaimedToday;
  final int? batteryPercentage;
  final bool? isCharging;
  final int pingLatencyMs;

  const FleetDeviceModel({
    required this.deviceId,
    required this.deviceName,
    required this.platform,
    required this.clientVersion,
    required this.lastHeartbeat,
    required this.isOnline,
    required this.activeMode,
    required this.isStrictLockActive,
    this.strictLockedUntil,
    required this.sessionRemainingSeconds,
    required this.distractionsBlockedToday,
    required this.minutesReclaimedToday,
    this.batteryPercentage,
    this.isCharging,
    this.pingLatencyMs = 24,
  });

  /// Visual icon for the platform.
  String get platformIcon {
    switch (platform) {
      case FleetPlatformType.android:
        return '🤖';
      case FleetPlatformType.chromeExtension:
        return '🌐';
      case FleetPlatformType.windows:
        return '🪟';
      case FleetPlatformType.macos:
        return '🍎';
      case FleetPlatformType.linux:
        return '🐧';
    }
  }

  /// Evaluates whether the device has missed heartbeat intervals (> 60s).
  bool get isHeartbeatStale {
    return DateTime.now().difference(lastHeartbeat).inSeconds > 60;
  }

  /// Formatted remaining countdown MM:SS.
  String get formattedRemainingTime {
    final mins = sessionRemainingSeconds ~/ 60;
    final secs = sessionRemainingSeconds % 60;
    return '${mins.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}';
  }

  FleetDeviceModel copyWith({
    String? deviceId,
    String? deviceName,
    FleetPlatformType? platform,
    String? clientVersion,
    DateTime? lastHeartbeat,
    bool? isOnline,
    String? activeMode,
    bool? isStrictLockActive,
    DateTime? strictLockedUntil,
    int? sessionRemainingSeconds,
    int? distractionsBlockedToday,
    int? minutesReclaimedToday,
    int? batteryPercentage,
    bool? isCharging,
    int? pingLatencyMs,
  }) {
    return FleetDeviceModel(
      deviceId: deviceId ?? this.deviceId,
      deviceName: deviceName ?? this.deviceName,
      platform: platform ?? this.platform,
      clientVersion: clientVersion ?? this.clientVersion,
      lastHeartbeat: lastHeartbeat ?? this.lastHeartbeat,
      isOnline: isOnline ?? this.isOnline,
      activeMode: activeMode ?? this.activeMode,
      isStrictLockActive: isStrictLockActive ?? this.isStrictLockActive,
      strictLockedUntil: strictLockedUntil ?? this.strictLockedUntil,
      sessionRemainingSeconds: sessionRemainingSeconds ?? this.sessionRemainingSeconds,
      distractionsBlockedToday: distractionsBlockedToday ?? this.distractionsBlockedToday,
      minutesReclaimedToday: minutesReclaimedToday ?? this.minutesReclaimedToday,
      batteryPercentage: batteryPercentage ?? this.batteryPercentage,
      isCharging: isCharging ?? this.isCharging,
      pingLatencyMs: pingLatencyMs ?? this.pingLatencyMs,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'deviceId': deviceId,
      'deviceName': deviceName,
      'platform': platform.name,
      'clientVersion': clientVersion,
      'lastHeartbeat': lastHeartbeat.toIso8601String(),
      'isOnline': isOnline,
      'activeMode': activeMode,
      'isStrictLockActive': isStrictLockActive,
      'strictLockedUntil': strictLockedUntil?.toIso8601String(),
      'sessionRemainingSeconds': sessionRemainingSeconds,
      'distractionsBlockedToday': distractionsBlockedToday,
      'minutesReclaimedToday': minutesReclaimedToday,
      'batteryPercentage': batteryPercentage,
      'isCharging': isCharging,
      'pingLatencyMs': pingLatencyMs,
    };
  }

  factory FleetDeviceModel.fromJson(Map<String, dynamic> json) {
    return FleetDeviceModel(
      deviceId: json['deviceId'] as String? ?? 'dev_unknown',
      deviceName: json['deviceName'] as String? ?? 'Unnamed Device',
      platform: FleetPlatformType.values.firstWhere(
        (e) => e.name == json['platform'],
        orElse: () => FleetPlatformType.android,
      ),
      clientVersion: json['clientVersion'] as String? ?? '2.0.0',
      lastHeartbeat: json['lastHeartbeat'] != null
          ? DateTime.tryParse(json['lastHeartbeat'] as String) ?? DateTime.now()
          : DateTime.now(),
      isOnline: json['isOnline'] as bool? ?? false,
      activeMode: json['activeMode'] as String? ?? 'unrestricted',
      isStrictLockActive: json['isStrictLockActive'] as bool? ?? false,
      strictLockedUntil: json['strictLockedUntil'] != null
          ? DateTime.tryParse(json['strictLockedUntil'] as String)
          : null,
      sessionRemainingSeconds: json['sessionRemainingSeconds'] as int? ?? 0,
      distractionsBlockedToday: json['distractionsBlockedToday'] as int? ?? 0,
      minutesReclaimedToday: json['minutesReclaimedToday'] as int? ?? 0,
      batteryPercentage: json['batteryPercentage'] as int?,
      isCharging: json['isCharging'] as bool?,
      pingLatencyMs: json['pingLatencyMs'] as int? ?? 25,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is FleetDeviceModel &&
          runtimeType == other.runtimeType &&
          deviceId == other.deviceId &&
          platform == other.platform &&
          isOnline == other.isOnline &&
          isStrictLockActive == other.isStrictLockActive &&
          sessionRemainingSeconds == other.sessionRemainingSeconds;

  @override
  int get hashCode => Object.hash(
        deviceId,
        platform,
        isOnline,
        isStrictLockActive,
        sessionRemainingSeconds,
      );
}
