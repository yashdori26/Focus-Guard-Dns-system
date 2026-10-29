"""
Unit tests for FocusDNS Enterprise PII Redactor & Data Masking Engine.
"""

import unittest

from server.enterprise.pii_redactor import (
    PiiRedactor,
    get_pii_redactor
)
from server.enterprise.rbac_engine import (
    RbacEngine,
    RoleTier
)
from server.enterprise.columnar_analytics import (
    ColumnarAnalyticsEngine,
    DnsQueryEvent
)
from server.enterprise.threat_hunter import ThreatHunter
from server.enterprise.api_enterprise_router import EnterpriseApiDispatcher


class TestEnterprisePiiRedactor(unittest.TestCase):

    def setUp(self):
        self.rbac = RbacEngine()
        self.redactor = PiiRedactor(rbac_engine=self.rbac)

    def test_keyed_pseudonymization_deterministic_and_isolated(self):
        id_a = "student.johnson@springfield.k12.us"

        # Deterministic for same tenant
        pseudo1 = self.redactor.pseudonymize_identifier(id_a, tenant_id="org_springfield")
        pseudo2 = self.redactor.pseudonymize_identifier(id_a, tenant_id="org_springfield")
        self.assertEqual(pseudo1, pseudo2)
        self.assertTrue(pseudo1.startswith("anon_"))

        # Tenant isolation: different salt produces different pseudonym
        pseudo_other = self.redactor.pseudonymize_identifier(id_a, tenant_id="org_shelbyville")
        self.assertNotEqual(pseudo1, pseudo_other)

    def test_ip_address_masking(self):
        # IPv4 /24 subnet truncation
        masked_v4 = self.redactor.mask_ip_address("192.168.1.142")
        self.assertEqual(masked_v4, "192.168.1.0/24")

        # IPv6 /48 prefix truncation
        masked_v6 = self.redactor.mask_ip_address("2001:db8:85a3:8d3:1319:8a2e:370:7348")
        self.assertEqual(masked_v6, "2001:db8:85a3::/48")

        # Loopback preserved
        self.assertEqual(self.redactor.mask_ip_address("127.0.0.1"), "127.0.0.1")

    def test_embedded_domain_pii_sanitization(self):
        dom = "user_jane.doe@school.edu.tracking-cdn.com"
        sanitized = self.redactor.redact_embedded_domain_pii(dom)
        self.assertNotIn("jane.doe@school.edu", sanitized)
        self.assertIn("[REDACTED_EMAIL]", sanitized)

    def test_compliance_auditor_role_redaction(self):
        record = {
            "timestamp_us": 1730000000000000,
            "tenant_id": "org_springfield",
            "device_id": "ipad_classroom_4",
            "client_ip": "10.0.5.88",
            "user_id": "timmy.turner@springfield.edu",
            "domain": "khanacademy.org",
            "action": "ALLOW",
            "bytes_transferred": 1024,
            "latency_us": 850
        }

        redacted = self.redactor.redact_query_record(
            record=record,
            viewer_role=RoleTier.COMPLIANCE_AUDITOR,
            tenant_id="org_springfield"
        )

        self.assertTrue(redacted["pii_redacted"])
        self.assertEqual(redacted["client_ip"], "10.0.5.0/24")
        self.assertTrue(redacted["device_id"].startswith("dev_"))
        self.assertNotEqual(redacted["device_id"], "ipad_classroom_4")
        self.assertTrue(redacted["user_id"].startswith("usr_"))
        self.assertNotEqual(redacted["user_id"], "timmy.turner@springfield.edu")

    def test_super_admin_unmasked_view_with_audit_log(self):
        dataset = [
            {
                "timestamp_us": 1730000000000000,
                "tenant_id": "org_springfield",
                "device_id": "macbook_pro_10",
                "client_ip": "172.16.1.42",
                "domain": "admin-portal.internal"
            }
        ]

        # Register super-admin in rbac
        super_admin = self.rbac.create_user(
            username="sec_superadmin",
            email="sec@focusdns.internal",
            role=RoleTier.SUPER_ADMIN,
            password_hash="pw_hash"
        )

        out = self.redactor.redact_dataset(
            dataset=dataset,
            viewer_role=RoleTier.SUPER_ADMIN,
            tenant_id="org_springfield",
            requesting_user_id=super_admin.user_id
        )

        # Unmasked data preserved
        self.assertEqual(out[0]["client_ip"], "172.16.1.42")
        self.assertEqual(out[0]["device_id"], "macbook_pro_10")
        self.assertFalse(out[0]["pii_redacted"])

        # Cryptographic audit entry must be logged
        trail = self.rbac.get_audit_trail(limit=10)
        unmasked_events = [e for e in trail if e["action"] == "EXPORT_UNMASKED_PII_DATASET"]
        self.assertEqual(len(unmasked_events), 1)
        self.assertEqual(unmasked_events[0]["actor_user_id"], super_admin.user_id)

    def test_api_dispatcher_redacted_view_endpoint(self):
        analytics = ColumnarAnalyticsEngine(use_duckdb=False)
        hunter = ThreatHunter(columnar_engine=analytics)
        dispatcher = EnterpriseApiDispatcher(
            rbac=self.rbac,
            analytics=analytics,
            threat_hunter=hunter,
            pii_redactor=self.redactor
        )

        # Ingest event
        event = DnsQueryEvent(
            timestamp_us=1730000000000000,
            tenant_id="org_pii_test",
            sub_tenant_id="unit_1",
            device_id="unredacted_device",
            client_ip="192.168.10.99",
            domain="safe-learning.org",
            qtype="A",
            rcode=0,
            action="ALLOW",
            threat_type="NONE",
            category="Education",
            latency_us=500,
            bytes_transferred=45
        )
        analytics.backend.insert_batch([event])

        # GET /api/v1/enterprise/analytics/redacted
        code, res = dispatcher.handle_get(
            "/api/v1/enterprise/analytics/redacted",
            params={
                "tenant_id": ["org_pii_test"],
                "role": ["COMPLIANCE_AUDITOR"],
                "limit": ["10"]
            }
        )
        self.assertEqual(code, 200)
        self.assertTrue(res["success"])
        self.assertEqual(res["count"], 1)
        item = res["events"][0]
        self.assertTrue(item["pii_redacted"])
        self.assertEqual(item["client_ip"], "192.168.10.0/24")
        self.assertTrue(item["device_id"].startswith("dev_"))


if __name__ == "__main__":
    unittest.main()
