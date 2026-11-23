// FocusDNS Enterprise Models - Multi-Tenancy, Big Data Columnar Analytics, Fleet Push & SIEM

import 'package:flutter/foundation.dart';

enum RoleTier {
  superAdmin,
  orgAdmin,
  teamLead,
  teacherParent,
  complianceAuditor;

  static RoleTier fromString(String val) {
    switch (val.toUpperCase()) {
      case 'SUPER_ADMIN':
        return RoleTier.superAdmin;
      case 'ORG_ADMIN':
        return RoleTier.orgAdmin;
      case 'TEAM_LEAD':
        return RoleTier.teamLead;
      case 'TEACHER_PARENT':
        return RoleTier.teacherParent;
      case 'COMPLIANCE_AUDITOR':
        return RoleTier.complianceAuditor;
      default:
        return RoleTier.teamLead;
    }
  }

  String get label {
    switch (this) {
      case RoleTier.superAdmin:
        return 'Super Admin';
      case RoleTier.orgAdmin:
        return 'Organization Admin';
      case RoleTier.teamLead:
        return 'Team Lead';
      case RoleTier.teacherParent:
        return 'Teacher / Parent';
      case RoleTier.complianceAuditor:
        return 'Compliance Auditor';
    }
  }

  String get wireName {
    switch (this) {
      case RoleTier.superAdmin:
        return 'SUPER_ADMIN';
      case RoleTier.orgAdmin:
        return 'ORG_ADMIN';
      case RoleTier.teamLead:
        return 'TEAM_LEAD';
      case RoleTier.teacherParent:
        return 'TEACHER_PARENT';
      case RoleTier.complianceAuditor:
        return 'COMPLIANCE_AUDITOR';
    }
  }
}

@immutable
class TenantQuotaModel {
  final int maxDevices;
  final int maxQps;
  final int retentionDays;
  final bool allowSiem;
  final bool allowCustomDga;

  const TenantQuotaModel({
    required this.maxDevices,
    required this.maxQps,
    required this.retentionDays,
    required this.allowSiem,
    required this.allowCustomDga,
  });

  factory TenantQuotaModel.fromJson(Map<String, dynamic> json) {
    return TenantQuotaModel(
      maxDevices: json['max_devices'] as int? ?? 500,
      maxQps: json['max_qps'] as int? ?? 5000,
      retentionDays: json['retention_days'] as int? ?? 90,
      allowSiem: json['allow_siem'] as bool? ?? true,
      allowCustomDga: json['allow_custom_dga'] as bool? ?? true,
    );
  }

  Map<String, dynamic> toJson() => {
    'max_devices': maxDevices,
    'max_qps': maxQps,
    'retention_days': retentionDays,
    'allow_siem': allowSiem,
    'allow_custom_dga': allowCustomDga,
  };
}

@immutable
class OrganizationModel {
  final String orgId;
  final String name;
  final String domain;
  final String planTier;
  final bool isActive;
  final double createdAt;
  final TenantQuotaModel quota;

  const OrganizationModel({
    required this.orgId,
    required this.name,
    required this.domain,
    required this.planTier,
    required this.isActive,
    required this.createdAt,
    required this.quota,
  });

  factory OrganizationModel.fromJson(Map<String, dynamic> json) {
    return OrganizationModel(
      orgId: json['org_id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      domain: json['domain'] as String? ?? '',
      planTier: json['plan_tier'] as String? ?? 'ENTERPRISE',
      isActive: json['is_active'] as bool? ?? true,
      createdAt: (json['created_at'] as num?)?.toDouble() ?? 0.0,
      quota: json['quota'] != null
          ? TenantQuotaModel.fromJson(Map<String, dynamic>.from(json['quota'] as Map))
          : const TenantQuotaModel(maxDevices: 500, maxQps: 5000, retentionDays: 90, allowSiem: true, allowCustomDga: true),
    );
  }

  Map<String, dynamic> toJson() => {
    'org_id': orgId,
    'name': name,
    'domain': domain,
    'plan_tier': planTier,
    'is_active': isActive,
    'created_at': createdAt,
    'quota': quota.toJson(),
  };
}

@immutable
class TenantUnitModel {
  final String unitId;
  final String orgId;
  final String name;
  final String unitType;
  final String? parentUnitId;
  final Map<String, dynamic> policyProfile;
  final bool isActive;

  const TenantUnitModel({
    required this.unitId,
    required this.orgId,
    required this.name,
    required this.unitType,
    this.parentUnitId,
    required this.policyProfile,
    required this.isActive,
  });

  factory TenantUnitModel.fromJson(Map<String, dynamic> json) {
    return TenantUnitModel(
      unitId: json['unit_id'] as String? ?? '',
      orgId: json['org_id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      unitType: json['unit_type'] as String? ?? 'DEPARTMENT',
      parentUnitId: json['parent_unit_id'] as String?,
      policyProfile: json['policy_profile'] != null
          ? Map<String, dynamic>.from(json['policy_profile'] as Map)
          : {},
      isActive: json['is_active'] as bool? ?? true,
    );
  }

  Map<String, dynamic> toJson() => {
    'unit_id': unitId,
    'org_id': orgId,
    'name': name,
    'unit_type': unitType,
    'parent_unit_id': parentUnitId,
    'policy_profile': policyProfile,
    'is_active': isActive,
  };
}

@immutable
class DeviceFleetModel {
  final String fleetId;
  final String unitId;
  final String orgId;
  final String name;
  final String platform;
  final String policyProfileId;
  final bool isLocked;
  final double? lockedUntil;
  final int remainingLockSeconds;
  final int deviceCount;

