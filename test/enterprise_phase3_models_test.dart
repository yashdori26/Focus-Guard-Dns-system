import 'package:flutter_test/flutter_test.dart';
import 'package:focus_dns/models/enterprise_models.dart';

void main() {
  group('Phase 3 Enterprise Models Serialization Tests', () {
    test('ClassroomFocusMode enum conversion', () {
      expect(ClassroomFocusMode.fromString('NORMAL_PROTECTION'), ClassroomFocusMode.normalProtection);
      expect(ClassroomFocusMode.fromString('RESTRICTED_RESEARCH'), ClassroomFocusMode.restrictedResearch);
      expect(ClassroomFocusMode.fromString('STRICT_EXAM_MODE'), ClassroomFocusMode.strictExamMode);
      expect(ClassroomFocusMode.fromString('UNKNOWN'), ClassroomFocusMode.normalProtection);

      expect(ClassroomFocusMode.normalProtection.wireName, 'NORMAL_PROTECTION');
      expect(ClassroomFocusMode.strictExamMode.displayName, 'Strict Exam Lockdown');
    });

    test('StudentDeviceModel JSON serialization', () {
      const student = StudentDeviceModel(
        deviceId: 'chromebook_01',
        studentName: 'Alex Johnson',
        studentId: 'STU-9401',
        clientIp: '192.168.1.101',
        lastQueryTime: 1761700000.0,
        lastQueriedDomain: 'khanacademy.org',
        distractionCount: 0,
        isLocked: false,
        handRaised: true,
      );

      final json = student.toJson();
      expect(json['device_id'], 'chromebook_01');
      expect(json['hand_raised'], true);

      final decoded = StudentDeviceModel.fromJson(json);
      expect(decoded.deviceId, 'chromebook_01');
      expect(decoded.studentName, 'Alex Johnson');
      expect(decoded.handRaised, true);
    });

    test('ClassroomSessionModel JSON serialization', () {
      final session = ClassroomSessionModel(
        sessionId: 'cls_period_3_bio',
        orgId: 'org_springfield',
        unitId: 'unit_lincoln_high',
        fleetId: 'flt_cart_4b',
        classroomName: 'Biology 101 - Period 3',
        teacherUserId: 'usr_teacher_smith',
        mode: ClassroomFocusMode.strictExamMode,
        durationSeconds: 2700,
        remainingSeconds: 1840,
        isActive: true,
        studentCount: 1,
        students: const [
          StudentDeviceModel(
            deviceId: 'chromebook_02',
            studentName: 'Emma Watson',
            studentId: 'STU-9402',
            clientIp: '192.168.1.102',
            lastQueryTime: 1761700045.0,
            lastQueriedDomain: 'canvas.instructure.com',
            distractionCount: 0,
            isLocked: true,
            handRaised: false,
          ),
        ],
        distractionAlertCount: 0,
        allowedExamDomains: const ['canvas.instructure.com', 'exam.school.edu'],
      );

      final json = session.toJson();
      expect(json['session_id'], 'cls_period_3_bio');
      expect(json['mode'], 'STRICT_EXAM_MODE');

      final decoded = ClassroomSessionModel.fromJson(json);
      expect(decoded.sessionId, 'cls_period_3_bio');
      expect(decoded.mode, ClassroomFocusMode.strictExamMode);
      expect(decoded.students.length, 1);
      expect(decoded.allowedExamDomains.length, 2);
    });

    test('SoarIncidentModel JSON serialization', () {
      const incident = SoarIncidentModel(
        incidentId: 'inc_84a91c',
        timestamp: 1761700000.0,
        tenantId: 'org_springfield',
        deviceId: 'chromebook_03',
        triggerType: 'ZERO_HOUR_PHISHING',
        domain: 'login-credential-steal.xyz',
        riskScore: 94.5,
        actionsExecuted: ['SNAPSHOT_FORENSICS', 'AUTO_BLACKLIST_DOMAIN', 'QUARANTINE_DEVICE'],
        snapshotRecords: 24,
        status: 'CONTAINED',
      );

      final json = incident.toJson();
      expect(json['incident_id'], 'inc_84a91c');
      expect(json['actions_executed'], contains('QUARANTINE_DEVICE'));

      final decoded = SoarIncidentModel.fromJson(json);
      expect(decoded.incidentId, 'inc_84a91c');
      expect(decoded.riskScore, 94.5);
      expect(decoded.status, 'CONTAINED');
    });

    test('ScimProvisioningLogModel JSON serialization', () {
      const log = ScimProvisioningLogModel(
        timestamp: 1761700000.0,
        action: 'PROVISION_USER',
        resourceId: 'usr_scim_123',
        identifier: 'john.doe@springfield.k12.us',
        details: 'Role=TEACHER_PARENT (Mapped from FocusDNS-Teachers)',
      );

      final json = log.toJson();
      expect(json['action'], 'PROVISION_USER');
      expect(json['identifier'], 'john.doe@springfield.k12.us');

      final decoded = ScimProvisioningLogModel.fromJson(json);
      expect(decoded.action, 'PROVISION_USER');
      expect(decoded.resourceId, 'usr_scim_123');
    });

    test('UsageInvoiceModel JSON serialization', () {
      const invoice = UsageInvoiceModel(
        invoiceId: 'inv_org_springfield_2026_10_a9f1',
        orgId: 'org_springfield',
        orgName: 'Springfield Unified District',
        planTier: 'EDUCATION_ENTERPRISE',
        billingCycle: '2026-10',
        generatedAt: 1761700000.0,
        totalQueries: 4820000,
        peakQps: 1840.5,
        activeDevices: 480,
        totalAmountUsd: 580.75,
        signatureSha256: '9f83c18b4382e293847291849182736481729384719283749182736481928374',
      );

      final json = invoice.toJson();
      expect(json['invoice_id'], 'inv_org_springfield_2026_10_a9f1');
      expect(json['metrics']['total_queries'], 4820000);
      expect(json['charges_usd']['total'], 580.75);

      final decoded = UsageInvoiceModel.fromJson(json);
      expect(decoded.invoiceId, 'inv_org_springfield_2026_10_a9f1');
      expect(decoded.totalQueries, 4820000);
      expect(decoded.totalAmountUsd, 580.75);
      expect(decoded.signatureSha256.length, 64);
    });
  });
}
