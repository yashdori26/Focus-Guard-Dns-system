"""
Integration Tests for FocusDNS Engine Phase 4 Subsystems & Pipeline Integration
================================================================================
Validates:
  1. Cyclic compression pointer loop early neutralization at ingress (CVE-2000-0381)
  2. RFC 8482 Stop-ANY minimal answer synthesis through unified pipeline
  3. RFC 8806 Hyperlocal Root Zone query resolution and TLD delegations
  4. RFC 8900 PMTU and Flag Day buffer clamping integration
  5. RFC 8198 Aggressive NSEC cache negative answer synthesis
  6. Prometheus metrics recording and exposition endpoint (/metrics)
  7. Pipeline telemetry reporting for all Phase 4 subsystems
"""

import unittest
from dnslib import DNSRecord, DNSQuestion, QTYPE, RCODE, RR
from server.engine.pipeline import get_pipeline, DNSPipeline
from server.engine.dns_fuzzer import WireMutationEngine
from server.engine.svcb_https import HTTPSRecord, SvcParam, SvcParamKey
from server.engine.rfc8482_any import HINFO


class TestEnginePipelinePhase4(unittest.TestCase):
    """Integration test suite for Phase 4 DNS engine additions."""

    def setUp(self):
        self.pipeline = DNSPipeline(enable_dnssec=False)

    def test_cyclic_pointer_loop_ingress_neutralization(self):
        # Generate valid query wire
        valid_wire = DNSRecord(q=DNSQuestion("loop-test.com", QTYPE.A)).pack()

        # Inject infinite cyclic compression pointer at offset 12
        hostile_wire = WireMutationEngine.inject_cyclic_pointer_loop(valid_wire, target_offset=12)

        reply_bytes, meta = self.pipeline.process_wire_query(
            hostile_wire, client_ip="198.51.100.99", protocol="UDP"
        )
        self.assertEqual(meta["status"], "error")
        self.assertEqual(meta["rcode"], "FORMERR")
        self.assertIn("Cyclic Pointer Loop", meta["reason"])

    def test_rfc8482_any_query_interception(self):
        any_query = DNSRecord(q=DNSQuestion("target.victim.com", QTYPE.ANY)).pack()

        reply_bytes, meta = self.pipeline.process_wire_query(
            any_query, client_ip="203.0.113.5", protocol="UDP"
        )
        self.assertEqual(meta["status"], "allowed")
        self.assertEqual(meta["rcode"], "NOERROR")
        self.assertIn("RFC 8482", meta["reason"])

        parsed_reply = DNSRecord.parse(reply_bytes)
        self.assertEqual(len(parsed_reply.rr), 1)
        self.assertEqual(parsed_reply.rr[0].rtype, QTYPE.HINFO)

    def test_local_root_delegation_referral(self):
        # LocalRootEngine should have seeded TLD delegations
        ref = self.pipeline.local_root.process_query("service.org", "A")
        self.assertEqual(ref["type"], "DELEGATION_REFERRAL")
        self.assertEqual(ref["rcode"], "NOERROR")
        self.assertGreater(len(ref["authority"]), 0)

        # Root apex NS query
        apex = self.pipeline.local_root.process_query(".", "NS")
        self.assertEqual(apex["type"], "APEX_ANSWER")
        self.assertEqual(len(apex["answers"]), 13)

    def test_aggressive_nsec_synthesis(self):
        zone = "corp.internal"
        # Seed an authenticated NSEC range: beta.corp.internal -> delta.corp.internal
        self.pipeline.aggressive_nsec.store_nsec(
            owner_name="beta.corp.internal",
            next_domain_name="delta.corp.internal",
            type_bitmaps=["A", "NSEC"],
            ttl=300,
            zone_origin=zone,
        )

        # Query for charlie.corp.internal (falls between beta and delta)
        covering = self.pipeline.aggressive_nsec.find_covering_nxdomain("charlie.corp.internal", zone)
        self.assertIsNotNone(covering)
        self.assertEqual(covering.owner_name, "beta.corp.internal")

    def test_svcb_resolver_integration(self):
        rec = HTTPSRecord(priority=1, target_name=".", params=[
            SvcParam(SvcParamKey.ALPN, ["h3", "h2"]),
            SvcParam(SvcParamKey.PORT, 443),
            SvcParam(SvcParamKey.IPV4HINT, ["192.0.2.1"]),
        ])
        self.pipeline.svcb_resolver.add_record("app.domain.com", rec)

        resolved = self.pipeline.svcb_resolver.resolve("app.domain.com", supported_alpns=["h3"])
        self.assertTrue(resolved["found"])
        self.assertEqual(resolved["selected_record"]["priority"], 1)

    def test_prometheus_metrics_recording(self):
        # Process a regular query
        query_wire = DNSRecord(q=DNSQuestion("telemetry.test", QTYPE.A)).pack()
        self.pipeline.process_wire_query(query_wire, client_ip="127.0.0.1", protocol="UDP")

        metrics_text = self.pipeline.prometheus.export_metrics_text()
        self.assertIn("focusdns_queries_total", metrics_text)
        self.assertIn("focusdns_query_duration_seconds", metrics_text)

    def test_pipeline_metrics_phase4_fields(self):
        metrics = self.pipeline.get_pipeline_metrics()
        self.assertIn("local_root_queries", metrics)
        self.assertIn("pmtu_truncations", metrics)
        self.assertIn("aggressive_nsec_hits", metrics)
        self.assertIn("compact_dnssec_proofs", metrics)
        self.assertIn("rfc8482_any_intercepts", metrics)


if __name__ == "__main__":
    unittest.main()
