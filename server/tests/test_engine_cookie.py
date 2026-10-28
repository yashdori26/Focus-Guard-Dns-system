"""
FocusDNS Engine Tests - RFC 7873 & RFC 9018 Interoperable DNS Server Cookie Subsystem
Tests:
- RFC 9018 Server Cookie generation with 16-byte HMAC-SHA256 structure
- RFC 9018 Section 5.3 timestamp verification and validity windows
- Graceful secret rotation with previous secret dual-verification
- Bad cookie rejection (length mismatch, bad version, corrupted HMAC)
- Telemetry stats tracking
"""

import struct
import time
import unittest

from server.engine.cookie_manager import (
    DNSCookieManager,
    DNSCookieSecret,
    SERVER_COOKIE_VERSION_1,
    SERVER_COOKIE_LEN,
    CLIENT_COOKIE_LEN,
    COOKIE_MAX_TIME_VALIDITY,
    COOKIE_LOWER_TIME_TOLERANCE,
)


class TestDNSCookieManager(unittest.TestCase):

    def setUp(self):
        self.mgr = DNSCookieManager(rollover_interval_sec=3600.0)
        self.client_cookie = b"ABCDEFGH"  # Exactly 8 bytes
        self.client_ip = "192.0.2.42"

    def test_client_cookie_length_validation(self):
        with self.assertRaises(ValueError):
            self.mgr.generate_server_cookie(b"short", self.client_ip)

        with self.assertRaises(ValueError):
            self.mgr.generate_server_cookie(b"too_long_client_cookie", self.client_ip)

    def test_generate_and_validate_valid_cookie(self):
        server_cookie = self.mgr.generate_server_cookie(self.client_cookie, self.client_ip)
        self.assertEqual(len(server_cookie), SERVER_COOKIE_LEN)

        # Version must be 1
        self.assertEqual(server_cookie[0], SERVER_COOKIE_VERSION_1)
        # Reserved bytes must be 0x00, 0x00
        self.assertEqual(server_cookie[1:4], b"\x00\x00\x00")

        valid, reason = self.mgr.validate_cookie(self.client_cookie, server_cookie, self.client_ip)
        self.assertTrue(valid)
        self.assertEqual(reason, "VALID_ACTIVE_SECRET")

    def test_validate_cookie_different_ip_fails(self):
        server_cookie = self.mgr.generate_server_cookie(self.client_cookie, self.client_ip)
        different_ip = "198.51.100.1"

        valid, reason = self.mgr.validate_cookie(self.client_cookie, server_cookie, different_ip)
        self.assertFalse(valid)
        self.assertEqual(reason, "BAD_COOKIE_HMAC")

    def test_validate_cookie_different_client_cookie_fails(self):
        server_cookie = self.mgr.generate_server_cookie(self.client_cookie, self.client_ip)
        tampered_client = b"HGFEDCBA"

        valid, reason = self.mgr.validate_cookie(tampered_client, server_cookie, self.client_ip)
        self.assertFalse(valid)
        self.assertEqual(reason, "BAD_COOKIE_HMAC")

    def test_validate_corrupted_hash_fails(self):
        server_cookie = bytearray(self.mgr.generate_server_cookie(self.client_cookie, self.client_ip))
        # Corrupt last byte of hash
        server_cookie[-1] ^= 0xFF

        valid, reason = self.mgr.validate_cookie(self.client_cookie, bytes(server_cookie), self.client_ip)
        self.assertFalse(valid)
        self.assertEqual(reason, "BAD_COOKIE_HMAC")

    def test_invalid_lengths_rejected(self):
        valid, reason = self.mgr.validate_cookie(b"short", b"0" * 16, self.client_ip)
        self.assertFalse(valid)
        self.assertEqual(reason, "INVALID_CLIENT_COOKIE_LENGTH")

        valid, reason = self.mgr.validate_cookie(self.client_cookie, b"short", self.client_ip)
        self.assertFalse(valid)
        self.assertEqual(reason, "INVALID_SERVER_COOKIE_LENGTH")

    def test_unsupported_version_rejected(self):
        bad_version_cookie = b"\x02\x00\x00\x00" + struct.pack("!I", int(time.time())) + b"01234567"
        valid, reason = self.mgr.validate_cookie(self.client_cookie, bad_version_cookie, self.client_ip)
        self.assertFalse(valid)
        self.assertEqual(reason, "UNSUPPORTED_COOKIE_VERSION")

    def test_expired_timestamp_rejected(self):
        # Create cookie with timestamp in distant past
        past_time = int(time.time()) - (COOKIE_MAX_TIME_VALIDITY + 50)
        hdr = struct.pack("!BBBBI", SERVER_COOKIE_VERSION_1, 0, 0, 0, past_time)
        cookie = hdr + b"12345678"

        valid, reason = self.mgr.validate_cookie(self.client_cookie, cookie, self.client_ip)
        self.assertFalse(valid)
        self.assertEqual(reason, "COOKIE_EXPIRED")

    def test_future_timestamp_rejected(self):
        # Create cookie with timestamp too far in the future
        future_time = int(time.time()) + (COOKIE_LOWER_TIME_TOLERANCE + 50)
        hdr = struct.pack("!BBBBI", SERVER_COOKIE_VERSION_1, 0, 0, 0, future_time)
        cookie = hdr + b"12345678"

        valid, reason = self.mgr.validate_cookie(self.client_cookie, cookie, self.client_ip)
        self.assertFalse(valid)
        self.assertEqual(reason, "COOKIE_TIMESTAMP_IN_FUTURE")

    def test_secret_rotation_grace_period(self):
        # Generate cookie with original secret
        cookie1 = self.mgr.generate_server_cookie(self.client_cookie, self.client_ip)
        self.assertIsNone(self.mgr.previous_secret)

        # Rotate secret
        self.mgr.rotate_secret()
        self.assertIsNotNone(self.mgr.previous_secret)
        self.assertEqual(self.mgr.secrets_rotated, 1)

        # Cookie 1 should still validate via previous secret
        valid, reason = self.mgr.validate_cookie(self.client_cookie, cookie1, self.client_ip)
        self.assertTrue(valid)
        self.assertEqual(reason, "VALID_PREVIOUS_SECRET")

        # New cookie generates with active secret
        cookie2 = self.mgr.generate_server_cookie(self.client_cookie, self.client_ip)
        valid2, reason2 = self.mgr.validate_cookie(self.client_cookie, cookie2, self.client_ip)
        self.assertTrue(valid2)
        self.assertEqual(reason2, "VALID_ACTIVE_SECRET")

        # Rotate second time -> original cookie 1 now discarded and invalid
        self.mgr.rotate_secret()
        valid_old, reason_old = self.mgr.validate_cookie(self.client_cookie, cookie1, self.client_ip)
        self.assertFalse(valid_old)
        self.assertEqual(reason_old, "BAD_COOKIE_HMAC")

    def test_stats_reporting(self):
        self.mgr.generate_server_cookie(self.client_cookie, self.client_ip)
        self.mgr.validate_cookie(self.client_cookie, b"0" * 16, self.client_ip)
        stats = self.mgr.get_stats()

        self.assertEqual(stats["rfc"], "RFC 9018")
        self.assertEqual(stats["cookies_generated"], 1)
        self.assertIn("cookies_valid", stats)
        self.assertIn("cookies_expired", stats)
        self.assertIn("cookies_bad_hash", stats)


if __name__ == "__main__":
    unittest.main()
