"""
Unit & Integration Tests for FocusDNS RFC 6052 & RFC 6147 DNS64 Subsystem
===========================================================================
Validates:
  1. RFC 6052 Well-Known Prefix (64:ff9b::/96) IPv4 embedding and bitwise extraction
  2. Variable Network-Specific Prefix (NSP) lengths (/32, /40, /48, /56, /64, /96)
  3. Verification of Octet 8 (bits 64-71) reserved zero byte (RFC 6052 §2.2)
  4. Reverse PTR synthesis translating *.ip6.arpa to *.in-addr.arpa
  5. RFC 6147 §5.1.4 IPv4 exclusion filter (loopback, private, broadcast, multicast)
  6. Synthetic AAAA record generation, TTL clamping, and telemetry counters
"""

import ipaddress
import unittest
from dnslib import DNSRecord, RR, QTYPE, RCODE, A, AAAA, PTR

from server.engine.dns64 import (
    DNS64Engine,
    DEFAULT_DNS64_PREFIX,
    embed_ipv4_in_ipv6,
    extract_ipv4_from_ipv6,
    reverse_ipv6_to_ipv4_ptr,
)


class TestRFC6052BitwiseEmbedding(unittest.TestCase):
    """Tests RFC 6052 bit-level byte stuffing across all supported prefix lengths."""

    def test_well_known_prefix_96(self):
        # RFC 6052 §2.1 example: 192.0.2.1 embedded in 64:ff9b::/96
        # 192 = 0xC0, 0 = 0x00, 2 = 0x02, 1 = 0x01 -> c000:0201
        ipv4 = "192.0.2.1"
        v6_str = embed_ipv4_in_ipv6(ipv4, "64:ff9b::/96")
        self.assertEqual(v6_str.lower(), "64:ff9b::c000:201")

        # Roundtrip extraction
        extracted = extract_ipv4_from_ipv6(v6_str, "64:ff9b::/96")
        self.assertEqual(extracted, ipv4)

    def test_prefix_length_64(self):
        # Prefix length /64: IPv4 is embedded in bytes 9..12, byte 8 MUST be 0x00
        prefix = "2001:db8:1:2::/64"
        ipv4 = "198.51.100.42"
        v6_str = embed_ipv4_in_ipv6(ipv4, prefix)

        # Inspect raw bytes
        ip6_bytes = ipaddress.IPv6Address(v6_str).packed
        self.assertEqual(ip6_bytes[8], 0x00, "RFC 6052 octet 8 (byte 8) must be 0x00")

        # Roundtrip extraction
        extracted = extract_ipv4_from_ipv6(v6_str, prefix)
        self.assertEqual(extracted, ipv4)

    def test_prefix_length_56(self):
        # Prefix length /56: byte 7 is v4[0], byte 8 is 0x00, bytes 9..11 are v4[1..3]
        prefix = "2001:db8:1:200::/56"
        ipv4 = "203.0.113.89"
        v6_str = embed_ipv4_in_ipv6(ipv4, prefix)

        ip6_bytes = ipaddress.IPv6Address(v6_str).packed
        self.assertEqual(ip6_bytes[8], 0x00, "RFC 6052 octet 8 must be 0x00")

        extracted = extract_ipv4_from_ipv6(v6_str, prefix)
        self.assertEqual(extracted, ipv4)

    def test_prefix_length_48(self):
        # Prefix length /48: bytes 6..7 are v4[0..1], byte 8 is 0x00, bytes 9..10 are v4[2..3]
        prefix = "2001:db8:1::/48"
        ipv4 = "192.0.2.128"
        v6_str = embed_ipv4_in_ipv6(ipv4, prefix)

        ip6_bytes = ipaddress.IPv6Address(v6_str).packed
        self.assertEqual(ip6_bytes[8], 0x00, "RFC 6052 octet 8 must be 0x00")

        extracted = extract_ipv4_from_ipv6(v6_str, prefix)
        self.assertEqual(extracted, ipv4)

    def test_prefix_length_40(self):
        # Prefix length /40: bytes 5..7 are v4[0..2], byte 8 is 0x00, byte 9 is v4[3]
        prefix = "2001:db8:100::/40"
        ipv4 = "198.51.100.1"
        v6_str = embed_ipv4_in_ipv6(ipv4, prefix)

        ip6_bytes = ipaddress.IPv6Address(v6_str).packed
        self.assertEqual(ip6_bytes[8], 0x00, "RFC 6052 octet 8 must be 0x00")

        extracted = extract_ipv4_from_ipv6(v6_str, prefix)
        self.assertEqual(extracted, ipv4)

    def test_prefix_length_32(self):
        # Prefix length /32: bytes 4..7 are v4[0..3], byte 8 is 0x00
        prefix = "2001:db8::/32"
        ipv4 = "192.0.2.33"
        v6_str = embed_ipv4_in_ipv6(ipv4, prefix)

        ip6_bytes = ipaddress.IPv6Address(v6_str).packed
        self.assertEqual(ip6_bytes[8], 0x00, "RFC 6052 octet 8 must be 0x00")

        extracted = extract_ipv4_from_ipv6(v6_str, prefix)
        self.assertEqual(extracted, ipv4)

    def test_extraction_mismatched_prefix_returns_none(self):
        # An IPv6 address that does not match the prefix should return None
        alien_ip = "2607:f8b0:4005:800::200e"
        extracted = extract_ipv4_from_ipv6(alien_ip, "64:ff9b::/96")
        self.assertIsNone(extracted)


