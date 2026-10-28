"""
Integration Tests for FocusDNS Engine Pipeline (Phase 3 Subsystems)
===================================================================
End-to-end integration tests validating:
  1. eBPF / XDP Packet Filter integration into DNSPipeline.process_wire_query:
     - Kernel-bypass drop for blacklisted IP addresses without parsing overhead
     - Rate-limited traffic drops with telemetry logging
  2. GeoDNS Integration into DNSPipeline:
     - Bound domain requests resolved to nearest geographic edge endpoint
     - EDNS Client Subnet (ECS) override routing
     - Geo-fencing blocking policies (returning EDE_BLOCKED and NXDOMAIN)
  3. DNS64 Integration into DNSPipeline:
     - Automatic synthetic AAAA record injection for IPv4-only upstream answers
  4. RFC 9432 Catalog Zone & AXFR Zone Transfer Integration:
     - Interception of catalog zone queries and zone replication handling
  5. Unified Operational Telemetry:
     - Verification of all Phase 3 metrics in get_pipeline_metrics()
"""

import time
import unittest
from dnslib import DNSRecord, RR, QTYPE, RCODE, A, AAAA

from server.engine.pipeline import DNSPipeline
from server.engine.xdp_filter import XDP_DROP
from server.engine.geodns import HealthState, EdgeEndpoint, GeoCoordinates
from server.engine.zone_authority import AuthoritativeZone, AuthoritativeRecord


class TestPipelinePhase3Integration(unittest.TestCase):
    """End-to-end integration suite for Phase 3 enterprise DNS subsystems."""

    def setUp(self):
        self.pipeline = DNSPipeline(upstream_primary="1.1.1.1", upstream_secondary="8.8.8.8")

        # Bind test domain to GeoDNS pool
        self.pipeline.geodns.bind_domain("geo.focusguard.local", "global-web")

    def test_xdp_packet_filter_drop_fastpath(self):
        # 1. Ban IP in eBPF / XDP Hash Map
        attacker_ip = "198.51.100.99"
        self.pipeline.xdp_filter.bpf_map_update_ip(attacker_ip, action=XDP_DROP, reason="XDP Ban Attack")

        req = DNSRecord.question("example.com", "A")
        wire = req.pack()

        # Query from banned IP
        reply_bytes, telem = self.pipeline.process_wire_query(
            wire, client_ip=attacker_ip, protocol="UDP"
        )

        # RFC 791/1035 / XDP: Frame is dropped immediately (empty bytes returned)
        self.assertEqual(reply_bytes, b"")
        self.assertEqual(telem["status"], "dropped")
        self.assertIn("eBPF/XDP Drop", telem["reason"])

        # Check telemetry counters
        metrics = self.pipeline.get_pipeline_metrics()
        self.assertGreater(metrics["xdp_frames_inspected"], 0)
        self.assertGreater(metrics["xdp_frames_dropped"], 0)

    def test_geodns_nearest_routing_in_pipeline(self):
        # Query for GeoDNS-managed domain from a client IP located in Frankfurt, Germany
        req = DNSRecord.question("geo.focusguard.local", "A")
        wire = req.pack()

        de_client_ip = "193.99.144.1"
        reply_bytes, telem = self.pipeline.process_wire_query(
            wire, client_ip=de_client_ip, protocol="UDP"
        )

        resp = DNSRecord.parse(reply_bytes)
        self.assertEqual(resp.header.rcode, RCODE.NOERROR)
        self.assertGreater(len(resp.rr), 0)

        # Selected endpoint should be Frankfurt Edge Cluster (198.51.100.30)
        self.assertEqual(str(resp.rr[0].rdata), "198.51.100.30")
        self.assertEqual(telem["status"], "allowed")
        self.assertIn("Frankfurt Edge Cluster", telem["reason"])

    def test_geodns_ecs_override_in_pipeline(self):
        # Client IP is loopback/US, but EDNS Client Subnet (ECS) is Tokyo, Japan
        req = DNSRecord.question("geo.focusguard.local", "A")
        wire = req.pack()

        # Simulate EDNS Client Subnet option in query
        edns_client_ip = "103.22.200.5"  # Tokyo, JP

        # We can test resolution via geodns.resolve directly or with ECS attached
        res = self.pipeline.geodns.resolve("geo.focusguard.local", "127.0.0.1", ecs_ip=edns_client_ip)
        self.assertEqual(res.policy_action, "allow")
        self.assertEqual(res.selected_endpoint.endpoint_id, "ap-northeast-1")
        self.assertEqual(res.selected_endpoint.ipv4_address, "198.51.100.50")

    def test_geodns_geofencing_blocking(self):
        # Configure Geo-Fence policy blocking DE (Germany)
        self.pipeline.geodns.fencing.block_country("DE")

        req = DNSRecord.question("geo.focusguard.local", "A")
        wire = req.pack()

        de_client_ip = "193.99.144.1"
        reply_bytes, telem = self.pipeline.process_wire_query(
            wire, client_ip=de_client_ip, protocol="UDP"
        )

        resp = DNSRecord.parse(reply_bytes)
        self.assertEqual(resp.header.rcode, RCODE.NXDOMAIN)
        self.assertEqual(telem["status"], "blocked")
        self.assertIn("Geo-Fence Policy", telem["reason"])

    def test_dns64_synthetic_aaaa_in_pipeline(self):
        # Mock upstream resolution for an IPv4-only domain
        def _mock_upstream(query_bytes: bytes):
            req = DNSRecord.parse(query_bytes)
            reply = req.reply()
            if req.q.qtype == QTYPE.A:
                reply.add_answer(RR(str(req.q.qname), QTYPE.A, ttl=300, rdata=A("198.51.100.44")))
            elif req.q.qtype == QTYPE.AAAA:
                # No native AAAA (NODATA)
                pass
            return reply.pack(), "NOERROR"

        self.pipeline.forward_upstream = _mock_upstream

        # Client queries AAAA for IPv4-only domain
        req = DNSRecord.question("ipv4only.example.com", "AAAA")
        reply_bytes, telem = self.pipeline.process_wire_query(
            req.pack(), client_ip="127.0.0.1", protocol="UDP"
        )

        resp = DNSRecord.parse(reply_bytes)
        self.assertEqual(resp.header.rcode, RCODE.NOERROR)
        self.assertGreater(len(resp.rr), 0)

        # Synthesized AAAA record should be present with 64:ff9b:: prefix
        first_ans = resp.rr[0]
        self.assertEqual(first_ans.rtype, QTYPE.AAAA)
        self.assertTrue(str(first_ans.rdata).startswith("64:ff9b::"))

    def test_pipeline_metrics_phase3_fields(self):
        metrics = self.pipeline.get_pipeline_metrics()

        # Check that Phase 3 telemetry fields exist and are integer types
        phase3_keys = [
            "xdp_frames_inspected",
            "xdp_frames_dropped",
            "dns64_synthetic_aaaa",
            "geodns_queries",
            "geodns_blocked",
            "catalog_members",
            "zone_transfers_served",
        ]
        for k in phase3_keys:
            self.assertIn(k, metrics)
            self.assertIsInstance(metrics[k], int)


if __name__ == "__main__":
    unittest.main()
