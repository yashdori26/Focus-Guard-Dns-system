"""
FocusDNS Resolver & Security Unit Tests
Tests domain matching, public suffix parsing, private IP / DNS rebinding detection,
database column whitelisting, Strict Mode timer barrier, and rule cache invalidation.
"""

import os
import sys
import unittest
import time
import tempfile
import shutil

# Ensure server module and dnslib are discoverable
SERVER_DIR = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
REPO_DIR = os.path.abspath(os.path.join(SERVER_DIR, ".."))
if REPO_DIR not in sys.path:
    sys.path.insert(0, REPO_DIR)

VENV_PKGS = os.path.join(SERVER_DIR, "venv/lib/python3.14/site-packages")
if os.path.exists(VENV_PKGS) and VENV_PKGS not in sys.path:
    sys.path.insert(0, VENV_PKGS)

from server import resolver
from server import db

class TestResolverDomainLogic(unittest.TestCase):
    """Tests RFC-grade domain parsing and matching."""

    def test_split_domain_standard(self):
        self.assertEqual(resolver.split_domain("google.com"), ("", "google.com"))
        self.assertEqual(resolver.split_domain("mail.google.com"), ("mail.", "google.com"))
        self.assertEqual(resolver.split_domain("sub.deep.example.org"), ("sub.deep.", "example.org"))
        self.assertEqual(resolver.split_domain("localhost"), ("", "localhost"))

    def test_split_domain_multi_level_tlds(self):
        # ccTLDs like .co.uk, .com.au, .co.jp
        self.assertEqual(resolver.split_domain("bbc.co.uk"), ("", "bbc.co.uk"))
        self.assertEqual(resolver.split_domain("www.bbc.co.uk"), ("www.", "bbc.co.uk"))
        self.assertEqual(resolver.split_domain("www.hmrc.gov.uk"), ("www.", "hmrc.gov.uk"))
        self.assertEqual(resolver.split_domain("shop.amazon.co.jp"), ("shop.", "amazon.co.jp"))
        self.assertEqual(resolver.split_domain("portal.unimelb.edu.au"), ("portal.", "unimelb.edu.au"))

    def test_domain_matches_strict_boundary(self):
        # Exact match
        self.assertTrue(resolver.domain_matches("x.com", "x.com"))
        self.assertTrue(resolver.domain_matches("reddit.com", "reddit.com"))

        # Subdomain match
        self.assertTrue(resolver.domain_matches("www.x.com", "x.com"))
        self.assertTrue(resolver.domain_matches("old.reddit.com", "reddit.com"))
        self.assertTrue(resolver.domain_matches("deep.sub.reddit.com", "reddit.com"))

        # CRITICAL: Substring rejection (must NOT match substring inside domain name)
        self.assertFalse(resolver.domain_matches("box.community.net", "x.com"))
        self.assertFalse(resolver.domain_matches("notreddit.com", "reddit.com"))
        self.assertFalse(resolver.domain_matches("fake-reddit.com", "reddit.com"))
        self.assertFalse(resolver.domain_matches("reddit.com.evil.com", "reddit.com"))
        self.assertFalse(resolver.domain_matches("myx.com", "x.com"))

class TestSecurityIPInspection(unittest.TestCase):
    """Tests private IP detection for DNS rebinding protection."""

    def test_private_ipv4(self):
        self.assertTrue(resolver.is_private_ip("127.0.0.1"))
        self.assertTrue(resolver.is_private_ip("192.168.1.1"))
        self.assertTrue(resolver.is_private_ip("10.0.0.1"))
        self.assertTrue(resolver.is_private_ip("172.16.0.1"))
        self.assertTrue(resolver.is_private_ip("172.31.255.255"))
        self.assertTrue(resolver.is_private_ip("169.254.169.254")) # Link-local / AWS metadata
        self.assertTrue(resolver.is_private_ip("100.64.0.1"))       # Shared CGNAT RFC 6598
        self.assertTrue(resolver.is_private_ip("0.0.0.0"))         # Unspecified

    def test_private_ipv6(self):
        self.assertTrue(resolver.is_private_ip("::1"))              # Loopback
        self.assertTrue(resolver.is_private_ip("fe80::1"))          # Link-local
        self.assertTrue(resolver.is_private_ip("fc00::1"))          # Unique local
        self.assertTrue(resolver.is_private_ip("fd12:3456:789a::1")) # Unique local

    def test_public_ips(self):
        self.assertFalse(resolver.is_private_ip("8.8.8.8"))
        self.assertFalse(resolver.is_private_ip("1.1.1.1"))
        self.assertFalse(resolver.is_private_ip("142.250.190.46"))
        self.assertFalse(resolver.is_private_ip("2606:4700:4700::1111"))

    def test_local_zone_exemption(self):
        self.assertTrue(resolver.is_local_zone("router.lan"))
        self.assertTrue(resolver.is_local_zone("printer.local"))
        self.assertTrue(resolver.is_local_zone("nas.home.arpa"))
        self.assertTrue(resolver.is_local_zone("localhost"))
        self.assertFalse(resolver.is_local_zone("google.com"))

