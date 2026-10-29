"""
Unit Test Suite for FocusDNS Enterprise - REST API Router & Control Plane Dispatcher.
Validates multi-tenant REST endpoints, login, fleet locking, audit hash verification,
columnar analytics querying, and HTTP 403 Conditional Whitelisting enforcement.
"""

import os
import tempfile
import time
import unittest
from server.enterprise.columnar_analytics import ColumnarAnalyticsEngine, DnsQueryEvent
from server.enterprise.rbac_engine import RbacEngine, RoleTier
from server.enterprise.tenant_manager import TenantManager
from server.enterprise.fleet_websocket_server import FleetWebSocketServer
from server.enterprise.siem_forwarder import SiemForwarder, SiemConfig
from server.enterprise.api_enterprise_router import EnterpriseApiDispatcher


class TestEnterpriseApiRouter(unittest.TestCase):

    def setUp(self):
        self.temp_db = tempfile.NamedTemporaryFile(suffix=".db", delete=False)
        self.temp_db.close()

        self.rbac = RbacEngine(secret_key="Api-Test-Secret-Key")
        self.tenants = TenantManager(db_path=self.temp_db.name)
        self.analytics = ColumnarAnalyticsEngine(use_duckdb=False)
        self.ws_hub = FleetWebSocketServer(ping_interval_sec=10.0)
        self.siem = SiemForwarder(config=SiemConfig(enabled=False))

        self.dispatcher = EnterpriseApiDispatcher(
            rbac=self.rbac,
            tenants=self.tenants,
            analytics=self.analytics,
            ws_hub=self.ws_hub,
            siem=self.siem
        )

    def tearDown(self):
        self.analytics.shutdown()
        self.ws_hub.shutdown()
        self.siem.shutdown()
        if os.path.exists(self.temp_db.name):
            os.unlink(self.temp_db.name)

    def test_info_endpoint(self):
        """GET /api/v1/enterprise/info returns system status and sub-systems."""
        status, resp = self.dispatcher.handle_get("/api/v1/enterprise/info", {})
        self.assertEqual(status, 200)
        self.assertTrue(resp["success"])
        self.assertEqual(resp["version"], "7.0.0-enterprise")
        self.assertIn("columnar_backend", resp["subsystems"])

    def test_authentication_login_flow(self):
        """POST /api/v1/enterprise/auth/login validates credentials and issues token."""
        # 1. Valid credentials
        status, resp = self.dispatcher.handle_post(
            "/api/v1/enterprise/auth/login",
            {"username": "superadmin", "password": "admin123"}
        )
        self.assertEqual(status, 200)
        self.assertTrue(resp["success"])
        self.assertIn("token", resp)
        self.assertEqual(resp["user"]["role"], "SUPER_ADMIN")

        # 2. Invalid credentials -> 401 Unauthorized
        bad_status, bad_resp = self.dispatcher.handle_post(
            "/api/v1/enterprise/auth/login",
            {"username": "superadmin", "password": "wrong"}
        )
        self.assertEqual(bad_status, 401)
        self.assertFalse(bad_resp["success"])

    def test_organization_and_unit_lifecycle(self):
        """Creates organization and nested sub-tenant units."""
        # 1. Create Org
        status, resp = self.dispatcher.handle_post(
            "/api/v1/enterprise/tenants",
            {"name": "District 99", "domain": "d99.k12.us", "max_devices": 300}
        )
        self.assertEqual(status, 201)
        org_id = resp["organization"]["org_id"]

        # 2. Create Unit
        status_u, resp_u = self.dispatcher.handle_post(
            "/api/v1/enterprise/units",
            {"org_id": org_id, "name": "East High School", "unit_type": "SCHOOL"}
        )
        self.assertEqual(status_u, 201)
        unit_id = resp_u["unit"]["unit_id"]

        # 3. GET /tenants
        get_status, get_resp = self.dispatcher.handle_get(
            "/api/v1/enterprise/tenants",
            {"org_id": [org_id]}
        )
        self.assertEqual(get_status, 200)
        self.assertEqual(len(get_resp["units"]), 1)
        self.assertEqual(get_resp["units"][0]["unit_id"], unit_id)

    def test_fleet_lock_and_conditional_whitelisting_barrier(self):
        """
        INVIOLABLE CONDITIONAL WHITELISTING LAW:
        When fleet is locked, whitelist attempts MUST return HTTP 403 Forbidden with ERROR_ACCESS_DENIED (5).
        """
        # Create Org, Unit, and Fleet
        org = self.tenants.create_organization("Acme Labs", "acme.org")
        unit = self.tenants.create_tenant_unit(org.org_id, "Research")
        fleet = self.tenants.create_device_fleet(org.org_id, unit.unit_id, "Lab Tablets")

        # 1. Idle mode: Whitelist succeeds
        s_idle, r_idle = self.dispatcher.handle_post(
            "/api/v1/enterprise/fleets/whitelist",
            {"fleet_id": fleet.fleet_id, "domain": "arxiv.org"}
        )
        self.assertEqual(s_idle, 200)
        self.assertTrue(r_idle["success"])

        # 2. Lock fleet for 1 hour
        s_lock, r_lock = self.dispatcher.handle_post(
            "/api/v1/enterprise/fleets/lock",
            {"fleet_id": fleet.fleet_id, "duration_seconds": 3600}
        )
        self.assertEqual(s_lock, 200)
        self.assertTrue(r_lock["fleet"]["is_locked"])

        # 3. Whitelist attempt during lock MUST RETURN HTTP 403 FORBIDDEN
        s_block, r_block = self.dispatcher.handle_post(
            "/api/v1/enterprise/fleets/whitelist",
            {"fleet_id": fleet.fleet_id, "domain": "youtube.com"}
        )
        self.assertEqual(s_block, 403)
        self.assertFalse(r_block["success"])
        self.assertEqual(r_block["code"], "ERROR_ACCESS_DENIED")
        self.assertEqual(r_block["errno"], 5)
        self.assertIn("locked with", r_block["error"])

        # 4. Unlock fleet
        s_unlock, _ = self.dispatcher.handle_post(
            "/api/v1/enterprise/fleets/unlock",
            {"fleet_id": fleet.fleet_id}
        )
        self.assertEqual(s_unlock, 200)

        # 5. Whitelist succeeds again
        s_retry, _ = self.dispatcher.handle_post(
            "/api/v1/enterprise/fleets/whitelist",
            {"fleet_id": fleet.fleet_id, "domain": "youtube.com"}
        )
        self.assertEqual(s_retry, 200)

    def test_columnar_analytics_api_endpoints(self):
        """Validates timeseries, top-domains, and threat-matrix GET endpoints."""
        now_us = int(time.time() * 1_000_000)
        self.analytics.log_batch([
            DnsQueryEvent(now_us - 2_000_000, "org_test", "unit_1", "dev_1", "10.0.0.1", "google.com"),
            DnsQueryEvent(now_us - 1_000_000, "org_test", "unit_1", "dev_1", "10.0.0.1", "dga-c2.xyz", action="BLOCKED_MALWARE", threat_type="DGA_MALWARE")
        ])
        self.analytics.flush()

        # Top Domains
        s_top, r_top = self.dispatcher.handle_get(
            "/api/v1/enterprise/analytics/top-domains",
            {"tenant_id": ["org_test"]}
        )
        self.assertEqual(s_top, 200)
        self.assertEqual(len(r_top["top_domains"]), 2)

        # Threat Matrix
        s_tm, r_tm = self.dispatcher.handle_get(
            "/api/v1/enterprise/analytics/threat-matrix",
            {"tenant_id": ["org_test"]}
        )
        self.assertEqual(s_tm, 200)
        self.assertEqual(r_tm["threat_matrix"]["total_threats"], 1)

    def test_audit_verification_endpoint(self):
        """GET /api/v1/enterprise/rbac/audit-verify checks cryptographic hash chain."""
        status, resp = self.dispatcher.handle_get("/api/v1/enterprise/rbac/audit-verify", {})
        self.assertEqual(status, 200)
        self.assertTrue(resp["chain_valid"])
        self.assertEqual(resp["status"], "UNBROKEN_CRYPTOGRAPHIC_CHAIN")


if __name__ == "__main__":
    unittest.main()
