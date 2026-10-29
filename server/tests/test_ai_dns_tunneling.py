"""
Unit tests for On-Device DNS Tunneling & Exfiltration Detector.
Validates payload entropy, encoding recognition (Hex/Base32/Base64), burst velocity,
life-safety exemptions, and Conditional Whitelisting Law.
"""

import unittest
from server.ai.dns_tunneling_detector import (
    DnsTunnelingDetector,
    DnsTunnelingVerdict,
    LIFE_SAFETY_DOMAINS
)


class TestDnsTunnelingDetector(unittest.TestCase):

    def setUp(self):
        self.detector = DnsTunnelingDetector(risk_threshold=60.0)

    def test_benign_domain_not_flagged(self):
        """Standard human domains must have low risk scores and not be flagged."""
        benign_samples = [
            "google.com",
            "api.github.com",
            "mail.google.com",
            "docs.python.org",
            "cdn.jsdelivr.net",
        ]
        for domain in benign_samples:
            verdict = self.detector.analyze(domain)
            self.assertFalse(verdict.is_tunneling, f"False positive on benign domain: {domain}")
            self.assertLess(verdict.risk_score, 50.0)

    def test_hex_exfiltration_payload_detection(self):
        """Long hexadecimal chunk in subdomain should be detected as tunneling."""
        hex_payload = "48656c6c6f576f726c6454686973497344617461457866696c74726174696f6e.c2.attacker.com"
        verdict = self.detector.analyze(hex_payload, qtype="TXT")

        self.assertTrue(verdict.is_tunneling)
        self.assertGreaterEqual(verdict.risk_score, 60.0)
        self.assertEqual(verdict.detected_encoding, "HEXADECIMAL")
        self.assertIn("HEXADECIMAL", verdict.reason)

    def test_base32_iodine_tunnel_detection(self):
        """Base32 encoded payload (typical for Iodine / DNSCat2) should be caught."""
        b32_payload = "jbswy3dpeblw64tmmqqq234567abcdefg.tunnel.badactor.net"
        verdict = self.detector.analyze(b32_payload, qtype="NULL")

        self.assertTrue(verdict.is_tunneling)
        self.assertGreaterEqual(verdict.risk_score, 60.0)
        self.assertEqual(verdict.detected_encoding, "BASE32")

    def test_txt_record_multiplier(self):
        """High abuse record types (TXT, NULL) must amplify risk score over A queries."""
        payload = "a1b2c3d4e5f6g7h8i9j0k1l2m3n4o5p6.exfil.org"
        v_a = self.detector.analyze(payload, qtype="A")
        v_txt = self.detector.analyze(payload, qtype="TXT")

        self.assertGreater(v_txt.risk_score, v_a.risk_score)

    def test_legitimate_cdn_bypass(self):
        """Cloudfront, Akamai, AzureEdge hash prefixes must be recognized and bypassed."""
        cdn_domain = "d12345abcdefgh6789.cloudfront.net"
        verdict = self.detector.analyze(cdn_domain)

        self.assertFalse(verdict.is_tunneling)
        self.assertEqual(verdict.detected_encoding, "LEGITIMATE_CDN")

    def test_life_safety_exemption_never_flagged(self):
        """Emergency calling and system updates must NEVER be flagged even with abnormal formats."""
        for exempt in LIFE_SAFETY_DOMAINS:
            verdict = self.detector.analyze(f"exfil1234567890abcdef.{exempt}", qtype="TXT")
            self.assertFalse(verdict.is_tunneling)
            self.assertTrue(verdict.is_exempt)
            self.assertEqual(verdict.risk_score, 0.0)

    def test_conditional_whitelisting_law_when_idle(self):
        """Whitelisting works with 0 friction when idle."""
        self.assertFalse(self.detector.is_locked)

        domain = "custom-tunnel-partner.com"
        success = self.detector.add_whitelist(domain)
        self.assertTrue(success)
        self.assertIn(domain, self.detector.get_whitelist())

        # Now analyzing with large payload should be permitted due to whitelist
        verdict = self.detector.analyze(f"abcdef12345678901234567890.{domain}")
        self.assertFalse(verdict.is_tunneling)
        self.assertTrue(verdict.is_whitelisted)

        # Removal succeeds when idle
        removed = self.detector.remove_whitelist(domain)
        self.assertTrue(removed)
        self.assertNotIn(domain, self.detector.get_whitelist())

    def test_conditional_whitelisting_law_denial_when_locked(self):
        """Whitelisting must raise PermissionError ERROR_ACCESS_DENIED (5) when locked."""
        self.detector.set_lock_state(is_locked=True, countdown_seconds=0)
        self.assertTrue(self.detector.is_locked)

        with self.assertRaises(PermissionError) as ctx:
            self.detector.add_whitelist("malicious-c2.net")
        self.assertIn("ERROR_ACCESS_DENIED (5)", str(ctx.exception))

        with self.assertRaises(PermissionError) as ctx:
            self.detector.remove_whitelist("malicious-c2.net")
        self.assertIn("ERROR_ACCESS_DENIED (5)", str(ctx.exception))

    def test_conditional_whitelisting_law_denial_when_timer_active(self):
        """Whitelisting must raise PermissionError if countdown_seconds > 0 even if is_locked is False."""
        self.detector.set_lock_state(is_locked=False, countdown_seconds=1200)
        self.assertTrue(self.detector.is_locked)

        with self.assertRaises(PermissionError) as ctx:
            self.detector.add_whitelist("tunnel-domain.com")
        self.assertIn("ERROR_ACCESS_DENIED (5)", str(ctx.exception))

    def test_telemetry_counters(self):
        """Telemetry must correctly record scanned queries and blocked exfiltration attempts."""
        self.detector.analyze("benign.com")
        self.detector.analyze("48656c6c6f576f726c6454686973497344617461457866696c74726174696f6e.c2.attacker.com")

        telem = self.detector.get_telemetry()
        self.assertGreaterEqual(telem["total_scanned"], 2)
        self.assertGreaterEqual(telem["total_tunneling_blocked"], 1)


if __name__ == "__main__":
    unittest.main()
