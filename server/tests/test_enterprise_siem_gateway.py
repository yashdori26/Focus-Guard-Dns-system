"""
Unit tests for FocusDNS Enterprise Inbound SIEM Ingestion & Webhook Gateway.
"""

import hashlib
import hmac
import json
import time
import unittest

from server.enterprise.siem_ingest_gateway import (
    SiemIngestGateway,
    SiemIngestAlert,
    SiemVendorType,
    CRITICAL_LIFE_SAFETY_DOMAINS
)
from server.enterprise.soar_playbook_engine import (
    SoarPlaybookEngine,
    SoarIncident
)
from server.enterprise.tenant_manager import TenantManager
from server.enterprise.fleet_websocket_server import FleetWebSocketServer
from server.enterprise.api_enterprise_router import EnterpriseApiDispatcher


class TestSiemIngestGateway(unittest.TestCase):

    def setUp(self):
        self.tenants = TenantManager(db_path=":memory:")
        self.ws_server = FleetWebSocketServer()
        self.soar = SoarPlaybookEngine(ws_hub=self.ws_server)
        self.gateway = SiemIngestGateway(
            soar_engine=self.soar,
            tenant_mgr=self.tenants,
            dedup_window_seconds=10.0,
            auto_soar_threshold=70.0
        )
        # Register test secrets
        self.gateway.set_vendor_secret(SiemVendorType.SPLUNK, "test-splunk-secret")
        self.gateway.set_vendor_secret(SiemVendorType.DATADOG, "test-datadog-secret")
        self.gateway.set_vendor_secret(SiemVendorType.ELASTIC, "test-elastic-secret")

    def tearDown(self):
        self.ws_server.shutdown()


    def test_splunk_valid_bearer_token_ingest(self):
        payload = {
            "sid": "splunk_alert_1001",
            "search_name": "Phishing C2 Beacon",
            "result": {
                "src_ip": "10.0.4.15",
                "device_id": "win_workstation_7",
                "query": "malware-phish-portal.cc",
                "threat_category": "PHISHING",
                "urgency": "critical",
                "tenant_id": "org_cyber_corp"
            }
        }
        headers = {"Authorization": "Bearer test-splunk-secret"}
        ok, msg, alert = self.gateway.ingest_splunk_alert(payload, headers=headers)

        self.assertTrue(ok)
        self.assertIsNotNone(alert)
        self.assertEqual(alert.vendor, SiemVendorType.SPLUNK)
        self.assertEqual(alert.indicator_domain, "malware-phish-portal.cc")
        self.assertEqual(alert.risk_score, 95.0)
        self.assertFalse(alert.deduplicated)

    def test_splunk_invalid_token_fails(self):
        payload = {
            "sid": "splunk_alert_1002",
            "search_name": "Phishing C2 Beacon",
            "result": {"src_ip": "10.0.4.15", "query": "badsite.xyz"}
        }
        headers = {"Authorization": "Bearer WRONG_TOKEN"}
        ok, msg, alert = self.gateway.ingest_splunk_alert(payload, headers=headers)

        self.assertFalse(ok)
        self.assertIn("Invalid Splunk authentication token", msg)
        self.assertIsNone(alert)
        self.assertEqual(self.gateway.get_telemetry()["stats"]["invalid_signatures"], 1)

    def test_datadog_hmac_signature_ingest(self):
        payload = {
            "id": "dd_event_4421",
            "event_title": "DGA Malware Anomaly",
            "alert_type": "error",
            "tags": ["tenant:org_springfield", "device:macbook_lab_02", "ip:192.168.1.88"],
            "body": "Spike in suspicious DGA queries: xk9284lz789.biz",
            "domain": "xk9284lz789.biz"
        }
        body_bytes = json.dumps(payload).encode("utf-8")
        secret = "test-datadog-secret"
        sig = hmac.new(secret.encode("utf-8"), body_bytes, hashlib.sha256).hexdigest()
        headers = {"X-Datadog-Signature": sig}

        ok, msg, alert = self.gateway.ingest_datadog_alert(payload, headers=headers, raw_body=body_bytes)
        self.assertTrue(ok)
        self.assertIsNotNone(alert)
        self.assertEqual(alert.vendor, SiemVendorType.DATADOG)
        self.assertEqual(alert.indicator_domain, "xk9284lz789.biz")
        self.assertEqual(alert.device_id, "macbook_lab_02")
        self.assertEqual(alert.severity, "CRITICAL")

    def test_datadog_tampered_signature_rejected(self):
        payload = {"id": "dd_event_4422", "domain": "attack.com"}
        headers = {"X-Datadog-Signature": "invalid_hex_signature"}
        ok, msg, alert = self.gateway.ingest_datadog_alert(payload, headers=headers)
        self.assertFalse(ok)
        self.assertIn("Invalid Datadog webhook HMAC signature", msg)

    def test_elastic_ecs_alert_ingest(self):
        payload = {
            "kibana.alert.rule.id": "elastic_rule_99",
            "kibana.alert.rule.name": "DNS Tunneling Exfil",
            "source.ip": "172.16.0.40",
            "dns.question.name": "tunnel.dnscat.io",
            "event.severity": 4,
            "labels": {"tenant_id": "org_enterprise", "device_id": "dev_linux_edge"}
        }
        headers = {"X-Elastic-Secret": "test-elastic-secret"}
        ok, msg, alert = self.gateway.ingest_elastic_alert(payload, headers=headers)

        self.assertTrue(ok)
        self.assertIsNotNone(alert)
        self.assertEqual(alert.vendor, SiemVendorType.ELASTIC)
        self.assertEqual(alert.indicator_domain, "tunnel.dnscat.io")
        self.assertEqual(alert.risk_score, 95.0)

    def test_sliding_window_deduplication(self):
        payload = {
            "sid": "splunk_alert_dup_1",
            "search_name": "Repeated C2",
            "result": {
                "src_ip": "192.168.1.100",
                "device_id": "dev_user_1",
                "query": "c2-beacon-constant.org",
                "tenant_id": "org_test"
            }
        }
        headers = {"Authorization": "Bearer test-splunk-secret"}

        # 1st Ingestion: Not deduplicated
        ok1, msg1, alert1 = self.gateway.ingest_splunk_alert(payload, headers=headers)
        self.assertTrue(ok1)
        self.assertFalse(alert1.deduplicated)

        # 2nd Ingestion immediately: Deduplicated!
        ok2, msg2, alert2 = self.gateway.ingest_splunk_alert(payload, headers=headers)
        self.assertTrue(ok2)
        self.assertTrue(alert2.deduplicated)
        self.assertIn("deduplicated", msg2)
        self.assertEqual(self.gateway.get_telemetry()["stats"]["total_deduplicated"], 1)

    def test_life_safety_exemption_inviolable_guard(self):
        """
        External SIEM alert targeting critical life safety domains (911.gov, update.microsoft.com)
        MUST be ingested but strictly neutralized from automated quarantine/blocking!
        """
        for critical_domain in ("911.gov", "update.microsoft.com", "push.apple.com"):
            payload = {
                "sid": f"splunk_alert_safe_{critical_domain}",
                "search_name": "False Positive Spike",
                "result": {
                    "src_ip": "10.0.1.5",
                    "device_id": "dev_admin_pc",
                    "query": critical_domain,
                    "tenant_id": "org_safe",
                    "urgency": "critical"
                }
            }
            headers = {"Authorization": "Bearer test-splunk-secret"}
            ok, msg, alert = self.gateway.ingest_splunk_alert(payload, headers=headers)

            self.assertTrue(ok)
            self.assertIn("Life Safety Exemption protected", msg)
            # Ensure device was NOT quarantined
            self.assertFalse(self.soar.is_device_quarantined("dev_admin_pc"))

        self.assertEqual(self.gateway.get_telemetry()["stats"]["life_safety_neutralized"], 3)

    def test_api_dispatcher_webhook_integration(self):
        dispatcher = EnterpriseApiDispatcher(
            tenants=self.tenants,
            ws_hub=self.ws_server,
            soar=self.soar,
            siem_gateway=self.gateway
        )

        splunk_payload = {
            "sid": "api_splunk_1",
            "search_name": "API Alert",
            "result": {
                "src_ip": "192.168.50.2",
                "device_id": "dev_api_test",
                "query": "phishing-api.net",
                "tenant_id": "org_api"
            }
        }
        headers = {"Authorization": "Bearer test-splunk-secret"}

        code, res = dispatcher.handle_post(
            "/api/v1/enterprise/siem/webhook/splunk",
            payload=splunk_payload,
            headers=headers
        )
        self.assertEqual(code, 200)
        self.assertTrue(res["success"])
        self.assertIsNotNone(res["alert"])

        # Query recent alerts endpoint
        g_code, g_res = dispatcher.handle_get(
            "/api/v1/enterprise/siem/alerts",
            params={"limit": ["10"]}
        )
        self.assertEqual(g_code, 200)
        self.assertGreaterEqual(g_res["count"], 1)

        # Query telemetry endpoint
        t_code, t_res = dispatcher.handle_get(
            "/api/v1/enterprise/siem/telemetry",
            params={}
        )
        self.assertEqual(t_code, 200)
        self.assertIn("stats", t_res["telemetry"])


if __name__ == "__main__":
    unittest.main()
