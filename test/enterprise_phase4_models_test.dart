// Test Suite: Topic 7 Phase 4 Enterprise Models Serialization & Logic

import 'package:flutter_test/flutter_test.dart';
import 'package:focus_dns/models/enterprise_models.dart';

void main() {
  group('Enterprise Phase 4 Domain Models', () {
    test('SiemIngestAlertModel serialization and deserialization', () {
      final json = {
        'alert_id': 'siem_splunk_a1b2c3d4',
        'vendor': 'SPLUNK',
        'tenant_id': 'org_springfield',
        'device_id': 'win11_workstation_04',
        'client_ip': '10.200.1.45',
        'indicator_domain': 'c2-beacon.darknet.cc',
        'threat_type': 'MALWARE_C2',
        'severity': 'CRITICAL',
        'risk_score': 92,
        'received_at': 1761701200.5,
        'deduplicated': false,
        'soar_triggered': true,
        'raw_payload': {'vendor_event_id': 'splunk_ev_99482'},
      };

      final model = SiemIngestAlertModel.fromJson(json);
      expect(model.alertId, equals('siem_splunk_a1b2c3d4'));
      expect(model.vendor, equals('SPLUNK'));
      expect(model.tenantId, equals('org_springfield'));
      expect(model.deviceId, equals('win11_workstation_04'));
      expect(model.clientIp, equals('10.200.1.45'));
      expect(model.indicatorDomain, equals('c2-beacon.darknet.cc'));
      expect(model.threatType, equals('MALWARE_C2'));
      expect(model.severity, equals('CRITICAL'));
      expect(model.riskScore, equals(92.0));
      expect(model.deduplicated, isFalse);

      final serialized = model.toJson();
      expect(serialized['alert_id'], equals(json['alert_id']));
      expect(serialized['vendor'], equals(json['vendor']));
      expect(serialized['risk_score'], equals(92.0));
    });

    test('ThreatHuntQueryModel serialization and defaults', () {
      const model = ThreatHuntQueryModel(
        tenantId: 'org_springfield',
        cidrSubnet: '10.200.0.0/16',
        domainPattern: r'.*\.top$',
        minEntropy: 3.8,
        threatType: 'DGA',
        limit: 150,
      );

      final json = model.toJson();
      expect(json['tenant_id'], equals('org_springfield'));
      expect(json['cidr_subnet'], equals('10.200.0.0/16'));
      expect(json['domain_pattern'], equals(r'.*\.top$'));
      expect(json['min_entropy'], equals(3.8));
      expect(json['threat_type'], equals('DGA'));
      expect(json['limit'], equals(150));

      final deserialized = ThreatHuntQueryModel.fromJson(json);
      expect(deserialized.tenantId, equals(model.tenantId));
      expect(deserialized.cidrSubnet, equals(model.cidrSubnet));
      expect(deserialized.minEntropy, equals(model.minEntropy));
    });

    test('ThreatHuntResultRecordModel and ThreatHuntResultModel', () {
      final recordJson = {
        'timestamp_us': 1761700000000000,
        'tenant_id': 'org_springfield',
        'sub_tenant_id': 'unt_hs',
        'device_id': 'chromebook_09',
        'client_ip': '10.200.4.12',
        'domain': 'oxk49fjf0a982jf.biz',
        'qtype': 'A',
        'rcode': 'NOERROR',
        'action': 'BLOCK',
        'threat_type': 'DGA',
        'category': 'Malware',
        'latency_us': 1450,
        'bytes_transferred': 512,
        'shannon_entropy': 4.12,
        'vowel_ratio': 0.15,
        'is_dga_candidate': true,
        'is_punycode': false,
      };

      final record = ThreatHuntResultRecordModel.fromJson(recordJson);
      expect(record.domain, equals('oxk49fjf0a982jf.biz'));
      expect(record.shannonEntropy, equals(4.12));
      expect(record.isDgaCandidate, isTrue);
      expect(record.action, equals('BLOCK'));

      final resultJson = {
        'tenant_id': 'org_springfield',
        'total_matches': 1,
        'execution_time_ms': 8.4,
        'dga_anomaly_count': 1,
        'records': [recordJson],
      };

      final result = ThreatHuntResultModel.fromJson(resultJson);
      expect(result.tenantId, equals('org_springfield'));
      expect(result.totalMatches, equals(1));
      expect(result.executionTimeMs, equals(8.4));
      expect(result.dgaAnomalyCount, equals(1));
      expect(result.records.length, equals(1));
      expect(result.records.first.deviceId, equals('chromebook_09'));

      final serialized = result.toJson();
      expect(serialized['total_matches'], equals(1));
    });

    test('DnsTimelineEntryModel and EndpointDnsTimelineModel', () {
      final entryJson = {
        'timestamp_us': 1761700000000000,
        'domain': 'beacon.c2server.org',
        'client_ip': '192.168.1.105',
        'action': 'BLOCK',
        'threat_type': 'C2',
      };

      final entry = DnsTimelineEntryModel.fromJson(entryJson);
      expect(entry.domain, equals('beacon.c2server.org'));
      expect(entry.action, equals('BLOCK'));

      final timelineJson = {
        'tenant_id': 'org_springfield',
        'device_id': 'device_win11_02',
        'time_window_minutes': 60,
        'total_queries_recorded': 34,
        'burst_count': 2,
        'suspected_beacons': [
          {'domain': 'beacon.c2server.org', 'interval_sec': 30, 'jitter_ratio': 0.04}
        ],
        'timeline': [entryJson],
      };

      final timeline = EndpointDnsTimelineModel.fromJson(timelineJson);
      expect(timeline.tenantId, equals('org_springfield'));
      expect(timeline.deviceId, equals('device_win11_02'));
      expect(timeline.burstCount, equals(2));
      expect(timeline.suspectedBeacons.length, equals(1));
      expect(timeline.timeline.length, equals(1));

      final serialized = timeline.toJson();
      expect(serialized['total_queries_recorded'], equals(34));
    });

    test('PolicyDriftRecordModel and TenantComplianceReportModel', () {
      final driftJson = {
        'record_id': 'drift_001',
        'tenant_id': 'org_springfield',
        'fleet_id': 'flt_chromebooks',
        'device_id': 'chromebook_05',
        'drift_type': 'EXTERNAL_DNS_BYPASS',
        'expected_policy_hash': '7a9f82bc4e10',
        'reported_policy_hash': '7a9f82bc4e10',
        'details': 'Unauthorized resolver 8.8.8.8 detected',
        'detected_at': 1761701000.0,
        'remediated': true,
        'remediated_at': 1761701050.0,
      };

      final drift = PolicyDriftRecordModel.fromJson(driftJson);
      expect(drift.recordId, equals('drift_001'));
      expect(drift.driftType, equals('EXTERNAL_DNS_BYPASS'));
      expect(drift.remediated, isTrue);
      expect(drift.remediatedAt, equals(1761701050.0));

      final reportJson = {
        'tenant_id': 'org_springfield',
        'total_devices': 50,
        'compliant_devices': 49,
        'drifted_devices': 1,
        'compliance_score': 98.0,
        'generated_at': 1761701100.0,
        'drifts': [driftJson],
      };

      final report = TenantComplianceReportModel.fromJson(reportJson);
      expect(report.tenantId, equals('org_springfield'));
      expect(report.totalDevices, equals(50));
      expect(report.compliantDevices, equals(49));
      expect(report.driftedDevices, equals(1));
      expect(report.complianceScore, equals(98.0));
      expect(report.drifts.length, equals(1));

      final serialized = report.toJson();
      expect(serialized['compliance_score'], equals(98.0));
    });

    test('BillingSummaryModel serialization and quota calculations', () {
      final json = {
        'org_id': 'org_springfield',
        'usage': {
          'active_devices_estimate': 490,
          'quota_max_devices': 500,
          'total_queries': 5200000,
          'peak_qps': 1950.0,
        },
        'current_invoice': {
          'plan_tier': 'ENTERPRISE_EDUCATION',
          'total_amount_usd': 620.50,
          'charges_usd': {'total': 620.50},
          'metrics': {
            'active_devices': 490,
            'total_queries': 5200000,
            'peak_qps': 1950.0,
          },
        },
        'warnings': ['Active devices reached 98% of capacity.'],
      };

      final summary = BillingSummaryModel.fromJson(json);
      expect(summary.orgId, equals('org_springfield'));
      expect(summary.planTier, equals('ENTERPRISE_EDUCATION'));
      expect(summary.activeDevices, equals(490));
      expect(summary.maxDevices, equals(500));
      expect(summary.totalQueriesMonth, equals(5200000));
      expect(summary.peakQps, equals(1950.0));
      expect(summary.currentCostUsd, equals(620.50));
      expect(summary.isQuotaExceeded, isFalse);
      expect(summary.warnings, contains('Active devices reached 98% of capacity.'));

      final serialized = summary.toJson();
      expect(serialized['active_devices'], equals(490));
      expect(serialized['org_id'], equals('org_springfield'));
    });

    test('UsageInvoiceModel serialization and HMAC verification payload structure', () {
      final json = {
        'invoice_id': 'inv_org_springfield_2026_10_beef',
        'org_id': 'org_springfield',
        'org_name': 'Springfield Unified District',
        'plan_tier': 'ENTERPRISE',
        'billing_cycle': '2026-10',
        'generated_at': 1761702000.0,
        'metrics': {
          'total_queries': 4820000,
          'peak_qps': 1840.5,
          'active_devices': 480,
          'storage_bytes': 137438953472,
          'siem_egress_bytes': 10737418240,
        },
        'charges_usd': {
          'total': 580.75,
        },
        'signature_sha256': '9f83c18b4382e293847291849182736481729384719283749182736481928374',
      };

      final invoice = UsageInvoiceModel.fromJson(json);
      expect(invoice.invoiceId, equals('inv_org_springfield_2026_10_beef'));
      expect(invoice.orgId, equals('org_springfield'));
      expect(invoice.totalQueries, equals(4820000));
      expect(invoice.activeDevices, equals(480));
      expect(invoice.totalAmountUsd, equals(580.75));
      expect(invoice.signatureSha256, equals('9f83c18b4382e293847291849182736481729384719283749182736481928374'));

      final serialized = invoice.toJson();
      expect(serialized['invoice_id'], equals(invoice.invoiceId));
      expect(serialized['signature_sha256'], equals(invoice.signatureSha256));
    });
  });
}