  const DeviceFleetModel({
    required this.fleetId,
    required this.unitId,
    required this.orgId,
    required this.name,
    required this.platform,
    required this.policyProfileId,
    required this.isLocked,
    this.lockedUntil,
    required this.remainingLockSeconds,
    required this.deviceCount,
  });

  factory DeviceFleetModel.fromJson(Map<String, dynamic> json) {
    return DeviceFleetModel(
      fleetId: json['fleet_id'] as String? ?? '',
      unitId: json['unit_id'] as String? ?? '',
      orgId: json['org_id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      platform: json['platform'] as String? ?? 'ALL',
      policyProfileId: json['policy_profile_id'] as String? ?? 'profile_strict',
      isLocked: json['is_locked'] as bool? ?? false,
      lockedUntil: (json['locked_until'] as num?)?.toDouble(),
      remainingLockSeconds: json['remaining_lock_seconds'] as int? ?? 0,
      deviceCount: json['device_count'] as int? ?? 0,
    );
  }

  Map<String, dynamic> toJson() => {
    'fleet_id': fleetId,
    'unit_id': unitId,
    'org_id': orgId,
    'name': name,
    'platform': platform,
    'policy_profile_id': policyProfileId,
    'is_locked': isLocked,
    'locked_until': lockedUntil,
    'remaining_lock_seconds': remainingLockSeconds,
    'device_count': deviceCount,
  };
}

@immutable
class TimeseriesPointModel {
  final int timestamp;
  final int totalQueries;
  final int blockedQueries;
  final int threatCount;
  final int allowedQueries;

  const TimeseriesPointModel({
    required this.timestamp,
    required this.totalQueries,
    required this.blockedQueries,
    required this.threatCount,
    required this.allowedQueries,
  });

  factory TimeseriesPointModel.fromJson(Map<String, dynamic> json) {
    return TimeseriesPointModel(
      timestamp: json['timestamp'] as int? ?? 0,
      totalQueries: json['total_queries'] as int? ?? 0,
      blockedQueries: json['blocked_queries'] as int? ?? 0,
      threatCount: json['threat_count'] as int? ?? 0,
      allowedQueries: json['allowed_queries'] as int? ?? 0,
    );
  }

  Map<String, dynamic> toJson() => {
    'timestamp': timestamp,
    'total_queries': totalQueries,
    'blocked_queries': blockedQueries,
    'threat_count': threatCount,
    'allowed_queries': allowedQueries,
  };
}

@immutable
class TopDomainStatModel {
  final String domain;
  final int queryCount;
  final String action;
  final String category;

  const TopDomainStatModel({
    required this.domain,
    required this.queryCount,
    required this.action,
    required this.category,
  });

  factory TopDomainStatModel.fromJson(Map<String, dynamic> json) {
    return TopDomainStatModel(
      domain: json['domain'] as String? ?? '',
      queryCount: json['query_count'] as int? ?? 0,
      action: json['action'] as String? ?? 'ALLOWED',
      category: json['category'] as String? ?? 'UNCATEGORIZED',
    );
  }

  Map<String, dynamic> toJson() => {
    'domain': domain,
    'query_count': queryCount,
    'action': action,
    'category': category,
  };
}

@immutable
class ThreatMatrixModel {
  final int totalThreats;
  final Map<String, int> breakdown;

  const ThreatMatrixModel({
    required this.totalThreats,
    required this.breakdown,
  });

  factory ThreatMatrixModel.fromJson(Map<String, dynamic> json) {
    final rawBreakdown = json['breakdown'] as Map? ?? {};
    final parsedMap = <String, int>{};
    for (final entry in rawBreakdown.entries) {
      parsedMap[entry.key.toString()] = (entry.value as num).toInt();
    }
    return ThreatMatrixModel(
      totalThreats: json['total_threats'] as int? ?? 0,
      breakdown: parsedMap,
    );
  }

  Map<String, dynamic> toJson() => {
    'total_threats': totalThreats,
    'breakdown': breakdown,
  };
}

@immutable
class LatencyQuantilesModel {
  final double p50;
  final double p90;
  final double p95;
  final double p99;
  final double avg;
  final int count;

  const LatencyQuantilesModel({
    required this.p50,
    required this.p90,
    required this.p95,
    required this.p99,
    required this.avg,
    required this.count,
  });

  factory LatencyQuantilesModel.fromJson(Map<String, dynamic> json) {
    return LatencyQuantilesModel(
      p50: (json['p50'] as num?)?.toDouble() ?? 0.0,
      p90: (json['p90'] as num?)?.toDouble() ?? 0.0,
      p95: (json['p95'] as num?)?.toDouble() ?? 0.0,
      p99: (json['p99'] as num?)?.toDouble() ?? 0.0,
      avg: (json['avg'] as num?)?.toDouble() ?? 0.0,
      count: json['count'] as int? ?? 0,
    );
  }

  Map<String, dynamic> toJson() => {
    'p50': p50,
    'p90': p90,
    'p95': p95,
    'p99': p99,
    'avg': avg,
    'count': count,
  };
}

@immutable
class RbacUserModel {
  final String userId;
  final String username;
  final String email;
  final RoleTier role;
  final String tenantId;
  final List<String> subTenantIds;
  final bool isActive;
  final double createdAt;

