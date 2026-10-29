import 'package:flutter_test/flutter_test.dart';
import 'package:focus_dns/models/enterprise_models.dart';

void main() {
  group('RoleTier Enum Tests', () {
    test('fromString parses all role variants correctly', () {
      expect(RoleTier.fromString('SUPER_ADMIN'), RoleTier.superAdmin);
      expect(RoleTier.fromString('ORG_ADMIN'), RoleTier.orgAdmin);
      expect(RoleTier.fromString('TEAM_LEAD'), RoleTier.teamLead);
      expect(RoleTier.fromString('TEACHER_PARENT'), RoleTier.teacherParent);
      expect(RoleTier.fromString('COMPLIANCE_AUDITOR'), RoleTier.complianceAuditor);
      expect(RoleTier.fromString('unknown'), RoleTier.teamLead);
    });

    test('label and wireName provide clean presentation and serialization', () {
      expect(RoleTier.superAdmin.label, 'Super Admin');
      expect(RoleTier.superAdmin.wireName, 'SUPER_ADMIN');
      expect(RoleTier.teacherParent.label, 'Teacher / Parent');
      expect(RoleTier.teacherParent.wireName, 'TEACHER_PARENT');
    });
  });

  group('Tenant Hierarchy Models Tests', () {
    test('TenantQuotaModel serialization and deserialization', () {
      const quota = TenantQuotaModel(
        maxDevices: 500,
        maxQps: 1500,
        retentionDays: 90,
        allowSiem: true,
        allowCustomDga: true,
      );
      final json = quota.toJson();
      expect(json['max_devices'], 500);
      expect(json['max_qps'], 1500);
      expect(json['retention_days'], 90);
      expect(json['allow_siem'], true);

      final restored = TenantQuotaModel.fromJson(json);
      expect(restored.maxDevices, 500);
      expect(restored.maxQps, 1500);
      expect(restored.retentionDays, 90);
      expect(restored.allowCustomDga, true);
    });

    test('OrganizationModel serialization and deserialization', () {
      const org = OrganizationModel(
        orgId: 'org_acme',
        name: 'Acme Corporation',
        domain: 'acme.com',
        planTier: 'ENTERPRISE',
        isActive: true,
        createdAt: 1700000000.0,
        quota: TenantQuotaModel(
          maxDevices: 1000,
          maxQps: 5000,
          retentionDays: 180,
          allowSiem: true,
          allowCustomDga: true,
        ),
      );
      final json = org.toJson();
      expect(json['org_id'], 'org_acme');
      expect(json['name'], 'Acme Corporation');
      expect(json['is_active'], true);

      final restored = OrganizationModel.fromJson(json);
      expect(restored.orgId, 'org_acme');
      expect(restored.name, 'Acme Corporation');
      expect(restored.quota.maxDevices, 1000);
    });

    test('TenantUnitModel serialization and deserialization', () {
      const unit = TenantUnitModel(
        unitId: 'unit_sales',
        orgId: 'org_acme',
        name: 'Global Sales',
        unitType: 'DEPARTMENT',
        policyProfile: {'safe_search': true},
        isActive: true,
      );
      final json = unit.toJson();
      expect(json['unit_id'], 'unit_sales');
      expect(json['unit_type'], 'DEPARTMENT');

      final restored = TenantUnitModel.fromJson(json);
      expect(restored.unitId, 'unit_sales');
      expect(restored.orgId, 'org_acme');
      expect(restored.policyProfile['safe_search'], true);
    });

    test('DeviceFleetModel serialization and deserialization', () {
      const fleet = DeviceFleetModel(
        fleetId: 'fleet_laptops',
        unitId: 'unit_sales',
        orgId: 'org_acme',
        name: 'Sales Laptops',
        platform: 'WINDOWS',
        policyProfileId: 'policy_strict',
        isLocked: false,
        remainingLockSeconds: 0,
        deviceCount: 25,
      );
      final json = fleet.toJson();
      expect(json['fleet_id'], 'fleet_laptops');
      expect(json['platform'], 'WINDOWS');

      final restored = DeviceFleetModel.fromJson(json);
      expect(restored.fleetId, 'fleet_laptops');
      expect(restored.platform, 'WINDOWS');
      expect(restored.deviceCount, 25);
    });
  });

  group('Columnar Analytics Models Tests', () {
    test('TimeseriesPointModel serialization and getters', () {
      const pt = TimeseriesPointModel(
        timestamp: 1700000000,
        totalQueries: 1000,
        blockedQueries: 250,
        threatCount: 15,
        allowedQueries: 750,
      );
      final json = pt.toJson();
      final restored = TimeseriesPointModel.fromJson(json);
      expect(restored.timestamp, 1700000000);
      expect(restored.totalQueries, 1000);
      expect(restored.blockedQueries, 250);
      expect(restored.threatCount, 15);
      expect(restored.allowedQueries, 750);
    });

    test('TopDomainStatModel serialization and deserialization', () {
      const stat = TopDomainStatModel(
        domain: 'example.com',
        queryCount: 500,
        action: 'ALLOWED',
        category: 'ADVERTISING',
      );
      final json = stat.toJson();
      final restored = TopDomainStatModel.fromJson(json);
      expect(restored.domain, 'example.com');
      expect(restored.queryCount, 500);
      expect(restored.action, 'ALLOWED');
      expect(restored.category, 'ADVERTISING');
    });

    test('ThreatMatrixModel serialization and breakdown mapping', () {
      const tm = ThreatMatrixModel(
        totalThreats: 61,
        breakdown: {
          'PHISHING': 10,
          'MALWARE': 5,
          'DGA': 2,
          'POLICY_VIOLATION': 44,
        },
      );
      expect(tm.totalThreats, 61);
      final json = tm.toJson();
      final restored = ThreatMatrixModel.fromJson(json);
      expect(restored.totalThreats, 61);
      expect(restored.breakdown['PHISHING'], 10);
      expect(restored.breakdown['MALWARE'], 5);
    });

    test('LatencyQuantilesModel serialization and conversions', () {
      const lq = LatencyQuantilesModel(
        p50: 0.8,
        p90: 1.8,
        p95: 3.2,
        p99: 9.5,
        avg: 1.1,
        count: 50000,
      );
      final json = lq.toJson();
      final restored = LatencyQuantilesModel.fromJson(json);
      expect(restored.p50, 0.8);
      expect(restored.p90, 1.8);
      expect(restored.p95, 3.2);
      expect(restored.p99, 9.5);
      expect(restored.avg, 1.1);
      expect(restored.count, 50000);
    });
  });

  group('RBAC, Audit & Fleet Models Tests', () {
    test('RbacUserModel serialization and getters', () {
      const user = RbacUserModel(
        userId: 'u_123',
        username: 'alice',
        email: 'alice@acme.com',
        role: RoleTier.orgAdmin,
        tenantId: 'org_acme',
        subTenantIds: ['unit_sales', 'unit_eng'],
        isActive: true,
        createdAt: 1700000000.0,
      );
      final json = user.toJson();
      final restored = RbacUserModel.fromJson(json);
      expect(restored.userId, 'u_123');
      expect(restored.username, 'alice');
      expect(restored.role, RoleTier.orgAdmin);
      expect(restored.subTenantIds.length, 2);
    });

    test('AuditEntryModel serialization and deserialization', () {
      const audit = AuditEntryModel(
        entryId: 'aud_456',
        timestamp: 1700000000.0,
        actorUserId: 'u_123',
        actorRole: 'ORG_ADMIN',
        tenantId: 'org_acme',
        action: 'LOCK_SESSION',
        resource: 'fleet_laptops',
        details: {'duration': 1800},
        status: 'SUCCESS',
        previousHash: '0000000000000000000000000000000000000000',
        entryHash: 'abcdef0123456789abcdef0123456789abcdef01',
      );
      final json = audit.toJson();
      final restored = AuditEntryModel.fromJson(json);
      expect(restored.entryId, 'aud_456');
      expect(restored.action, 'LOCK_SESSION');
      expect(restored.entryHash, 'abcdef0123456789abcdef0123456789abcdef01');
    });

    test('SiemConfigModel serialization and deserialization', () {
      const cfg = SiemConfigModel(
        enabled: true,
        transport: 'UDP',
        host: '10.0.0.99',
        port: 514,
        apiToken: 'splunk_token_xyz',
        indexName: 'focusdns_security',
        facility: 16,
        minSeverity: 4,
      );
      final json = cfg.toJson();
      expect(json['transport'], 'UDP');
      expect(json['host'], '10.0.0.99');

      final restored = SiemConfigModel.fromJson(json);
      expect(restored.host, '10.0.0.99');
      expect(restored.enabled, true);
      expect(restored.port, 514);
      expect(restored.apiToken, 'splunk_token_xyz');
    });

    test('FleetDeviceConnectionModel serialization and getters', () {
      const conn = FleetDeviceConnectionModel(
        deviceId: 'dev_iphone_12',
        orgId: 'org_acme',
        unitId: 'unit_sales',
        fleetId: 'fleet_laptops',
        platform: 'IOS',
        connectedAt: 1700000000.0,
        lastHeartbeat: 1700000050.0,
        rttMs: 14.5,
        pendingQueueSize: 0,
        isAlive: true,
      );
      final json = conn.toJson();
      final restored = FleetDeviceConnectionModel.fromJson(json);
      expect(restored.deviceId, 'dev_iphone_12');
      expect(restored.rttMs, 14.5);
      expect(restored.isAlive, true);
    });

    test('DeviceFleetModel with locked status and timestamp', () {
      const lockedFleet = DeviceFleetModel(
        fleetId: 'flt_locked',
        unitId: 'unit_exam',
        orgId: 'org_k12',
        name: 'Exam Room A',
        platform: 'CHROMEOS',
        policyProfileId: 'profile_locked_strict',
        isLocked: true,
        lockedUntil: 1700003600.0,
        remainingLockSeconds: 3600,
        deviceCount: 30,
      );
      final json = lockedFleet.toJson();
      expect(json['is_locked'], true);
      expect(json['locked_until'], 1700003600.0);
      expect(json['remaining_lock_seconds'], 3600);

      final restored = DeviceFleetModel.fromJson(json);
      expect(restored.isLocked, true);
      expect(restored.lockedUntil, 1700003600.0);
      expect(restored.remainingLockSeconds, 3600);
    });

    test('TenantUnitModel handles optional parentUnitId and policyProfile', () {
      const subUnit = TenantUnitModel(
        unitId: 'unit_sub_dept',
        orgId: 'org_acme',
        name: 'Sub Department',
        unitType: 'SUB_DEPARTMENT',
        parentUnitId: 'unit_sales',
        policyProfile: {'safe_search': true, 'youtube_restricted': true},
        isActive: false,
      );
      final json = subUnit.toJson();
      expect(json['parent_unit_id'], 'unit_sales');
      expect(json['is_active'], false);

      final restored = TenantUnitModel.fromJson(json);
      expect(restored.parentUnitId, 'unit_sales');
      expect(restored.isActive, false);
      expect(restored.policyProfile['youtube_restricted'], true);
    });

    test('AuditEntryModel hash and details verification', () {
      const entry = AuditEntryModel(
        entryId: 'aud_999',
        timestamp: 1700005000.0,
        actorUserId: 'usr_sec_lead',
        actorRole: 'TEAM_LEAD',
        tenantId: 'org_sec',
        action: 'UPDATE_SIEM_ENDPOINT',
        resource: 'siem/config',
        details: {'transport': 'TLS', 'port': 6514},
        status: 'SUCCESS',
        previousHash: 'a1b2c3d4e5f6',
        entryHash: 'f6e5d4c3b2a1',
      );
      final json = entry.toJson();
      final restored = AuditEntryModel.fromJson(json);
      expect(restored.action, 'UPDATE_SIEM_ENDPOINT');
      expect(restored.details['port'], 6514);
      expect(restored.entryHash, 'f6e5d4c3b2a1');
    });
  });
}
