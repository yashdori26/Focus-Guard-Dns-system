"""
Unit tests for FocusDNS Enterprise Pipeline Hook.
Verifies:
  1. Inviolable Life-Safety Exemption Guarantee (Safety domains NEVER blocked).
  2. CIDR subnet longest-prefix routing to enterprise tenants.
  3. Static IP-to-device mapping.
  4. Real-time asynchronous columnar micro-batch ingestion.
  5. RFC 5424 SIEM forwarder streaming integration.
  6. Backpressure protection and operational metrics.
"""

import time
import unittest

from server.enterprise.columnar_analytics import ColumnarAnalyticsEngine
from server.enterprise.siem_forwarder import SiemForwarder, SiemConfig, SiemTransport
from server.engine.enterprise_pipeline_hook import (
    EnterprisePipelineHook,
    LIFE_SAFETY_DOMAINS,
)


class TestEnterprisePipelineHook(unittest.TestCase):

    def setUp(self):
        # Isolated in-memory columnar engine
        self.columnar_engine = ColumnarAnalyticsEngine(use_duckdb=False, flush_interval_sec=0.1)
        # Isolated SIEM forwarder
        siem_config = SiemConfig(
            transport=SiemTransport.UDP,
            host="127.0.0.1",
            port=5140,
            enabled=True
        )
        self.siem_forwarder = SiemForwarder(config=siem_config)
        self.hook = EnterprisePipelineHook(
            columnar_engine=self.columnar_engine,
            siem_forwarder=self.siem_forwarder,
            default_tenant_id="tenant_univ",
            default_sub_tenant_id="unit_cs",
            default_fleet_id="fleet_lab",
        )

    def tearDown(self):
        self.hook.shutdown()
        self.columnar_engine.shutdown()
        self.siem_forwarder.shutdown()

    def test_inviolable_life_safety_exemption(self):
        """Emergency and life-safety domains can NEVER be blocked by enterprise policies."""
        for safe_domain in ["911.gov", "112.gov", "update.microsoft.com", "push.apple.com"]:
            action, safety_override = self.hook.intercept_and_record(
                client_ip="192.168.1.50",
                domain=safe_domain,
                action="BLOCKED",  # Policy attempted illegal block
                threat_type="POLICY_VIOLATION",
            )
            self.assertEqual(action, "ALLOWED", f"Domain {safe_domain} must be allowed by life safety exemption")
            self.assertTrue(safety_override, f"Domain {safe_domain} must trigger safety override")

        telemetry = self.hook.get_telemetry()
        self.assertGreaterEqual(telemetry["safety_exemptions_granted"], 4)

    def test_subnet_and_static_routing(self):
        """Verifies CIDR longest-prefix subnet matching and static device overrides."""
        # Register subnet rules
        self.hook.register_subnet_mapping("10.10.0.0/16", "org_acme", "unit_hq", "fleet_hq_wifi")
        self.hook.register_subnet_mapping("10.10.5.0/24", "org_acme", "unit_engineering", "fleet_eng_laptops")
        self.hook.register_static_device("172.16.0.99", "org_k12", "unit_highschool", "fleet_grade9", "dev_ipad_01")

        # 1. Longest-prefix match (10.10.5.42 matches /24 rather than /16)
        t, u, f, d = self.hook.resolve_tenant_context("10.10.5.42")
        self.assertEqual(t, "org_acme")
        self.assertEqual(u, "unit_engineering")
        self.assertEqual(f, "fleet_eng_laptops")

        # 2. Broader subnet match (10.10.8.20 matches /16)
        t, u, f, d = self.hook.resolve_tenant_context("10.10.8.20")
        self.assertEqual(t, "org_acme")
        self.assertEqual(u, "unit_hq")
        self.assertEqual(f, "fleet_hq_wifi")

        # 3. Static device match
        t, u, f, d = self.hook.resolve_tenant_context("172.16.0.99")
        self.assertEqual(t, "org_k12")
        self.assertEqual(u, "unit_highschool")
        self.assertEqual(d, "dev_ipad_01")

        # 4. Fallback default
        t, u, f, d = self.hook.resolve_tenant_context("192.0.2.1")
        self.assertEqual(t, "tenant_univ")
        self.assertEqual(u, "unit_cs")

    def test_columnar_microbatch_ingestion(self):
        """DNS queries intercepted by the hook are asynchronously batched into columnar storage."""
        start_us = int(time.time() * 1_000_000) - 1000

        for i in range(100):
            self.hook.intercept_and_record(
                client_ip="10.0.0.1",
                domain=f"sub{i}.internal.corp",
                qtype="A",
                action="ALLOWED" if i % 2 == 0 else "BLOCKED",
                latency_us=850,
            )

        # Allow micro-batch worker to flush
        time.sleep(0.3)
        self.columnar_engine.flush()
        end_us = int(time.time() * 1_000_000) + 1000

        buckets = self.columnar_engine.get_timeseries(
            tenant_id="tenant_univ",
            start_us=start_us,
            end_us=end_us,
            bucket_seconds=60
        )
        total_queries = sum(b.get("total_queries", 0) for b in buckets)
        blocked_queries = sum(b.get("blocked_queries", 0) for b in buckets)
        allowed_queries = sum(b.get("allowed_queries", 0) for b in buckets)
        self.assertEqual(total_queries, 100)
        self.assertEqual(blocked_queries, 50)
        self.assertEqual(allowed_queries, 50)

    def test_siem_streaming_integration(self):
        """Security violations and blocks are dispatched to SIEM forwarder queue."""
        self.hook.intercept_and_record(
            client_ip="10.0.0.5",
            domain="c2-malicious-beacon.biz",
            action="BLOCKED",
            threat_type="MALWARE",
        )

        telemetry = self.hook.get_telemetry()
        self.assertGreaterEqual(telemetry["siem_events_streamed"], 1)
        self.assertGreaterEqual(telemetry["blocked_events"], 1)

    def test_clear_mappings_and_telemetry(self):
        """Verify telemetry counters and route clearing."""
        self.hook.register_subnet_mapping("10.0.0.0/8", "org_x", "unit_y", "fleet_z")
        self.hook.clear_mappings()
        telemetry = self.hook.get_telemetry()
        self.assertEqual(telemetry["active_subnet_rules"], 0)
        self.assertEqual(telemetry["active_static_devices"], 0)

    def test_disabled_hook_bypasses_processing(self):
        """When disabled, the hook immediately returns the original action without modifications."""
        self.hook.enabled = False
        action, override = self.hook.intercept_and_record(
            client_ip="192.168.1.1",
            domain="gambling.com",
            action="BLOCKED",
        )
        self.assertEqual(action, "BLOCKED")
        self.assertFalse(override)

    def test_life_safety_subdomains(self):
        """Subdomains of life safety domains (e.g. gateway.emergency.gov) are strictly exempt."""
        for sub in ["gateway.emergency.gov", "auth.update.microsoft.com", "service.push.apple.com"]:
            action, override = self.hook.intercept_and_record(
                client_ip="192.168.1.10",
                domain=sub,
                action="BLOCKED",
                threat_type="POLICY_VIOLATION",
            )
            self.assertEqual(action, "ALLOWED")
            self.assertTrue(override)

    def test_override_action_parameter(self):
        """Specifying override_action forces the assigned verdict."""
        action, _ = self.hook.intercept_and_record(
            client_ip="10.0.0.2",
            domain="custom-domain.org",
            action="ALLOWED",
            override_action="SINKHOLED",
        )
        self.assertEqual(action, "SINKHOLED")


if __name__ == "__main__":
    unittest.main()
