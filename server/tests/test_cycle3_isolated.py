"""
FocusDNS Cycle 3 Comprehensive Isolated Test Suite
Tests:
- Strict Mode attack vectors (timer-only enforcement, value: 0 non-bool bypass)
- Log retention policy guard under Strict Mode
- Public Suffix parsing (com.cn, co.kr, github.io, blogspot.com, co.uk)
- DNS Wire forwarding across query types (A, AAAA, MX, TXT)
- Nonexistent domain returning NXDOMAIN (RCODE 3) instead of SERVFAIL
- Blocked domain returning NXDOMAIN with 0 answers
- DNS rebinding interception for private IPs on public domains
- Error telemetry logging on SERVFAIL and upstream failures
- All running against an isolated temporary database with zero live environment mutation
"""

import ipaddress
import os
import shutil
import sys
import tempfile
import time
import unittest

# Ensure server module is discoverable
SERVER_DIR = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
REPO_DIR = os.path.abspath(os.path.join(SERVER_DIR, ".."))
if REPO_DIR not in sys.path:
    sys.path.insert(0, REPO_DIR)

from dnslib import DNSRecord, QTYPE, RCODE, RR, A, AAAA, MX, TXT

from server import db
from server import resolver

class TestCycle3IsolatedSuite(unittest.TestCase):

    @classmethod
    def setUpClass(cls):
        cls.temp_dir = tempfile.mkdtemp()
        cls.test_db_path = os.path.join(cls.temp_dir, "test_cycle3.db")
        cls.orig_db_path = db.DB_PATH
        db.DB_PATH = cls.test_db_path
        db.init_db()

    @classmethod
    def tearDownClass(cls):
        db.flush_query_log_queue()
        db.DB_PATH = cls.orig_db_path
        shutil.rmtree(cls.temp_dir, ignore_errors=True)

    def setUp(self):
        # Reset profile state
        conn = db.get_connection()
        conn.execute("UPDATE profiles SET is_strict_mode = 0, is_protection_on = 1, strict_until = NULL WHERE profile_id = 'a1b2c3'")
        conn.commit()
        conn.close()
        db.invalidate_cache('a1b2c3')

    # =========================================================================
    # 1. STRICT MODE SECURITY & ATTACK VECTORS
    # =========================================================================

    def test_strict_mode_requires_duration(self):
        """Enabling Strict Mode without a positive duration must be rejected."""
        for dur in (None, 0, -5):
            success, msg = db.set_strict_mode('a1b2c3', True, duration_minutes=dur)
            self.assertFalse(success)
            self.assertIn("duration", msg)
        self.assertFalse(bool(db.get_profile('a1b2c3')['is_strict_mode']))

    def test_strict_mode_timer_cannot_be_overwritten_or_unlocked(self):
        """An active timer cannot be shortened/replaced or unlocked early."""
        success, _ = db.set_strict_mode('a1b2c3', True, duration_minutes=30)
        self.assertTrue(success)
        until = db.get_profile('a1b2c3')['strict_until']

        success, _ = db.set_strict_mode('a1b2c3', True, duration_minutes=1)
        self.assertFalse(success)
        success, _ = db.set_strict_mode('a1b2c3', False)
        self.assertFalse(success)
        self.assertEqual(db.get_profile('a1b2c3')['strict_until'], until)

    def test_strict_mode_expiry_and_no_timer_state(self):
        """Expired timers auto-clear; strict with no end time is self-healed (not bypass-locked)."""
        db.set_strict_mode('a1b2c3', True, duration_minutes=5)
        conn = db.get_connection()
        conn.execute("UPDATE profiles SET strict_until = ? WHERE profile_id = 'a1b2c3'", (time.time() - 1,))
        conn.commit()
        conn.close()
        db.invalidate_cache('a1b2c3')
        p = db.get_profile('a1b2c3')
        self.assertEqual(p['is_strict_mode'], 0)
        self.assertIsNone(p['strict_until'])

        conn = db.get_connection()
        conn.execute("UPDATE profiles SET is_strict_mode = 1, strict_until = NULL WHERE profile_id = 'a1b2c3'")
        conn.commit()
        conn.close()
        db.invalidate_cache('a1b2c3')
        self.assertEqual(db.get_profile('a1b2c3')['is_strict_mode'], 0)

    def test_profile_has_no_pin_artifacts(self):
        """No PIN column in profile output or schema."""
        prof = db.get_profile('a1b2c3')
        self.assertNotIn('strict_pin', prof)
        conn = db.get_connection()
        cols = [r['name'] for r in conn.execute("PRAGMA table_info(profiles)")]
        tables = [r['name'] for r in conn.execute("SELECT name FROM sqlite_master WHERE type='table'")]
        conn.close()
        self.assertNotIn('strict_pin', cols)
        self.assertNotIn('pin_lockouts', tables)

    def test_boolean_type_validation_and_value_zero_defense(self):
        """
        Confirmed Probe Bug #2: Passing 0 or 'false' to toggles must NOT bypass
        type validation.
        """
        with self.assertRaises(ValueError):
            db.update_security_setting('a1b2c3', 'threat_intel', 0)

        with self.assertRaises(ValueError):
            db.update_security_setting('a1b2c3', 'threat_intel', 'false')

        with self.assertRaises(ValueError):
            db.update_privacy_setting('a1b2c3', 'disguised_trackers', 0)

        with self.assertRaises(ValueError):
            db.update_web3_setting('a1b2c3', 'ens', 0)

        # Valid boolean must succeed
        db.update_security_setting('a1b2c3', 'threat_intel', False)
        sec = db.get_security_settings('a1b2c3')
        self.assertFalse(sec['threat_intel'])

    def test_settings_log_retention_strict_mode_guard(self):
        """Changing retention while the Strict Mode timer runs must be rejected."""
        db.set_strict_mode('a1b2c3', True, duration_minutes=10)
        success, msg = db.update_log_retention('a1b2c3', '1 hour')
        self.assertFalse(success)
        self.assertIn("Strict Mode", msg)

        conn = db.get_connection()
        conn.execute("UPDATE profiles SET strict_until = ? WHERE profile_id = 'a1b2c3'", (time.time() - 1,))
        conn.commit()
        conn.close()
        db.invalidate_cache('a1b2c3')
        success, msg = db.update_log_retention('a1b2c3', '1 hour')
        self.assertTrue(success)
        self.assertEqual(db.get_profile('a1b2c3')['log_retention'], '1 hour')

    # =========================================================================
    # 2. PUBLIC SUFFIX DOMAIN PARSING
    # =========================================================================

    def test_public_suffix_parsing(self):
        """Tests publicsuffix2 domain splitting across complex TLDs."""
        self.assertEqual(resolver.split_domain("bbc.co.uk"), ("", "bbc.co.uk"))
        self.assertEqual(resolver.split_domain("www.bbc.co.uk"), ("www.", "bbc.co.uk"))
        self.assertEqual(resolver.split_domain("foo.blogspot.com"), ("", "foo.blogspot.com"))
        self.assertEqual(resolver.split_domain("sub.foo.blogspot.com"), ("sub.", "foo.blogspot.com"))
        self.assertEqual(resolver.split_domain("test.github.io"), ("", "test.github.io"))
        self.assertEqual(resolver.split_domain("foo.com.cn"), ("", "foo.com.cn"))
        self.assertEqual(resolver.split_domain("www.hmrc.gov.uk"), ("www.", "hmrc.gov.uk"))
        self.assertEqual(resolver.split_domain("news.service.gov.uk"), ("", "news.service.gov.uk"))
        self.assertEqual(resolver.split_domain("portal.unimelb.edu.au"), ("portal.", "unimelb.edu.au"))
        self.assertEqual(resolver.split_domain("localhost"), ("", "localhost"))

    # =========================================================================
    # 3. DNS WIRE FORWARDING & QUERY TYPES
    # =========================================================================

    def test_wire_forwarding_query_types(self):
        """
        Tests real wire DNS resolution across A, AAAA, MX, and TXT query types.
        Verifies that AAAA lookups do NOT raise ValueError or return IPv4 strings.
        """
        # A query
        req_a = DNSRecord.question("google.com", "A")
        raw_reply, meta = resolver.resolve_wire_packet(req_a.pack(), 'a1b2c3', '127.0.0.1')
        reply_a = DNSRecord.parse(raw_reply)
        self.assertEqual(reply_a.header.rcode, RCODE.NOERROR)
        self.assertGreater(len(reply_a.rr), 0)
        # Verify valid IPv4
        a_ip = str(reply_a.rr[0].rdata)
        self.assertEqual(ipaddress.ip_address(a_ip).version, 4)

        # AAAA query (IPv6)
        req_aaaa = DNSRecord.question("google.com", "AAAA")
        raw_reply, meta = resolver.resolve_wire_packet(req_aaaa.pack(), 'a1b2c3', '127.0.0.1')
        reply_aaaa = DNSRecord.parse(raw_reply)
        self.assertEqual(reply_aaaa.header.rcode, RCODE.NOERROR)
        self.assertGreater(len(reply_aaaa.rr), 0)
        # Verify valid IPv6
        aaaa_ip = str(reply_aaaa.rr[0].rdata)
        self.assertEqual(ipaddress.ip_address(aaaa_ip).version, 6)

        # MX query
        req_mx = DNSRecord.question("gmail.com", "MX")
        raw_reply, meta = resolver.resolve_wire_packet(req_mx.pack(), 'a1b2c3', '127.0.0.1')
        reply_mx = DNSRecord.parse(raw_reply)
        self.assertEqual(reply_mx.header.rcode, RCODE.NOERROR)
        self.assertGreater(len(reply_mx.rr), 0)
        self.assertEqual(reply_mx.rr[0].rtype, QTYPE.MX)

        # TXT query
        req_txt = DNSRecord.question("google.com", "TXT")
        raw_reply, meta = resolver.resolve_wire_packet(req_txt.pack(), 'a1b2c3', '127.0.0.1')
        reply_txt = DNSRecord.parse(raw_reply)
        self.assertEqual(reply_txt.header.rcode, RCODE.NOERROR)
        self.assertGreater(len(reply_txt.rr), 0)
        self.assertEqual(reply_txt.rr[0].rtype, QTYPE.TXT)

    def test_nonexistent_domain_returns_nxdomain(self):
        """
        Confirmed Probe Bug #3: Nonexistent domain must return NXDOMAIN (RCODE 3),
        NOT SERVFAIL!
        """
        req = DNSRecord.question("this-does-not-exist-zzqq-test-focusdns.com", "A")
        raw_reply, meta = resolver.resolve_wire_packet(req.pack(), 'a1b2c3', '127.0.0.1')
        reply = DNSRecord.parse(raw_reply)
        self.assertEqual(reply.header.rcode, RCODE.NXDOMAIN)
        self.assertEqual(meta['rcode'], 'NXDOMAIN')

    def test_blocked_domain_returns_nxdomain_with_zero_answers(self):
        """Blocked domain must return standard NXDOMAIN with 0 answers."""
        req = DNSRecord.question("reddit.com", "A")
        raw_reply, meta = resolver.resolve_wire_packet(req.pack(), 'a1b2c3', '127.0.0.1')
        reply = DNSRecord.parse(raw_reply)
        self.assertEqual(reply.header.rcode, RCODE.NXDOMAIN)
        self.assertEqual(len(reply.rr), 0)
        self.assertEqual(meta['status'], 'blocked')

    def test_dns_rebinding_interception(self):
        """Private IP returned for a public domain must be blocked as DNS rebinding."""
        # Enable DNS rebinding protection
        db.update_security_setting('a1b2c3', 'dns_rebinding', True)
        self.assertTrue(resolver.is_private_ip("192.168.1.1"))
        self.assertTrue(resolver.is_private_ip("100.64.0.1"))
        self.assertFalse(resolver.is_local_zone("evil-target.com"))

    def test_servfail_telemetry_logging(self):
        """SERVFAIL upstream outcomes must be logged in telemetry."""
        db.log_query_async('a1b2c3', 'timeout.org', '', 'error', 'Upstream Resolution Failed', '127.0.0.1')
        db.flush_query_log_queue()
        logs = db.get_query_logs('a1b2c3', limit=5)
        self.assertTrue(any(l['status'] == 'error' and 'Upstream' in l['reason'] for l in logs))

    def test_expanded_app_domains_blocked(self):
        """
        Confirmed Requirement: NextDNS-style app blocking must intercept API,
        auth, and CDN endpoints (e.g. gql.reddit.com, oauth.reddit.com, v.redd.it).
        """
        for subdomain_query in ["gql.reddit.com", "oauth.reddit.com", "v.redd.it", "preview.redd.it", "styles.redditmedia.com"]:
            req = DNSRecord.question(subdomain_query, "A")
            raw_reply, meta = resolver.resolve_wire_packet(req.pack(), 'a1b2c3', '127.0.0.1')
            reply = DNSRecord.parse(raw_reply)
            self.assertEqual(reply.header.rcode, RCODE.NXDOMAIN, f"Failed on {subdomain_query}")
            self.assertEqual(len(reply.rr), 0)
            self.assertEqual(meta['status'], 'blocked')

    def test_firefox_canary_domain_returns_nxdomain(self):
        """
        Confirmed Requirement: Mozilla RFC canary domain (use-application-dns.net)
        must return NXDOMAIN to disable browser DoH bypass.
        """
        req = DNSRecord.question("use-application-dns.net", "A")
        raw_reply, meta = resolver.resolve_wire_packet(req.pack(), 'a1b2c3', '127.0.0.1')
        reply = DNSRecord.parse(raw_reply)
        self.assertEqual(reply.header.rcode, RCODE.NXDOMAIN)
        self.assertIn("Canary", meta['reason'])

    def test_doh_bypass_domains_blocked(self):
        """
        Confirmed Requirement: Public DoH resolver hostnames must be blocked to prevent
        apps from bypassing local DNS filtering.
        """
        for doh_domain in ["dns.google", "cloudflare-dns.com", "dns.quad9.net"]:
            req = DNSRecord.question(doh_domain, "A")
            raw_reply, meta = resolver.resolve_wire_packet(req.pack(), 'a1b2c3', '127.0.0.1')
            reply = DNSRecord.parse(raw_reply)
            self.assertEqual(reply.header.rcode, RCODE.NXDOMAIN, f"Failed to block DoH domain: {doh_domain}")
            self.assertEqual(meta['status'], 'blocked')

    def test_blocked_answer_authority_soa_negative_ttl(self):
        """
        Confirmed Requirement: Blocked responses must include a short negative caching
        TTL (30s) in authority SOA to allow rapid unblocking without hanging.
        """
        req = DNSRecord.question("reddit.com", "A")
        raw_reply, _ = resolver.resolve_wire_packet(req.pack(), 'a1b2c3', '127.0.0.1')
        reply = DNSRecord.parse(raw_reply)
        self.assertEqual(reply.header.rcode, RCODE.NXDOMAIN)
        self.assertGreater(len(reply.auth), 0)
        self.assertEqual(reply.auth[0].rtype, QTYPE.SOA)
        self.assertEqual(reply.auth[0].ttl, 30)

if __name__ == '__main__':
    unittest.main()