  const RbacUserModel({
    required this.userId,
    required this.username,
    required this.email,
    required this.role,
    required this.tenantId,
    required this.subTenantIds,
    required this.isActive,
    required this.createdAt,
  });

  factory RbacUserModel.fromJson(Map<String, dynamic> json) {
    return RbacUserModel(
      userId: json['user_id'] as String? ?? '',
      username: json['username'] as String? ?? '',
      email: json['email'] as String? ?? '',
      role: RoleTier.fromString(json['role'] as String? ?? 'TEAM_LEAD'),
      tenantId: json['tenant_id'] as String? ?? '',
      subTenantIds: (json['sub_tenant_ids'] as List?)?.map((e) => e.toString()).toList() ?? [],
      isActive: json['is_active'] as bool? ?? true,
      createdAt: (json['created_at'] as num?)?.toDouble() ?? 0.0,
    );
  }

  Map<String, dynamic> toJson() => {
    'user_id': userId,
    'username': username,
    'email': email,
    'role': role.wireName,
    'tenant_id': tenantId,
    'sub_tenant_ids': subTenantIds,
    'is_active': isActive,
    'created_at': createdAt,
  };
}

@immutable
class AuditEntryModel {
  final String entryId;
  final double timestamp;
  final String actorUserId;
  final String actorRole;
  final String tenantId;
  final String action;
  final String resource;
  final Map<String, dynamic> details;
  final String status;
  final String previousHash;
  final String entryHash;

  const AuditEntryModel({
    required this.entryId,
    required this.timestamp,
    required this.actorUserId,
    required this.actorRole,
    required this.tenantId,
    required this.action,
    required this.resource,
    required this.details,
    required this.status,
    required this.previousHash,
    required this.entryHash,
  });

  factory AuditEntryModel.fromJson(Map<String, dynamic> json) {
    return AuditEntryModel(
      entryId: json['entry_id'] as String? ?? '',
      timestamp: (json['timestamp'] as num?)?.toDouble() ?? 0.0,
      actorUserId: json['actor_user_id'] as String? ?? '',
      actorRole: json['actor_role'] as String? ?? '',
      tenantId: json['tenant_id'] as String? ?? '',
      action: json['action'] as String? ?? '',
      resource: json['resource'] as String? ?? '',
      details: json['details'] != null ? Map<String, dynamic>.from(json['details'] as Map) : {},
      status: json['status'] as String? ?? 'SUCCESS',
      previousHash: json['previous_hash'] as String? ?? '',
      entryHash: json['entry_hash'] as String? ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
    'entry_id': entryId,
    'timestamp': timestamp,
    'actor_user_id': actorUserId,
    'actor_role': actorRole,
    'tenant_id': tenantId,
    'action': action,
    'resource': resource,
    'details': details,
    'status': status,
    'previous_hash': previousHash,
    'entry_hash': entryHash,
  };
}

@immutable
class SiemConfigModel {
  final bool enabled;
  final String transport;
  final String host;
  final int port;
  final String apiToken;
  final String indexName;
  final int facility;
  final int minSeverity;

  const SiemConfigModel({
    required this.enabled,
    required this.transport,
    required this.host,
    required this.port,
    required this.apiToken,
    required this.indexName,
    required this.facility,
    required this.minSeverity,
  });

  factory SiemConfigModel.fromJson(Map<String, dynamic> json) {
    return SiemConfigModel(
      enabled: json['enabled'] as bool? ?? false,
      transport: json['transport'] as String? ?? 'UDP',
      host: json['host'] as String? ?? '127.0.0.1',
      port: json['port'] as int? ?? 514,
      apiToken: json['api_token'] as String? ?? '',
      indexName: json['index_name'] as String? ?? 'focusdns_security',
      facility: json['facility'] as int? ?? 16,
      minSeverity: json['min_severity'] as int? ?? 4,
    );
  }

  Map<String, dynamic> toJson() => {
    'enabled': enabled,
    'transport': transport,
    'host': host,
    'port': port,
    'api_token': apiToken,
    'index_name': indexName,
    'facility': facility,
    'min_severity': minSeverity,
  };
}

@immutable
class FleetDeviceConnectionModel {
  final String deviceId;
  final String orgId;
  final String unitId;
  final String fleetId;
  final String platform;
  final double connectedAt;
  final double lastHeartbeat;
  final double rttMs;
  final int pendingQueueSize;
  final bool isAlive;

  const FleetDeviceConnectionModel({
    required this.deviceId,
    required this.orgId,
    required this.unitId,
    required this.fleetId,
    required this.platform,
    required this.connectedAt,
    required this.lastHeartbeat,
    required this.rttMs,
    required this.pendingQueueSize,
    required this.isAlive,
  });

  factory FleetDeviceConnectionModel.fromJson(Map<String, dynamic> json) {
    return FleetDeviceConnectionModel(
      deviceId: json['device_id'] as String? ?? '',
      orgId: json['org_id'] as String? ?? '',
      unitId: json['unit_id'] as String? ?? '',
      fleetId: json['fleet_id'] as String? ?? '',
      platform: json['platform'] as String? ?? 'ALL',
      connectedAt: (json['connected_at'] as num?)?.toDouble() ?? 0.0,
      lastHeartbeat: (json['last_heartbeat'] as num?)?.toDouble() ?? 0.0,
      rttMs: (json['rtt_ms'] as num?)?.toDouble() ?? 0.0,
      pendingQueueSize: json['pending_queue_size'] as int? ?? 0,
      isAlive: json['is_alive'] as bool? ?? true,
    );
  }

