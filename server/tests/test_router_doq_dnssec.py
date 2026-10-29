"""
Unit tests for Router Edge DNS-over-QUIC (DoQ RFC 9250) and DNSSEC Validator.
"""

import unittest
import struct
from router.daemon.router_doq_engine import RouterDoqEngine
from router.daemon.router_dnssec_validator import RouterDnssecValidator, DnssecTrustAnchor


class TestRouterDoqAndDnssec(unittest.TestCase):

    def setUp(self):
        self.doq_engine = RouterDoqEngine(upstream_host="127.0.0.1", upstream_port=8853)
        self.dnssec_validator = RouterDnssecValidator()

    def test_doq_framing_and_unframing(self):
        sample_query = b"\x12\x34\x01\x00\x00\x01\x00\x00\x00\x00\x00\x00\x07example\x03com\x00\x00\x01\x00\x01"
        framed = self.doq_engine.frame_query(sample_query)

        # RFC 9250 requires a 2-byte big-endian length prefix
        self.assertEqual(len(framed), len(sample_query) + 2)
        expected_len = struct.unpack("!H", framed[:2])[0]
        self.assertEqual(expected_len, len(sample_query))

        unframed, remaining = self.doq_engine.unframe_response(framed)
        self.assertEqual(unframed, sample_query)
        self.assertEqual(len(remaining), 0)

    def test_doq_truncated_stream_error(self):
        truncated_packet = b"\x00\x10\x12\x34" # Claims 16 bytes, but only has 2 payload bytes
        with self.assertRaises(ValueError):
            self.doq_engine.unframe_response(truncated_packet)

    def test_doq_session_ticket_storage_and_telemetry(self):
        ticket = b"tls13_0rtt_sample_session_resumption_ticket_bytes"
        self.doq_engine.store_session_ticket(ticket)
        telemetry = self.doq_engine.get_telemetry()

        self.assertTrue(telemetry["has_cached_session_ticket"])
        self.assertEqual(telemetry["alpn"], "doq")
        self.assertTrue(telemetry["zero_rtt_enabled"])

    def test_dnssec_rrsig_timing_validation(self):
        inception = 1700000000
        expiration = 1700100000

        # Current time within window
        self.assertTrue(self.dnssec_validator.verify_rrsig_timing(inception, expiration, current_time=1700050000))

        # Current time before inception
        self.assertFalse(self.dnssec_validator.verify_rrsig_timing(inception, expiration, current_time=1699999999))

        # Current time after expiration
        self.assertFalse(self.dnssec_validator.verify_rrsig_timing(inception, expiration, current_time=1700100001))

    def test_dnssec_ds_digest_calculation(self):
        # Test SHA-256 digest computation for a simulated DNSKEY
        fake_dnskey = b"\x01\x00\x03\x08abcdefghijklmnopqrstuvwxyz012345"
        digest = self.dnssec_validator.calculate_ds_digest("example.com", fake_dnskey, digest_type=2)
        self.assertIsInstance(digest, str)
        self.assertEqual(len(digest), 64) # SHA-256 hex string

    def test_dnssec_packet_ad_flag_validation(self):
        # Construct DNS response packet (QR=1, RCODE=0, Flags=0x8180)
        tx_id = b"\xab\xcd"
        flags = struct.pack("!H", 0x8180)
        counts = b"\x00\x01\x00\x01\x00\x00\x00\x00"
        payload = b"\x07example\x03com\x00\x00\x01\x00\x01"
        raw_response = tx_id + flags + counts + payload

        status, verified_packet = self.dnssec_validator.validate_dns_packet(raw_response, "example.com")
        self.assertEqual(status, "SECURE")

        # Verify AD (Authenticated Data) bit (0x0020) is set in the response
        verified_flags = struct.unpack("!H", verified_packet[2:4])[0]
        self.assertTrue((verified_flags & 0x0020) != 0)

        # Check bogus for malformed packet
        status_bogus, _ = self.dnssec_validator.validate_dns_packet(b"\x00\x01", "example.com")
        self.assertEqual(status_bogus, "BOGUS")


if __name__ == "__main__":
    unittest.main()
