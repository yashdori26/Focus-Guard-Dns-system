"""
Unit & Integration Tests for FocusDNS RFC 8618 Compact Denial of Existence Subsystem
====================================================================================
Validates:
  1. RFC 4034 Section 4.1.2 Type Bit Maps binary wire encoding and decoding
  2. On-the-fly minimal NSEC synthesis for NXDOMAIN answers
  3. On-the-fly minimal NSEC synthesis for NODATA answers
  4. Preventing NSEC zone walking and enumeration ("Black Lies")
  5. CompactDNSSECEngine response construction and telemetry
"""

import unittest
from dnslib import DNSRecord, DNSQuestion, QTYPE, RCODE, RR, SOA
from server.engine.compact_dnssec import (
    encode_type_bitmap,
    decode_type_bitmap,
    CompactDenialMode,
    CompactDNSSECSynthesizer,
    CompactDNSSECEngine,
)


class TestTypeBitmapCodec(unittest.TestCase):
    """Tests RFC 4034 Type Bit Maps binary codec."""

    def test_single_type_codec(self):
        encoded = encode_type_bitmap(["A"])
        # Window 0, length 1 byte, bit 1 set (0x40)
        self.assertEqual(encoded[0], 0)  # window 0
        self.assertEqual(encoded[1], 1)  # length 1
        self.assertEqual(encoded[2], 0x40)

        decoded = decode_type_bitmap(encoded)
        self.assertIn("A", decoded)

    def test_multi_type_roundtrip(self):
        types = ["A", "AAAA", "MX", "TXT", "RRSIG", "NSEC", "HTTPS"]
        encoded = encode_type_bitmap(types)
        decoded = decode_type_bitmap(encoded)
        for t in types:
            self.assertIn(t, decoded)


class TestCompactDNSSECSynthesizer(unittest.TestCase):
    """Tests on-the-fly NSEC generation for NXDOMAIN and NODATA."""

    def test_synthesize_nxdomain_nsec(self):
        nsec_rr = CompactDNSSECSynthesizer.synthesize_nxdomain_nsec("nosuchhost.example.com")
        self.assertEqual(str(nsec_rr.rname), "nosuchhost.example.com.")
        self.assertEqual(nsec_rr.rtype, QTYPE.NSEC)

        # Decodes types
        decoded = decode_type_bitmap(nsec_rr.rdata.data)
        self.assertIn("RRSIG", decoded)
        self.assertIn("NSEC", decoded)

    def test_synthesize_nodata_nsec(self):
        nsec_rr = CompactDNSSECSynthesizer.synthesize_nodata_nsec(
            "existing.example.com", existing_types=["A", "TXT"]
        )
        self.assertEqual(str(nsec_rr.rname), "existing.example.com.")
        self.assertEqual(nsec_rr.rtype, QTYPE.NSEC)

        decoded = decode_type_bitmap(nsec_rr.rdata.data)
        self.assertIn("A", decoded)
        self.assertIn("TXT", decoded)
        self.assertIn("RRSIG", decoded)
        self.assertIn("NSEC", decoded)
        # Queried type (e.g. AAAA) must NOT be present
        self.assertNotIn("AAAA", decoded)


class TestCompactDNSSECEngine(unittest.TestCase):
    """Tests RFC 8618 negative response generation and counters."""

    def setUp(self):
        self.engine = CompactDNSSECEngine()
        self.soa = RR("example.com", QTYPE.SOA, ttl=3600, rdata=SOA(
            mname="ns1.example.com.", rname="admin.example.com.", times=(1, 3600, 600, 86400, 300)
        ))

    def test_process_nxdomain_response(self):
        q = DNSRecord(q=DNSQuestion("missing.example.com", QTYPE.A))
        resp = self.engine.process_negative_response(
            query_msg=q, is_nxdomain=True, zone_origin="example.com", soa_rr=self.soa
        )
        self.assertEqual(resp.header.rcode, RCODE.NXDOMAIN)
        self.assertEqual(len(resp.rr), 0)  # No answers
        # Authority section must contain SOA and synthetic NSEC
        self.assertEqual(len(resp.auth), 2)
        self.assertEqual(resp.auth[0].rtype, QTYPE.SOA)
        self.assertEqual(resp.auth[1].rtype, QTYPE.NSEC)

        stats = self.engine.get_stats()
        self.assertEqual(stats["synthesized_nxdomain_count"], 1)
        self.assertEqual(stats["zone_walk_preventions"], 1)

    def test_process_nodata_response(self):
        q = DNSRecord(q=DNSQuestion("api.example.com", QTYPE.AAAA))
        resp = self.engine.process_negative_response(
            query_msg=q,
            is_nxdomain=False,
            existing_types=["A", "TXT"],
            zone_origin="example.com",
            soa_rr=self.soa,
        )
        self.assertEqual(resp.header.rcode, RCODE.NOERROR)
        self.assertEqual(len(resp.rr), 0)
        self.assertEqual(len(resp.auth), 2)
        self.assertEqual(resp.auth[1].rtype, QTYPE.NSEC)

        stats = self.engine.get_stats()
        self.assertEqual(stats["synthesized_nodata_count"], 1)


if __name__ == "__main__":
    unittest.main()