  Map<String, dynamic> toJson() => {
    'device_id': deviceId,
    'org_id': orgId,
    'unit_id': unitId,
    'fleet_id': fleetId,
    'platform': platform,
    'connected_at': connectedAt,
    'last_heartbeat': lastHeartbeat,
    'rtt_ms': rttMs,
    'pending_queue_size': pendingQueueSize,
    'is_alive': isAlive,
  };
}

enum ClassroomFocusMode {
  normalProtection,
  restrictedResearch,
  strictExamMode;

  static ClassroomFocusMode fromString(String val) {
    switch (val.toUpperCase()) {
      case 'RESTRICTED_RESEARCH':
        return ClassroomFocusMode.restrictedResearch;
      case 'STRICT_EXAM_MODE':
        return ClassroomFocusMode.strictExamMode;
      default:
        return ClassroomFocusMode.normalProtection;
    }
  }

  String get label {
    switch (this) {
      case ClassroomFocusMode.normalProtection:
        return 'Standard Protection';
      case ClassroomFocusMode.restrictedResearch:
        return 'Restricted Research';
      case ClassroomFocusMode.strictExamMode:
        return 'Strict Exam Lockdown';
    }
  }

  String get displayName => label;

  String get wireName {
    switch (this) {
      case ClassroomFocusMode.normalProtection:
        return 'NORMAL_PROTECTION';
      case ClassroomFocusMode.restrictedResearch:
        return 'RESTRICTED_RESEARCH';
      case ClassroomFocusMode.strictExamMode:
        return 'STRICT_EXAM_MODE';
    }
  }
}

@immutable
class StudentDeviceModel {
  final String deviceId;
  final String studentName;
  final String studentId;
  final String clientIp;
  final double lastQueryTime;
  final String lastQueriedDomain;
  final int distractionCount;
  final bool isLocked;
  final bool handRaised;

  const StudentDeviceModel({
    required this.deviceId,
    required this.studentName,
    required this.studentId,
    required this.clientIp,
    required this.lastQueryTime,
    required this.lastQueriedDomain,
    required this.distractionCount,
    required this.isLocked,
    required this.handRaised,
  });