class TestDatabaseHardening(unittest.TestCase):
    """Tests SQL injection prevention, column whitelisting, and strict mode barrier."""

    @classmethod
    def setUpClass(cls):
        # Use a temporary test database
        cls.temp_dir = tempfile.mkdtemp()
        cls.test_db_path = os.path.join(cls.temp_dir, "test_focus_dns.db")
        cls.orig_db_path = db.DB_PATH
        db.DB_PATH = cls.test_db_path
        db.init_db()

    @classmethod
    def tearDownClass(cls):
        db.DB_PATH = cls.orig_db_path
        shutil.rmtree(cls.temp_dir, ignore_errors=True)

    def test_column_whitelist_sql_injection_defense(self):
        # Valid column updates
        db.update_security_setting("a1b2c3", "threat_intel", True)
        sec = db.get_security_settings("a1b2c3")
        self.assertTrue(sec["threat_intel"])

        # Attempt SQL injection via column name
        with self.assertRaises(ValueError):
            db.update_security_setting("a1b2c3", "threat_intel = 1; DROP TABLE profiles; --", False)

        with self.assertRaises(ValueError):
            db.update_privacy_setting("a1b2c3", "disguised_trackers; DELETE FROM custom_rules; --", False)

        with self.assertRaises(ValueError):
            db.update_web3_setting("a1b2c3", "arbitrary_column", True)

    def test_strict_mode_timer_barrier(self):
        profile_id = "a1b2c3"
        # Enable timed strict mode
        success, msg = db.set_strict_mode(profile_id, True, duration_minutes=10)
        self.assertTrue(success)

        # Strict mode without a duration is rejected (no PIN mode)
        success, msg = db.set_strict_mode(profile_id, True)
        self.assertFalse(success)

        # Cannot turn off protection or strict mode while the timer runs
        success, msg = db.update_protection(profile_id, False)
        self.assertFalse(success)
        self.assertIn("Strict Mode", msg)
        success, msg = db.set_strict_mode(profile_id, False)
        self.assertFalse(success)

        # Expire the timer -> strict mode auto-clears and changes are allowed
        conn = db.get_connection()
        conn.execute("UPDATE profiles SET strict_until = ? WHERE profile_id = ?", (time.time() - 1, profile_id))
        conn.commit()
        conn.close()
        db.invalidate_cache(profile_id)
        success, msg = db.update_protection(profile_id, False)
        self.assertTrue(success)

        # Re-enable protection
        success, msg = db.update_protection(profile_id, True)
        self.assertTrue(success)

    def test_in_memory_rule_cache_invalidation(self):
        profile_id = "a1b2c3"
        # Prime cache
        cache1 = db.get_cached_rules(profile_id)
        self.assertIn("allowlist", cache1)

        # Add a custom rule -> Cache must invalidate
        db.add_custom_rule(profile_id, "deny", "unit-test-blocked.xyz")
        cache2 = db.get_cached_rules(profile_id)
        self.assertIn("unit-test-blocked.xyz", cache2["denylist"])

        # Clean up
        db.remove_custom_rule(profile_id, "deny", "unit-test-blocked.xyz")
        cache3 = db.get_cached_rules(profile_id)
        self.assertNotIn("unit-test-blocked.xyz", cache3["denylist"])

    def test_async_query_logger_and_purge(self):
        # Test async logging
        db.log_query_async("a1b2c3", "example.org", "", "allowed", "Clean Query", "127.0.0.1")
        # Flush queue
        db.flush_query_log_queue()

        logs = db.get_query_logs("a1b2c3", limit=5)
        self.assertTrue(any(l["domain"] == "example.org" for l in logs))

        # Test retention purge executes without error
        purged = db.purge_expired_logs()
        self.assertIsInstance(purged, int)

if __name__ == "__main__":
    unittest.main()
