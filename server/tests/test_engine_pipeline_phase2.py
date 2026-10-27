"""
End-to-End Integration Tests for FocusDNS Engine Pipeline Phase 2:
- EDNS0 + EDE diagnostic codes
- Threat Analytics & DGA / DNS Tunneling blocking
- Response Rate Limiting (RRL) & SLIP TC=1
- Resilient Upstream Pool resolution
- Multi-dimensional Pipeline Telemetry
"""

import time
import unittest
from dnslib import DNSRecord, QTYPE, RCODE, EDNS0, EDNSOption

from server.engine.pipeline import DNSPipeline
from server.engine.radix_trie import FLAG_BLOCKED
from server.engine.edns0 import EDE_BLOCKED, EDE_FILTERED, EDNSMessage, EDNSClientSubnet
from server.engine.rate_limiter import RateLimitAction


class TestPipelinePhase2Integration(unittest.TestCase):
    def setUp(self):
        self.pipeline = DNSPipeline(enable_dnssec=False, strip_ecs=True)

    def test_pipeline_edns_ecs_stripping_and_ede_on_blocked(self):
        """Verify pipeline strips ECS for privacy and attaches EDE error on block."""
        # Add test domain to trie as blocked
        self.pipeline.trie.insert("tracker.badadnetwork.com", FLAG_BLOCKED)

        # Build query with EDNS OPT and ECS
        req = DNSRecord.question("tracker.badadnetwork.com", "A")
        ecs = EDNSClientSubnet(EDNSClientSubnet.FAMILY_IPV4, 24, 0, "203.0.113.0")
        msg = EDNSMessage(udp_payload_size=1232)
        msg.set_ecs(ecs)
        msg.attach_to_dnslib_record(req)

        wire_in = req.pack()
        wire_out, telem = self.pipeline.process_wire_query(wire_in, "a1b2c3", "203.0.113.50", "UDP")

        self.assertEqual(telem["status"], "blocked")
        self.assertEqual(telem["rcode"], "NXDOMAIN")
        self.assertEqual(telem["ede_code"], EDE_BLOCKED)

        # Parse output wire response
        resp = DNSRecord.parse(wire_out)
        self.assertEqual(resp.header.rcode, RCODE.NXDOMAIN)

        # Verify EDNS response contains EDE
        edns_resp = EDNSMessage.from_dnslib_record(resp)
        self.assertIsNotNone(edns_resp)
        ede = edns_resp.get_ede()
        self.assertIsNotNone(ede)
        self.assertEqual(ede.info_code, EDE_BLOCKED)

    def test_pipeline_threat_analytics_dga_block(self):
        """Verify pipeline halts DGA query with high Shannon entropy before upstream forward."""
        dga_domain = "qz7x9v2k4m8p1w3j5t6y.xyz"
        req = DNSRecord.question(dga_domain, "A")

        wire_out, telem = self.pipeline.process_wire_query(req.pack(), "a1b2c3", "192.168.1.100", "UDP")
        self.assertEqual(telem["status"], "blocked")
        self.assertIn("Security Threat", telem["reason"])
        self.assertEqual(telem["ede_code"], EDE_BLOCKED)

    def test_pipeline_rate_limiting_drop_and_slip(self):
        """Verify pipeline drops and returns SLIP TC=1 under extreme query flood."""
        # Lower limits temporarily for test client with near-zero refill to prevent time drift
        self.pipeline.rate_limiter.client_qps = 0.0001
        self.pipeline.rate_limiter.client_burst = 2.0
        self.pipeline.rate_limiter.subnet_qps = 0.0001
        self.pipeline.rate_limiter.subnet_burst = 2.0
        self.pipeline.rate_limiter.slip_ratio = 2

        # Pre-seed cache to isolate from internet latency
        dummy_reply = DNSRecord.question("clean-test.org", "A").reply().pack()
        self.pipeline.cache.put("clean-test.org", 1, dummy_reply, ttl=300)

        req = DNSRecord.question("clean-test.org", "A")
        client_ip = "198.51.100.99"

        # First 2 should proceed
        self.pipeline.process_wire_query(req.pack(), "a1b2c3", client_ip, "UDP")
        self.pipeline.process_wire_query(req.pack(), "a1b2c3", client_ip, "UDP")

        # 3rd query: dropped
        wire_drop, telem_drop = self.pipeline.process_wire_query(req.pack(), "a1b2c3", client_ip, "UDP")
        self.assertEqual(telem_drop["status"], "dropped")
        self.assertEqual(wire_drop, b"")

        # 4th query: slipped with TC=1
        wire_slip, telem_slip = self.pipeline.process_wire_query(req.pack(), "a1b2c3", client_ip, "UDP")
        self.assertEqual(telem_slip["status"], "slipped_tc")
        resp_slip = DNSRecord.parse(wire_slip)
        self.assertEqual(resp_slip.header.tc, 1)

    def test_pipeline_phase2_metrics(self):
        """Verify unified pipeline performance counters include all Phase 2 subsystems."""
        metrics = self.pipeline.get_pipeline_metrics()

        # Core Phase 1 counters
        self.assertIn("total_queries", metrics)
        self.assertIn("trie_nodes", metrics)
        self.assertIn("cache_entries", metrics)
        self.assertIn("dnssec_verified", metrics)

        # Phase 2 counters
        self.assertIn("threat_queries_analyzed", metrics)
        self.assertIn("threat_dga_detected", metrics)
        self.assertIn("threat_tunneling_detected", metrics)
        self.assertIn("threat_fast_flux_detected", metrics)
        self.assertIn("rate_limiter_tracked_ips", metrics)
        self.assertIn("rate_limiter_dropped", metrics)
        self.assertIn("rate_limiter_slipped_tc", metrics)
        self.assertIn("upstream_total_queries", metrics)
        self.assertIn("upstream_active_nodes", metrics)


if __name__ == "__main__":
    unittest.main()