  factory StudentDeviceModel.fromJson(Map<String, dynamic> json) {
    return StudentDeviceModel(
      deviceId: json['device_id'] as String? ?? '',
      studentName: json['student_name'] as String? ?? '',
      studentId: json['student_id'] as String? ?? '',
      clientIp: json['client_ip'] as String? ?? '127.0.0.1',
      lastQueryTime: (json['last_query_time'] as num?)?.toDouble() ?? 0.0,
      lastQueriedDomain: json['last_queried_domain'] as String? ?? '',
      distractionCount: json['distraction_count'] as int? ?? 0,
      isLocked: json['is_locked'] as bool? ?? false,
      handRaised: json['hand_raised'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() => {
    'device_id': deviceId,
    'student_name': studentName,
    'student_id': studentId,
    'client_ip': clientIp,
    'last_query_time': lastQueryTime,
    'last_queried_domain': lastQueriedDomain,
    'distraction_count': distractionCount,
    'is_locked': isLocked,
    'hand_raised': handRaised,
  };
}

@immutable
class ClassroomSessionModel {
  final String sessionId;
  final String orgId;
  final String unitId;
  final String fleetId;
  final String classroomName;
  final String teacherUserId;
  final ClassroomFocusMode mode;
  final int durationSeconds;
  final int remainingSeconds;
  final bool isActive;
  final int studentCount;
  final List<StudentDeviceModel> students;
  final int distractionAlertCount;
  final List<String> allowedExamDomains;

  const ClassroomSessionModel({
    required this.sessionId,
    required this.orgId,
    required this.unitId,
    required this.fleetId,
    required this.classroomName,
    required this.teacherUserId,
    required this.mode,
    required this.durationSeconds,
    required this.remainingSeconds,
    required this.isActive,
    required this.studentCount,
    required this.students,
    required this.distractionAlertCount,
    required this.allowedExamDomains,
  });

  factory ClassroomSessionModel.fromJson(Map<String, dynamic> json) {
    final rawStudents = json['students'] as List? ?? [];
    return ClassroomSessionModel(
      sessionId: json['session_id'] as String? ?? '',
      orgId: json['org_id'] as String? ?? '',
      unitId: json['unit_id'] as String? ?? '',
      fleetId: json['fleet_id'] as String? ?? '',
      classroomName: json['classroom_name'] as String? ?? '',
      teacherUserId: json['teacher_user_id'] as String? ?? '',
      mode: ClassroomFocusMode.fromString(json['mode'] as String? ?? 'NORMAL_PROTECTION'),
      durationSeconds: json['duration_seconds'] as int? ?? 2700,
      remainingSeconds: json['remaining_seconds'] as int? ?? 0,
      isActive: json['is_active'] as bool? ?? true,
      studentCount: json['student_count'] as int? ?? rawStudents.length,
      students: rawStudents.map((s) => StudentDeviceModel.fromJson(Map<String, dynamic>.from(s as Map))).toList(),
      distractionAlertCount: json['distraction_alert_count'] as int? ?? 0,
      allowedExamDomains: (json['allowed_exam_domains'] as List?)?.map((e) => e.toString()).toList() ?? [],
    );
  }

  Map<String, dynamic> toJson() => {
    'session_id': sessionId,
    'org_id': orgId,
    'unit_id': unitId,
    'fleet_id': fleetId,
    'classroom_name': classroomName,
    'teacher_user_id': teacherUserId,
    'mode': mode.wireName,
    'duration_seconds': durationSeconds,
    'remaining_seconds': remainingSeconds,
    'is_active': isActive,
    'student_count': studentCount,
    'students': students.map((s) => s.toJson()).toList(),
    'distraction_alert_count': distractionAlertCount,
    'allowed_exam_domains': allowedExamDomains,
  };
}

@immutable
class SoarIncidentModel {
  final String incidentId;
  final double timestamp;
  final String tenantId;
  final String deviceId;
  final String triggerType;
  final String domain;
  final double riskScore;
  final List<String> actionsExecuted;
  final int snapshotRecords;
  final String status;

  const SoarIncidentModel({
    required this.incidentId,
    required this.timestamp,
    required this.tenantId,
    required this.deviceId,
    required this.triggerType,
    required this.domain,
    required this.riskScore,
    required this.actionsExecuted,
    required this.snapshotRecords,
    required this.status,
  });

  factory SoarIncidentModel.fromJson(Map<String, dynamic> json) {
    return SoarIncidentModel(
      incidentId: json['incident_id'] as String? ?? '',
      timestamp: (json['timestamp'] as num?)?.toDouble() ?? 0.0,
      tenantId: json['tenant_id'] as String? ?? '',
      deviceId: json['device_id'] as String? ?? '',
      triggerType: json['trigger_type'] as String? ?? '',
      domain: json['domain'] as String? ?? '',
      riskScore: (json['risk_score'] as num?)?.toDouble() ?? 0.0,
      actionsExecuted: (json['actions_executed'] as List?)?.map((e) => e.toString()).toList() ?? [],
      snapshotRecords: json['snapshot_records'] as int? ?? 0,
      status: json['status'] as String? ?? 'OPEN',
    );
  }

  Map<String, dynamic> toJson() => {
    'incident_id': incidentId,
    'timestamp': timestamp,
    'tenant_id': tenantId,
    'device_id': deviceId,
    'trigger_type': triggerType,
    'domain': domain,
    'risk_score': riskScore,
    'actions_executed': actionsExecuted,
    'snapshot_records': snapshotRecords,
    'status': status,
  };
}

@immutable
class ScimProvisioningLogModel {
  final double timestamp;
  final String action;
  final String resourceId;
  final String identifier;
  final String details;

  const ScimProvisioningLogModel({
    required this.timestamp,
    required this.action,
    required this.resourceId,
    required this.identifier,
    required this.details,
  });

  factory ScimProvisioningLogModel.fromJson(Map<String, dynamic> json) {
    return ScimProvisioningLogModel(
      timestamp: (json['timestamp'] as num?)?.toDouble() ?? 0.0,
      action: json['action'] as String? ?? '',
      resourceId: json['resource_id'] as String? ?? '',
      identifier: json['identifier'] as String? ?? '',
      details: json['details'] as String? ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
    'timestamp': timestamp,
    'action': action,
    'resource_id': resourceId,
    'identifier': identifier,
    'details': details,
  };
}

@immutable
class UsageInvoiceModel {
  final String invoiceId;
  final String orgId;
  final String orgName;
  final String planTier;
  final String billingCycle;
  final double generatedAt;
  final int totalQueries;
  final double peakQps;
  final int activeDevices;
  final double totalAmountUsd;
  final String signatureSha256;

  const UsageInvoiceModel({
    required this.invoiceId,
    required this.orgId,
    required this.orgName,
    required this.planTier,
    required this.billingCycle,
    required this.generatedAt,
    required this.totalQueries,
    required this.peakQps,
    required this.activeDevices,
    required this.totalAmountUsd,
    required this.signatureSha256,
  });

  factory UsageInvoiceModel.fromJson(Map<String, dynamic> json) {
    final metrics = json['metrics'] as Map? ?? {};
    final charges = json['charges_usd'] as Map? ?? {};
    return UsageInvoiceModel(
      invoiceId: json['invoice_id'] as String? ?? '',
      orgId: json['org_id'] as String? ?? '',
      orgName: json['org_name'] as String? ?? '',
      planTier: json['plan_tier'] as String? ?? 'ENTERPRISE',
      billingCycle: json['billing_cycle'] as String? ?? '',
      generatedAt: (json['generated_at'] as num?)?.toDouble() ?? 0.0,
      totalQueries: metrics['total_queries'] as int? ?? 0,
      peakQps: (metrics['peak_qps'] as num?)?.toDouble() ?? 0.0,
      activeDevices: metrics['active_devices'] as int? ?? 0,
      totalAmountUsd: (charges['total'] as num?)?.toDouble() ?? 0.0,
      signatureSha256: json['signature_sha256'] as String? ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
    'invoice_id': invoiceId,
    'org_id': orgId,
    'org_name': orgName,
    'plan_tier': planTier,
    'billing_cycle': billingCycle,
    'generated_at': generatedAt,
    'metrics': {
      'total_queries': totalQueries,
      'peak_qps': peakQps,
      'active_devices': activeDevices,
    },
    'charges_usd': {
      'total': totalAmountUsd,
    },
    'signature_sha256': signatureSha256,
  };
}

@immutable
class SiemIngestAlertModel {
  final String alertId;
  final String vendor;
  final String tenantId;
  final String? deviceId;
  final String? clientIp;
  final String indicatorDomain;
  final String threatType;
  final String severity;
  final double riskScore;
  final double receivedAt;
  final bool deduplicated;

  const SiemIngestAlertModel({
    required this.alertId,
    required this.vendor,
    required this.tenantId,
    this.deviceId,
    this.clientIp,
    required this.indicatorDomain,
    required this.threatType,
    required this.severity,
    required this.riskScore,
    required this.receivedAt,
    required this.deduplicated,
  });

  factory SiemIngestAlertModel.fromJson(Map<String, dynamic> json) {
    return SiemIngestAlertModel(
      alertId: json['alert_id'] as String? ?? '',
      vendor: json['vendor'] as String? ?? 'GENERIC_SYSLOG',
      tenantId: json['tenant_id'] as String? ?? '',
      deviceId: json['device_id'] as String?,
      clientIp: json['client_ip'] as String?,
      indicatorDomain: json['indicator_domain'] as String? ?? '',
      threatType: json['threat_type'] as String? ?? 'EXTERNAL_ALERT',
      severity: json['severity'] as String? ?? 'HIGH',
      riskScore: (json['risk_score'] as num?)?.toDouble() ?? 75.0,
      receivedAt: (json['received_at'] as num?)?.toDouble() ?? 0.0,
      deduplicated: json['deduplicated'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() => {
    'alert_id': alertId,
    'vendor': vendor,
    'tenant_id': tenantId,
    'device_id': deviceId,
    'client_ip': clientIp,
    'indicator_domain': indicatorDomain,
    'threat_type': threatType,
    'severity': severity,
    'risk_score': riskScore,
    'received_at': receivedAt,
    'deduplicated': deduplicated,
  };
}

@immutable
class ThreatHuntQueryModel {
  final String tenantId;
  final String? subTenantId;
  final String? deviceId;
  final String? cidrSubnet;
  final String? domainPattern;
  final double? minEntropy;
  final String? threatType;
  final String? action;
  final int limit;

  const ThreatHuntQueryModel({
    required this.tenantId,
    this.subTenantId,
    this.deviceId,
    this.cidrSubnet,
    this.domainPattern,
    this.minEntropy,
    this.threatType,
    this.action,
    this.limit = 200,
  });

  Map<String, dynamic> toJson() => {
    'tenant_id': tenantId,
    if (subTenantId != null) 'sub_tenant_id': subTenantId,
    if (deviceId != null) 'device_id': deviceId,
    if (cidrSubnet != null) 'cidr_subnet': cidrSubnet,
    if (domainPattern != null) 'domain_pattern': domainPattern,
    if (minEntropy != null) 'min_entropy': minEntropy,
    if (threatType != null) 'threat_type': threatType,
    if (action != null) 'action': action,
    'limit': limit,
  };

  factory ThreatHuntQueryModel.fromJson(Map<String, dynamic> json) {
    return ThreatHuntQueryModel(
      tenantId: json['tenant_id'] as String? ?? '',
      subTenantId: json['sub_tenant_id'] as String?,
      deviceId: json['device_id'] as String?,
      cidrSubnet: json['cidr_subnet'] as String?,
      domainPattern: json['domain_pattern'] as String?,
      minEntropy: (json['min_entropy'] as num?)?.toDouble(),
      threatType: json['threat_type'] as String?,
      action: json['action'] as String?,
      limit: json['limit'] as int? ?? 200,
    );
  }
}

@immutable
class ThreatHuntResultRecordModel {
  final int timestampUs;
  final String tenantId;
  final String subTenantId;
  final String deviceId;
  final String clientIp;
  final String domain;
  final String qtype;
  final String rcode;
  final String action;
  final String threatType;
  final String category;
  final int latencyUs;
  final int bytesTransferred;
  final double shannonEntropy;
  final double vowelRatio;
  final bool isDgaCandidate;
  final bool isPunycode;

  const ThreatHuntResultRecordModel({
    required this.timestampUs,
    required this.tenantId,
    required this.subTenantId,
    required this.deviceId,
    required this.clientIp,
    required this.domain,
    required this.qtype,
    required this.rcode,
    required this.action,
    required this.threatType,
    required this.category,
    required this.latencyUs,
    required this.bytesTransferred,
    required this.shannonEntropy,
    required this.vowelRatio,
    required this.isDgaCandidate,
    required this.isPunycode,
  });

  factory ThreatHuntResultRecordModel.fromJson(Map<String, dynamic> json) {
    return ThreatHuntResultRecordModel(
      timestampUs: json['timestamp_us'] as int? ?? 0,
      tenantId: json['tenant_id'] as String? ?? '',
      subTenantId: json['sub_tenant_id'] as String? ?? '',
      deviceId: json['device_id'] as String? ?? '',
      clientIp: json['client_ip'] as String? ?? '',
      domain: json['domain'] as String? ?? '',
      qtype: json['qtype'] as String? ?? 'A',
      rcode: json['rcode'] as String? ?? 'NOERROR',
      action: json['action'] as String? ?? 'ALLOW',
      threatType: json['threat_type'] as String? ?? 'NONE',
      category: json['category'] as String? ?? 'General',
      latencyUs: json['latency_us'] as int? ?? 0,
      bytesTransferred: json['bytes_transferred'] as int? ?? 0,
      shannonEntropy: (json['shannon_entropy'] as num?)?.toDouble() ?? 0.0,
      vowelRatio: (json['vowel_ratio'] as num?)?.toDouble() ?? 0.0,
      isDgaCandidate: json['is_dga_candidate'] as bool? ?? false,
      isPunycode: json['is_punycode'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() => {
    'timestamp_us': timestampUs,
    'tenant_id': tenantId,
    'sub_tenant_id': subTenantId,
    'device_id': deviceId,
    'client_ip': clientIp,
    'domain': domain,
    'qtype': qtype,
    'rcode': rcode,
    'action': action,
    'threat_type': threatType,
    'category': category,
    'latency_us': latencyUs,
    'bytes_transferred': bytesTransferred,
    'shannon_entropy': shannonEntropy,
    'vowel_ratio': vowelRatio,
    'is_dga_candidate': isDgaCandidate,
    'is_punycode': isPunycode,
  };
}

@immutable
class ThreatHuntResultModel {
  final String tenantId;
  final int totalMatches;
  final double executionTimeMs;
  final int dgaAnomalyCount;
  final List<ThreatHuntResultRecordModel> records;

  const ThreatHuntResultModel({
    required this.tenantId,
    required this.totalMatches,
    required this.executionTimeMs,
    required this.dgaAnomalyCount,
    required this.records,
  });

  factory ThreatHuntResultModel.fromJson(Map<String, dynamic> json) {
    final rawList = json['records'] as List? ?? [];
    return ThreatHuntResultModel(
      tenantId: json['tenant_id'] as String? ?? '',
      totalMatches: json['total_matches'] as int? ?? rawList.length,
      executionTimeMs: (json['execution_time_ms'] as num?)?.toDouble() ?? 0.0,
      dgaAnomalyCount: json['dga_anomaly_count'] as int? ?? 0,
      records: rawList.map((e) => ThreatHuntResultRecordModel.fromJson(Map<String, dynamic>.from(e as Map))).toList(),
    );
  }

  Map<String, dynamic> toJson() => {
    'tenant_id': tenantId,
    'total_matches': totalMatches,
    'execution_time_ms': executionTimeMs,
    'dga_anomaly_count': dgaAnomalyCount,
    'records': records.map((e) => e.toJson()).toList(),
  };
}

@immutable
class DnsTimelineEntryModel {
  final int timestampUs;
  final String domain;
  final String clientIp;
  final String action;
  final String threatType;

  const DnsTimelineEntryModel({
    required this.timestampUs,
    required this.domain,
    required this.clientIp,
    required this.action,
    required this.threatType,
  });

  factory DnsTimelineEntryModel.fromJson(Map<String, dynamic> json) {
    return DnsTimelineEntryModel(
      timestampUs: json['timestamp_us'] as int? ?? 0,
      domain: json['domain'] as String? ?? '',
      clientIp: json['client_ip'] as String? ?? '',
      action: json['action'] as String? ?? 'ALLOW',
      threatType: json['threat_type'] as String? ?? 'NONE',
    );
  }

  Map<String, dynamic> toJson() => {
    'timestamp_us': timestampUs,
    'domain': domain,
    'client_ip': clientIp,
    'action': action,
    'threat_type': threatType,
  };
}

@immutable
class EndpointDnsTimelineModel {
  final String tenantId;
  final String deviceId;
  final int timeWindowMinutes;
  final int totalQueriesRecorded;
  final int burstCount;
  final List<Map<String, dynamic>> suspectedBeacons;
  final List<DnsTimelineEntryModel> timeline;

  const EndpointDnsTimelineModel({
    required this.tenantId,
    required this.deviceId,
    required this.timeWindowMinutes,
    required this.totalQueriesRecorded,
    required this.burstCount,
    required this.suspectedBeacons,
    required this.timeline,
  });

  factory EndpointDnsTimelineModel.fromJson(Map<String, dynamic> json) {
    final rawTimeline = json['timeline'] as List? ?? [];
    final rawBeacons = json['suspected_beacons'] as List? ?? [];
    return EndpointDnsTimelineModel(
      tenantId: json['tenant_id'] as String? ?? '',
      deviceId: json['device_id'] as String? ?? '',
      timeWindowMinutes: json['time_window_minutes'] as int? ?? 30,
      totalQueriesRecorded: json['total_queries_recorded'] as int? ?? rawTimeline.length,
      burstCount: json['burst_count'] as int? ?? 0,
      suspectedBeacons: rawBeacons.map((e) => Map<String, dynamic>.from(e as Map)).toList(),
      timeline: rawTimeline.map((e) => DnsTimelineEntryModel.fromJson(Map<String, dynamic>.from(e as Map))).toList(),
    );
  }

  Map<String, dynamic> toJson() => {
    'tenant_id': tenantId,
    'device_id': deviceId,
    'time_window_minutes': timeWindowMinutes,
    'total_queries_recorded': totalQueriesRecorded,
    'burst_count': burstCount,
    'suspected_beacons': suspectedBeacons,
    'timeline': timeline.map((e) => e.toJson()).toList(),
  };
}

@immutable
class PolicyDriftRecordModel {
  final String recordId;
  final String tenantId;
  final String fleetId;
  final String deviceId;
  final String driftType;
  final String expectedPolicyHash;
  final String reportedPolicyHash;
  final String details;
  final double detectedAt;
  final bool remediated;
  final double? remediatedAt;

  const PolicyDriftRecordModel({
    required this.recordId,
    required this.tenantId,
    required this.fleetId,
    required this.deviceId,
    required this.driftType,
    required this.expectedPolicyHash,
    required this.reportedPolicyHash,
    required this.details,
    required this.detectedAt,
    required this.remediated,
    this.remediatedAt,
  });

  factory PolicyDriftRecordModel.fromJson(Map<String, dynamic> json) {
    return PolicyDriftRecordModel(
      recordId: json['record_id'] as String? ?? '',
      tenantId: json['tenant_id'] as String? ?? '',
      fleetId: json['fleet_id'] as String? ?? '',
      deviceId: json['device_id'] as String? ?? '',
      driftType: json['drift_type'] as String? ?? 'HASH_MISMATCH',
      expectedPolicyHash: json['expected_policy_hash'] as String? ?? '',
      reportedPolicyHash: json['reported_policy_hash'] as String? ?? '',
      details: json['details'] as String? ?? '',
      detectedAt: (json['detected_at'] as num?)?.toDouble() ?? 0.0,
      remediated: json['remediated'] as bool? ?? false,
      remediatedAt: (json['remediated_at'] as num?)?.toDouble(),
    );
  }

  Map<String, dynamic> toJson() => {
    'record_id': recordId,
    'tenant_id': tenantId,
    'fleet_id': fleetId,
    'device_id': deviceId,
    'drift_type': driftType,
    'expected_policy_hash': expectedPolicyHash,
    'reported_policy_hash': reportedPolicyHash,
    'details': details,
    'detected_at': detectedAt,
    'remediated': remediated,
    if (remediatedAt != null) 'remediated_at': remediatedAt,
  };
}

@immutable
class TenantComplianceReportModel {
  final String tenantId;
  final int totalDevices;
  final int compliantDevices;
  final int driftedDevices;
  final double complianceScore;
  final double generatedAt;
  final List<PolicyDriftRecordModel> drifts;

  const TenantComplianceReportModel({
    required this.tenantId,
    required this.totalDevices,
    required this.compliantDevices,
    required this.driftedDevices,
    required this.complianceScore,
    required this.generatedAt,
    required this.drifts,
  });

  factory TenantComplianceReportModel.fromJson(Map<String, dynamic> json) {
    final rawDrifts = json['drifts'] as List? ?? [];
    return TenantComplianceReportModel(
      tenantId: json['tenant_id'] as String? ?? '',
      totalDevices: json['total_devices'] as int? ?? 1,
      compliantDevices: json['compliant_devices'] as int? ?? 1,
      driftedDevices: json['drifted_devices'] as int? ?? 0,
      complianceScore: (json['compliance_score'] as num?)?.toDouble() ?? 100.0,
      generatedAt: (json['generated_at'] as num?)?.toDouble() ?? 0.0,
      drifts: rawDrifts.map((e) => PolicyDriftRecordModel.fromJson(Map<String, dynamic>.from(e as Map))).toList(),
    );
  }

  Map<String, dynamic> toJson() => {
    'tenant_id': tenantId,
    'total_devices': totalDevices,
    'compliant_devices': compliantDevices,
    'drifted_devices': driftedDevices,
    'compliance_score': complianceScore,
    'generated_at': generatedAt,
    'drifts': drifts.map((e) => e.toJson()).toList(),
  };
}

@immutable
class BillingSummaryModel {
  final String orgId;
  final String planTier;
  final int activeDevices;
  final int maxDevices;
  final int totalQueriesMonth;
  final double peakQps;
  final double currentCostUsd;
  final bool isQuotaExceeded;
  final List<String> warnings;

  const BillingSummaryModel({
    required this.orgId,
    required this.planTier,
    required this.activeDevices,
    required this.maxDevices,
    required this.totalQueriesMonth,
    required this.peakQps,
    required this.currentCostUsd,
    required this.isQuotaExceeded,
    required this.warnings,
  });

  factory BillingSummaryModel.fromJson(Map<String, dynamic> json) {
    final usage = json['usage'] as Map? ?? {};
    final inv = json['current_invoice'] as Map? ?? {};
    final charges = inv['charges_usd'] as Map? ?? {};
    final metrics = inv['metrics'] as Map? ?? {};
    final active = metrics['active_devices'] as int? ?? usage['active_devices_estimate'] as int? ?? 0;
    final maxDev = usage['quota_max_devices'] as int? ?? 500;
    final totalQueries = metrics['total_queries'] as int? ?? usage['total_queries'] as int? ?? 0;
    final qps = (metrics['peak_qps'] as num?)?.toDouble() ?? (usage['peak_qps'] as num?)?.toDouble() ?? 0.0;
    final cost = (charges['total'] as num?)?.toDouble() ?? (inv['total_amount_usd'] as num?)?.toDouble() ?? 0.0;
    final rawWarnings = json['warnings'] as List? ?? [];

    return BillingSummaryModel(
      orgId: json['org_id'] as String? ?? '',
      planTier: inv['plan_tier'] as String? ?? 'ENTERPRISE',
      activeDevices: active,
      maxDevices: maxDev,
      totalQueriesMonth: totalQueries,
      peakQps: qps,
      currentCostUsd: cost,
      isQuotaExceeded: active > maxDev,
      warnings: rawWarnings.map((e) => e.toString()).toList(),
    );
  }

  Map<String, dynamic> toJson() => {
    'org_id': orgId,
    'plan_tier': planTier,
    'active_devices': activeDevices,
    'max_devices': maxDevices,
    'total_queries_month': totalQueriesMonth,
    'peak_qps': peakQps,
    'current_cost_usd': currentCostUsd,
    'is_quota_exceeded': isQuotaExceeded,
    'warnings': warnings,
  };
}

