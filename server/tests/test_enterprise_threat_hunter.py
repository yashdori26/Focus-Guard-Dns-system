"""
Unit tests for FocusDNS Enterprise Threat Hunter & Forensic Query Engine.
"""

import time
import unittest

from server.enterprise.columnar_analytics import (
    ColumnarAnalyticsEngine,
    DnsQueryEvent
)
from server.enterprise.threat_hunter import (
    ThreatHunter,
    ThreatHuntQuery,
    calculate_shannon_entropy,
    calculate_vowel_ratio,
    is_dga_candidate
)
from server.enterprise.tenant_manager import TenantManager
from server.enterprise.api_enterprise_router import EnterpriseApiDispatcher


class TestEnterpriseThreatHunter(unittest.TestCase):

    def setUp(self):
        self.analytics = ColumnarAnalyticsEngine(use_duckdb=False)
        self.tenants = TenantManager(db_path=":memory:")
        self.hunter = ThreatHunter(columnar_engine=self.analytics, tenant_mgr=self.tenants)

        # Populate sample events for tenant 'org_acme'
        self.tenant_id = "org_acme"
        now_us = int(time.time() * 1_000_000)

        events = [
            DnsQueryEvent(
                timestamp_us=now_us - 100_000_000,
                tenant_id=self.tenant_id,
                sub_tenant_id="unit_finance",
                device_id="laptop_alice",
                client_ip="10.200.1.15",
                domain="portal.acme-corp.com",
                qtype="A",
                rcode=0,
                action="ALLOW",
                threat_type="NONE",
                category="Corporate",
                latency_us=1200,
                bytes_transferred=64
            ),
            DnsQueryEvent(
                timestamp_us=now_us - 80_000_000,
                tenant_id=self.tenant_id,
                sub_tenant_id="unit_finance",
                device_id="laptop_alice",
                client_ip="10.200.1.15",
                domain="bcdfghjklmnpqrstvwxyz.org",
                qtype="A",
                rcode=0,
                action="BLOCK",
                threat_type="DGA_MALWARE",
                category="Malware",
                latency_us=1800,
                bytes_transferred=128
            ),
            DnsQueryEvent(
                timestamp_us=now_us - 60_000_000,
                tenant_id=self.tenant_id,
                sub_tenant_id="unit_engineering",
                device_id="dev_bob_linux",
                client_ip="10.200.5.42",
                domain="crypto-phish-steal.top",
                qtype="A",
                rcode=0,
                action="BLOCK",
                threat_type="PHISHING",
                category="Phishing",
                latency_us=1400,
                bytes_transferred=80
            ),
            DnsQueryEvent(
                timestamp_us=now_us - 40_000_000,
                tenant_id=self.tenant_id,
                sub_tenant_id="unit_engineering",
                device_id="dev_guest_phone",
                client_ip="192.168.1.50",
                domain="xn--pple-43d.com",
                qtype="A",
                rcode=0,
                action="BLOCK",
                threat_type="HOMOGRAPH",
                category="Typosquatting",
                latency_us=1100,
                bytes_transferred=72
            ),
            DnsQueryEvent(
                timestamp_us=now_us - 20_000_000,
                tenant_id="other_tenant",
                sub_tenant_id="unit_other",
                device_id="dev_external",
                client_ip="10.200.9.99",
                domain="isolated-domain.org",
                qtype="A",
                rcode=0,
                action="ALLOW",
                threat_type="NONE",
                category="General",
                latency_us=1000,
                bytes_transferred=50
            ),
        ]
        self.analytics.backend.insert_batch(events)

    def test_shannon_entropy_calculation(self):
        # Benign common domains have low entropy
        e_google = calculate_shannon_entropy("google.com")
        self.assertLess(e_google, 2.5)

        # High entropy random character distribution
        e_dga = calculate_shannon_entropy("abcdefghijklmnopqrstuvwxyz.biz")
        self.assertGreater(e_dga, 4.0)

    def test_vowel_ratio_and_dga_candidate(self):
        # Benign word has natural vowel ratio ~0.40
        self.assertFalse(is_dga_candidate("wikipedia.org"))

        # Consonant-dense malware domain candidate
        self.assertTrue(is_dga_candidate("bcdfghjklmnpqrstvwxyz.org"))

    def test_cidr_subnet_filter(self):
        # Search for queries only in the 10.200.0.0/16 private subnet for org_acme
        query = ThreatHuntQuery(
            tenant_id=self.tenant_id,
            cidr_subnet="10.200.0.0/16"
        )
        res = self.hunter.execute_hunt(query)

        self.assertEqual(res.matched_records[0]["tenant_id"], self.tenant_id)
        # 192.168.1.50 and other_tenant records must not be returned
        for rec in res.matched_records:
            self.assertTrue(rec["client_ip"].startswith("10.200."))
        self.assertEqual(len(res.matched_records), 3)

    def test_domain_regex_filter(self):
        # Search for .top TLDs
        query = ThreatHuntQuery(
            tenant_id=self.tenant_id,
            domain_pattern=r".*\.top$"
        )
        res = self.hunter.execute_hunt(query)

        self.assertEqual(len(res.matched_records), 1)
        self.assertEqual(res.matched_records[0]["domain"], "crypto-phish-steal.top")

    def test_min_entropy_filter(self):
        # Only fetch queries with Shannon entropy >= 3.5
        query = ThreatHuntQuery(
            tenant_id=self.tenant_id,
            min_entropy=3.5
        )
        res = self.hunter.execute_hunt(query)

        self.assertGreaterEqual(len(res.matched_records), 1)
        for rec in res.matched_records:
            self.assertGreaterEqual(rec["shannon_entropy"], 3.5)

    def test_ioc_batch_scan(self):
        iocs = [
            {"indicator": "bcdfghjklmnpqrstvwxyz.org", "type": "DOMAIN"},
            {"indicator": "192.168.1.50", "type": "IPV4"},
            {"indicator": "clean-never-queried.net", "type": "DOMAIN"}
        ]
        hits = self.hunter.scan_ioc_batch(self.tenant_id, iocs)

        self.assertEqual(len(hits), 2)
        matched_indicators = {h["matched_ioc"] for h in hits}
        self.assertIn("bcdfghjklmnpqrstvwxyz.org", matched_indicators)
        self.assertIn("192.168.1.50", matched_indicators)

    def test_device_timeline_and_beacon_detection(self):
        # Insert 6 periodic queries spaced precisely 10 seconds apart to simulate C2 beacon
        now_us = int(time.time() * 1_000_000)
        beacon_events = []
        for i in range(6):
            ts = now_us - ((6 - i) * 10 * 1_000_000)
            beacon_events.append(
                DnsQueryEvent(
                    timestamp_us=ts,
                    tenant_id="org_timeline_test",
                    sub_tenant_id="unit_1",
                    device_id="compromised_host_1",
                    client_ip="10.10.10.5",
                    domain="c2-heartbeat.badnetwork.cc",
                    qtype="A",
                    rcode=0,
                    action="ALLOW",
                    threat_type="NONE",
                    category="General",
                    latency_us=900,
                    bytes_transferred=40
                )
            )
        self.analytics.backend.insert_batch(beacon_events)

        timeline = self.hunter.reconstruct_device_timeline(
            tenant_id="org_timeline_test",
            device_id="compromised_host_1",
            window_minutes=60
        )

        self.assertEqual(timeline["total_queries_recorded"], 6)
        self.assertGreaterEqual(len(timeline["suspected_beacons"]), 1)
        beacon = timeline["suspected_beacons"][0]
        self.assertEqual(beacon["domain"], "c2-heartbeat.badnetwork.cc")
        self.assertAlmostEqual(beacon["avg_interval_seconds"], 10.0, places=1)
        self.assertLess(beacon["jitter_ratio"], 0.1)

    def test_api_dispatcher_threat_hunter_endpoints(self):
        dispatcher = EnterpriseApiDispatcher(
            analytics=self.analytics,
            threat_hunter=self.hunter
        )

        # POST /api/v1/enterprise/threat-hunter/query
        post_payload = {
            "tenant_id": self.tenant_id,
            "cidr_subnet": "10.200.0.0/16",
            "limit": 50
        }
        code, res = dispatcher.handle_post(
            "/api/v1/enterprise/threat-hunter/query",
            payload=post_payload
        )
        self.assertEqual(code, 200)
        self.assertTrue(res["success"])
        self.assertIn("records", res["result"])
        self.assertGreaterEqual(res["result"]["total_matches"], 1)

        # POST /api/v1/enterprise/threat-hunter/ioc-scan
        ioc_payload = {
            "tenant_id": self.tenant_id,
            "iocs": [{"indicator": "10.200.5.42", "type": "IPV4"}]
        }
        i_code, i_res = dispatcher.handle_post(
            "/api/v1/enterprise/threat-hunter/ioc-scan",
            payload=ioc_payload
        )
        self.assertEqual(i_code, 200)
        self.assertTrue(i_res["success"])
        self.assertEqual(i_res["hits_count"], 1)

        # GET /api/v1/enterprise/threat-hunter/timeline
        t_code, t_res = dispatcher.handle_get(
            "/api/v1/enterprise/threat-hunter/timeline",
            params={"tenant_id": [self.tenant_id], "device_id": ["laptop_alice"]}
        )
        self.assertEqual(t_code, 200)
        self.assertTrue(t_res["success"])
        self.assertEqual(t_res["timeline"]["device_id"], "laptop_alice")


if __name__ == "__main__":
    unittest.main()
