import 'package:flutter/material.dart';

/// Represents an application audited from the device with installer provenance & distraction metrics.
class AuditedApp {
  final String packageName;
  final String appName;
  final String? installerPackage;
  final bool isPlayStoreVerified;
  final bool isSystemApp;
  final String category; // 'social', 'video', 'gaming', 'communication', 'shopping', 'other'
  final int distractionScore; // 0 - 100
  final bool isDistraction;
  final int installTimeMs;
  final int lastUpdateTimeMs;
  final int targetSdkVersion;
  final String versionName;
  final List<String> associatedDomains;

  const AuditedApp({
    required this.packageName,
    required this.appName,
    this.installerPackage,
    required this.isPlayStoreVerified,
    required this.isSystemApp,
    required this.category,
    required this.distractionScore,
    required this.isDistraction,
    required this.installTimeMs,
    required this.lastUpdateTimeMs,
    required this.targetSdkVersion,
    required this.versionName,
    required this.associatedDomains,
  });

  factory AuditedApp.fromMap(Map<dynamic, dynamic> map) {
    return AuditedApp(
      packageName: map['packageName']?.toString() ?? '',
      appName: map['appName']?.toString() ?? '',
      installerPackage: map['installerPackage']?.toString(),
      isPlayStoreVerified: map['isPlayStoreVerified'] == true,
      isSystemApp: map['isSystemApp'] == true,
      category: map['category']?.toString() ?? 'other',
      distractionScore: (map['distractionScore'] as num?)?.toInt() ?? 0,
      isDistraction: map['isDistraction'] == true,
      installTimeMs: (map['installTimeMs'] as num?)?.toInt() ?? 0,
      lastUpdateTimeMs: (map['lastUpdateTimeMs'] as num?)?.toInt() ?? 0,
      targetSdkVersion: (map['targetSdkVersion'] as num?)?.toInt() ?? 0,
      versionName: map['versionName']?.toString() ?? '1.0',
      associatedDomains: (map['associatedDomains'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          [],
    );
  }

  Color get categoryColor {
    switch (category) {
      case 'social':
        return const Color(0xFFE1306C);
      case 'video':
        return const Color(0xFFFF0000);
      case 'gaming':
        return const Color(0xFF7C3AED);
      case 'communication':
        return const Color(0xFF25D366);
      case 'shopping':
        return const Color(0xFFEA580C);
      default:
        return const Color(0xFF6B7280);
    }
  }

  String get categoryDisplayName {
    switch (category) {
      case 'social':
        return 'Social Media';
      case 'video':
        return 'Streaming & Video';
      case 'gaming':
        return 'Gaming';
      case 'communication':
        return 'Messaging & Chat';
      case 'shopping':
        return 'Shopping';
      default:
        return 'General App';
    }
  }
}

/// Aggregated report from device distraction audit.
class DeviceAuditReport {
  final int totalScanned;
  final int playStoreVerifiedCount;
  final int distractionCount;
  final String auditGrade; // 'A+', 'A', 'B', 'C', 'D', 'F'
  final DateTime timestamp;
  final List<AuditedApp> apps;

  const DeviceAuditReport({
    required this.totalScanned,
    required this.playStoreVerifiedCount,
    required this.distractionCount,
    required this.auditGrade,
    required this.timestamp,
    required this.apps,
  });

  factory DeviceAuditReport.fromMap(Map<dynamic, dynamic> map) {
    final rawApps = (map['apps'] as List<dynamic>?) ?? [];
    return DeviceAuditReport(
      totalScanned: (map['totalScanned'] as num?)?.toInt() ?? 0,
      playStoreVerifiedCount: (map['playStoreVerifiedCount'] as num?)?.toInt() ?? 0,
      distractionCount: (map['distractionCount'] as num?)?.toInt() ?? 0,
      auditGrade: map['auditGrade']?.toString() ?? 'A',
      timestamp: DateTime.fromMillisecondsSinceEpoch(
          (map['timestamp'] as num?)?.toInt() ?? DateTime.now().millisecondsSinceEpoch),
      apps: rawApps.map((a) => AuditedApp.fromMap(a as Map<dynamic, dynamic>)).toList(),
    );
  }

  /// List of Play Store verified applications that are distracting
  List<AuditedApp> get playStoreDistractions =>
      apps.where((a) => a.isPlayStoreVerified && a.isDistraction).toList();

  /// All Play Store verified user applications
  List<AuditedApp> get playStoreUserApps =>
      apps.where((a) => a.isPlayStoreVerified).toList();
}
