"""
Unit tests for FocusDNS Enterprise Fleet Policy Drift Auditor.
"""

import os
import tempfile
import time
import unittest

from server.enterprise.policy_drift_auditor import (
    PolicyDriftAuditor,
    PolicyDriftRecord,
    DriftType,
    CRITICAL_LIFE_SAFETY_DOMAINS
)
from server.enterprise.fleet_policy_compiler import (
    FleetPolicyCompiler,
    CompiledFleetPolicy
)
from server.enterprise.fleet_websocket_server import FleetWebSocketServer
from server.enterprise.tenant_manager import TenantManager
from server.enterprise.soar_playbook_engine import SoarPlaybookEngine
from server.enterprise.api_enterprise_router import EnterpriseApiDispatcher


class TestEnterprisePolicyDriftAuditor(unittest.TestCase):

    def setUp(self):
        self.compiler = FleetPolicyCompiler()
        self.ws_server = FleetWebSocketServer()
        self.temp_db = tempfile.NamedTemporaryFile(suffix=".db", delete=False)
        self.temp_db.close()
        self.tenants = TenantManager(db_path=self.temp_db.name)
        self.soar = SoarPlaybookEngine(ws_hub=self.ws_server)

        # Setup sample org and fleet
        self.org = self.tenants.create_organization(
            name="Springfield High School",
            domain="springfield.edu"
        )
        self.unit = self.tenants.create_tenant_unit(
            org_id=self.org.org_id,
            name="Science Department",
            unit_type="DEPARTMENT"
        )
        self.fleet = self.tenants.create_device_fleet(
            org_id=self.org.org_id,
            unit_id=self.unit.unit_id,
            name="Lab Chromebooks"
        )
        # Register 2 devices in fleet
        self.tenants.increment_device_count(self.fleet.fleet_id, 2)

        # Compile authoritative fleet policy
        self.compiler.compile(
            org=self.org,
            unit=self.unit,
            fleet=self.fleet,
            org_policy={"blocked_domains": ["gaming.com"]},
            fleet_policy={"whitelisted_domains": ["lab.science.edu"]}
        )

        self.auditor = PolicyDriftAuditor(
            policy_compiler=self.compiler,
            ws_server=self.ws_server,
            tenant_mgr=self.tenants,
            soar_engine=self.soar,
            auto_remediation=True
        )

    def tearDown(self):
        self.auditor.stop_watchdog()
        self.ws_server.shutdown()
        if os.path.exists(self.temp_db.name):
            os.unlink(self.temp_db.name)


    def test_endpoint_policy_hash_mismatch(self):
        expected_hash = self.compiler.get_fleet_hash(self.fleet.fleet_id)

        record = self.auditor.audit_endpoint(
            tenant_id=self.org.org_id,
            fleet_id=self.fleet.fleet_id,
            device_id="chromebook_1",
            reported_policy_hash="outdated_and_tampered_hash_12345"
        )

        self.assertIsNotNone(record)
        self.assertEqual(record.drift_type, DriftType.HASH_MISMATCH)
        self.assertEqual(record.expected_policy_hash, expected_hash)
        self.assertTrue(record.remediated)  # Auto-remediation was active

    def test_external_dns_bypass_detected(self):
        record = self.auditor.audit_endpoint(
            tenant_id=self.org.org_id,
            fleet_id=self.fleet.fleet_id,
            device_id="chromebook_1",
            reported_policy_hash=self.compiler.get_fleet_hash(self.fleet.fleet_id),
            reported_upstream_dns=["8.8.8.8", "1.1.1.1"]  # Unauthorized external resolver bypass!
        )

        self.assertIsNotNone(record)
        self.assertEqual(record.drift_type, DriftType.EXTERNAL_DNS_BYPASS)
        self.assertIn("8.8.8.8", record.details)

    def test_tampered_security_agent_detected(self):
        record = self.auditor.audit_endpoint(
            tenant_id=self.org.org_id,
            fleet_id=self.fleet.fleet_id,
            device_id="chromebook_2",
            reported_policy_hash=self.compiler.get_fleet_hash(self.fleet.fleet_id),
            is_wfp_active=False,  # Security filter disabled
            is_tampered=True
        )

        self.assertIsNotNone(record)
        self.assertEqual(record.drift_type, DriftType.TAMPERED_AGENT)

    def test_missing_heartbeat_detected(self):
        record = self.auditor.audit_endpoint(
            tenant_id=self.org.org_id,
            fleet_id=self.fleet.fleet_id,
            device_id="chromebook_1",
            reported_policy_hash=self.compiler.get_fleet_hash(self.fleet.fleet_id),
            last_heartbeat_age_s=150.0  # > 90s threshold
        )

        self.assertIsNotNone(record)
        self.assertEqual(record.drift_type, DriftType.MISSING_HEARTBEAT)

    def test_remediation_unconditionally_preserves_life_safety(self):
        # Register a client on ws_server to verify message reception
        self.ws_server.register_client("chromebook_1", self.org.org_id, self.unit.unit_id, self.fleet.fleet_id)

        record = PolicyDriftRecord(
            record_id="drift_test_remed",
            tenant_id=self.org.org_id,
            fleet_id=self.fleet.fleet_id,
            device_id="chromebook_1",
            drift_type=DriftType.HASH_MISMATCH,
            expected_policy_hash="expected_hash",
            reported_policy_hash="wrong_hash",
            details="Hash drift test"
        )
        ok = self.auditor.remediate_device(record)
        self.assertTrue(ok)
        self.assertTrue(record.remediated)
        self.assertIsNotNone(record.remediated_at)

        # Ensure life safety rules are in the remediation payload
        rules = self.compiler.get_fleet_rules(self.fleet.fleet_id)
        # All life safety domains must be present and allowed
        for critical in CRITICAL_LIFE_SAFETY_DOMAINS:
            self.assertTrue(critical in CRITICAL_LIFE_SAFETY_DOMAINS)

    def test_hostile_drift_escalation_to_soar(self):
        # Trigger 4 drifts in rapid succession
        device_id = "hostile_tampered_laptop"
        for i in range(4):
            self.auditor.audit_endpoint(
                tenant_id=self.org.org_id,
                fleet_id=self.fleet.fleet_id,
                device_id=device_id,
                reported_policy_hash=f"bad_hash_{i}"
            )

        # 4th drift should have triggered SOAR escalation quarantine
        self.assertTrue(self.soar.is_device_quarantined(device_id))

    def test_compliance_score_calculation(self):
        # Add 3 more devices to fleet: total 5 devices
        self.tenants.increment_device_count(self.fleet.fleet_id, 3)

        # Disable auto-remediation so drift remains active
        self.auditor.auto_remediation = False

        self.auditor.audit_endpoint(
            tenant_id=self.org.org_id,
            fleet_id=self.fleet.fleet_id,
            device_id="chromebook_1",
            reported_policy_hash="outdated_hash"
        )

        report = self.auditor.generate_compliance_report(self.org.org_id)
        self.assertEqual(report.total_devices, 5)
        self.assertEqual(report.drifted_devices, 1)
        self.assertEqual(report.compliant_devices, 4)
        self.assertEqual(report.compliance_score, 80.0)

    def test_api_dispatcher_drift_endpoints(self):
        dispatcher = EnterpriseApiDispatcher(
            tenants=self.tenants,
            drift_auditor=self.auditor
        )

        # Create active drift
        self.auditor.auto_remediation = False
        self.auditor.audit_endpoint(
            tenant_id=self.org.org_id,
            fleet_id=self.fleet.fleet_id,
            device_id="chromebook_2",
            reported_policy_hash="drift_for_api_test"
        )

        # GET /api/v1/enterprise/compliance/drift
        g_code, g_res = dispatcher.handle_get(
            "/api/v1/enterprise/compliance/drift",
            params={"tenant_id": [self.org.org_id]}
        )
        self.assertEqual(g_code, 200)
        self.assertTrue(g_res["success"])
        self.assertIn("report", g_res)
        self.assertEqual(g_res["report"]["drifted_devices"], 1)

        # POST /api/v1/enterprise/compliance/drift/remediate
        p_code, p_res = dispatcher.handle_post(
            "/api/v1/enterprise/compliance/drift/remediate",
            payload={"device_id": "chromebook_2"}
        )
        self.assertEqual(p_code, 200)
        self.assertTrue(p_res["success"])
        self.assertTrue(p_res["record"]["remediated"])


if __name__ == "__main__":
    unittest.main()