class TestDNS64ReversePTR(unittest.TestCase):
    """Tests reverse *.ip6.arpa to *.in-addr.arpa mapping."""

    def test_reverse_ip6_arpa_translation(self):
        # 192.0.2.1 embedded into 64:ff9b::/96 is 64:ff9b::c000:201
        v6_str = embed_ipv4_in_ipv6("192.0.2.1", "64:ff9b::/96")
        ip6 = ipaddress.IPv6Address(v6_str)

        # Build reverse nibble name for ip6.arpa
        # 64:ff9b::c000:201 -> 1.0.2.0.0.0.0.c...b.9.f.f.4.6.0.0.ip6.arpa
        nibbles = ip6.exploded.replace(":", "")[::-1]
        ip6_arpa_name = ".".join(nibbles) + ".ip6.arpa"

        v4_arpa = reverse_ipv6_to_ipv4_ptr(ip6_arpa_name, "64:ff9b::/96")
        self.assertIsNotNone(v4_arpa)
        self.assertEqual(v4_arpa, "1.2.0.192.in-addr.arpa.")

    def test_reverse_unrelated_ip6_arpa_returns_none(self):
        unrelated = "1.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.8.b.d.0.1.0.0.2.ip6.arpa"
        v4_arpa = reverse_ipv6_to_ipv4_ptr(unrelated, "64:ff9b::/96")
        self.assertIsNone(v4_arpa)


class TestDNS64EngineOperations(unittest.TestCase):
    """Tests core DNS64 translation engine policies and synthesis."""

    def setUp(self):
        self.engine = DNS64Engine(prefix="64:ff9b::/96", synth_ttl=120)

    def test_ipv4_exclusion_rules(self):
        # RFC 6147 §5.1.4: excluded addresses must not be synthesized
        self.assertTrue(self.engine.is_ipv4_excluded("127.0.0.1"))        # Loopback
        self.assertTrue(self.engine.is_ipv4_excluded("0.0.0.0"))          # Current network
        self.assertTrue(self.engine.is_ipv4_excluded("255.255.255.255"))  # Limited broadcast
        self.assertTrue(self.engine.is_ipv4_excluded("224.0.0.1"))        # Multicast
        self.assertTrue(self.engine.is_ipv4_excluded("169.254.1.1"))      # Link-local

        # Public IPv4 addresses should not be excluded
        self.assertFalse(self.engine.is_ipv4_excluded("8.8.8.8"))
        self.assertFalse(self.engine.is_ipv4_excluded("198.51.100.1"))

    def test_should_synthesize(self):
        # 1. Non-AAAA query -> False
        self.assertFalse(self.engine.should_synthesize(QTYPE.A, []))
        self.assertFalse(self.engine.should_synthesize(QTYPE.TXT, []))

        # 2. AAAA query with native AAAA records present -> False (RFC 6147 mandates native priority)
        native_rr = [RR("example.com.", QTYPE.AAAA, rdata=AAAA("2001:db8::1"))]
        self.assertFalse(self.engine.should_synthesize(QTYPE.AAAA, native_rr))

        # 3. AAAA query with NO native AAAA records -> True
        self.assertTrue(self.engine.should_synthesize(QTYPE.AAAA, []))

        # 4. Engine disabled -> False
        self.engine.enabled = False
        self.assertFalse(self.engine.should_synthesize(QTYPE.AAAA, []))

    def test_synthesize_aaaa_records(self):
        v4_list = ["198.51.100.10", "198.51.100.20"]
        rrs = self.engine.synthesize_aaaa_records("legacy.example.com", v4_list, original_ttl=300)

        self.assertEqual(len(rrs), 2)
        self.assertEqual(rrs[0].rtype, QTYPE.AAAA)
        self.assertEqual(rrs[0].ttl, 120)  # Clamped to synth_ttl=120
        self.assertEqual(str(rrs[0].rname), "legacy.example.com.")

        # Verify synthesized values
        v6_1 = str(rrs[0].rdata)
        v6_2 = str(rrs[1].rdata)
        self.assertEqual(extract_ipv4_from_ipv6(v6_1, "64:ff9b::/96"), "198.51.100.10")
        self.assertEqual(extract_ipv4_from_ipv6(v6_2, "64:ff9b::/96"), "198.51.100.20")

        # Telemetry should count 2 generated
        stats = self.engine.get_stats()
        self.assertEqual(stats["synthetic_aaaa_generated"], 2)

    def test_synthesize_with_excluded_ips_skips_them(self):
        # Mix of valid public and excluded loopback/multicast
        v4_mixed = ["127.0.0.1", "198.51.100.5", "224.0.0.251"]
        rrs = self.engine.synthesize_aaaa_records("mixed.example.com", v4_mixed)

        # Only 198.51.100.5 should be synthesized
        self.assertEqual(len(rrs), 1)
        self.assertEqual(extract_ipv4_from_ipv6(str(rrs[0].rdata), "64:ff9b::/96"), "198.51.100.5")


if __name__ == "__main__":
    unittest.main()
