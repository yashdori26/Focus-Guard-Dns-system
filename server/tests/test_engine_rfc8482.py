"""
Unit & Integration Tests for FocusDNS RFC 8482 Minimal ANY Query Subsystem
==========================================================================
Validates:
  1. RFC 8482 Section 4.1 standard HINFO "RFC8482" "" answer synthesis
  2. RFC 8482 Section 4.2 single arbitrary RRset fallback
  3. RCODE REFUSED enforcement mode
  4. Whitelisted management CIDR bypass and passthrough
  5. Interception and telemetry metric counters
"""

import unittest
from dnslib import DNSRecord, DNSQuestion, QTYPE, RCODE, SOA
from server.engine.rfc8482_any import (
    ANYResponseMode,
    RFC8482Policy,
    RFC8482Engine,
    HINFO,
)


class TestRFC8482Engine(unittest.TestCase):
    """Tests RFC 8482 ANY query interception and minimal synthesis."""

    def test_non_any_query_ignored(self):
        engine = RFC8482Engine()
        q = DNSRecord(q=DNSQuestion("example.com", QTYPE.A))
        self.assertFalse(engine.is_any_query(q))
        res = engine.process_query(q, client_ip="192.0.2.1")
        self.assertIsNone(res)

    def test_hinfo_standard_mode(self):
        policy = RFC8482Policy(mode=ANYResponseMode.HINFO_STANDARD)
        engine = RFC8482Engine(policy)

        q = DNSRecord(q=DNSQuestion("example.com", QTYPE.ANY))
        self.assertTrue(engine.is_any_query(q))

        resp = engine.process_query(q, client_ip="192.0.2.5")
        self.assertIsNotNone(resp)
        self.assertEqual(resp.header.rcode, RCODE.NOERROR)
        self.assertEqual(len(resp.rr), 1)

        hinfo_rr = resp.rr[0]
        self.assertEqual(hinfo_rr.rtype, QTYPE.HINFO)
        self.assertEqual(str(hinfo_rr.rdata.cpu), "RFC8482")

        stats = engine.get_stats()
        self.assertEqual(stats["total_any_queries_intercepted"], 1)
        self.assertEqual(stats["hinfo_synthesized"], 1)

    def test_refuse_mode(self):
        policy = RFC8482Policy(mode=ANYResponseMode.REFUSE)
        engine = RFC8482Engine(policy)

        q = DNSRecord(q=DNSQuestion("attack.victim.org", QTYPE.ANY))
        resp = engine.process_query(q, client_ip="203.0.113.10")
        self.assertIsNotNone(resp)
        self.assertEqual(resp.header.rcode, RCODE.REFUSED)
        self.assertEqual(len(resp.rr), 0)

        stats = engine.get_stats()
        self.assertEqual(stats["refused"], 1)

    def test_single_rrset_mode(self):
        policy = RFC8482Policy(mode=ANYResponseMode.SINGLE_RRSET)
        engine = RFC8482Engine(policy)
        soa = SOA("ns1.example.com.", "admin.example.com.", (1, 3600, 600, 86400, 300))

        q = DNSRecord(q=DNSQuestion("example.com", QTYPE.ANY))
        resp = engine.process_query(q, client_ip="192.0.2.1", zone_soa=soa)
        self.assertIsNotNone(resp)
        self.assertEqual(resp.header.rcode, RCODE.NOERROR)
        self.assertEqual(len(resp.rr), 1)
        self.assertEqual(resp.rr[0].rtype, QTYPE.SOA)

    def test_whitelisted_cidr_bypass(self):
        # Allow internal LAN 10.0.0.0/8 to receive full ANY responses
        policy = RFC8482Policy(
            mode=ANYResponseMode.HINFO_STANDARD,
            whitelisted_cidrs=["10.0.0.0/8"],
        )
        engine = RFC8482Engine(policy)

        q = DNSRecord(q=DNSQuestion("internal.corp", QTYPE.ANY))
        # Internal client -> passthrough (returns None)
        res_internal = engine.process_query(q, client_ip="10.50.1.20")
        self.assertIsNone(res_internal)

        # External client -> intercepted (returns HINFO)
        res_external = engine.process_query(q, client_ip="198.51.100.5")
        self.assertIsNotNone(res_external)

        stats = engine.get_stats()
        self.assertEqual(stats["total_any_queries_intercepted"], 2)
        self.assertEqual(stats["whitelisted_passthrough"], 1)
        self.assertEqual(stats["hinfo_synthesized"], 1)


if __name__ == "__main__":
    unittest.main()
