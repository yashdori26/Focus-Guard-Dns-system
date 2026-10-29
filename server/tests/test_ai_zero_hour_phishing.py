"""
Unit Tests for Zero-Hour Phishing & Brand Impersonation Detector
Verifies subdomain brand spoofing, deceptive keyword chaining, Shannon entropy,
TLD multipliers, and unconditional Life Safety Exemptions.
"""

import unittest
import sys
import os

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))))

from server.ai.zero_hour_phishing import (
    ZeroHourPhishingDetector,
    PhishingVerdict,
    LIFE_SAFETY_EXEMPTIONS,
)


class TestZeroHourPhishingDetector(unittest.TestCase):
    """Verifies phishing detection heuristics and life-safety bypasses."""

    def setUp(self):
        self.detector = ZeroHourPhishingDetector()

    def test_life_safety_exemptions_unconditionally_clean(self):
        """
        Inviolable Principle: Emergency 911/112, Apple APNs, Windows Update,
        and Google Play Services must NEVER be flagged as phishing or blocked.
        """
        for domain in LIFE_SAFETY_EXEMPTIONS:
            verdict: PhishingVerdict = self.detector.analyze(domain)
            self.assertFalse(
                verdict.is_phishing,
                f"Life safety domain {domain} was falsely flagged as phishing!"
            )
            self.assertEqual(verdict.phishing_score, 0.0)
            self.assertEqual(verdict.risk_level, "CLEAN_EXEMPT")
            self.assertIn("LIFE_SAFETY_EXEMPTION_ACTIVE", verdict.indicators)

    def test_life_safety_subdomains_also_exempt(self):
        """Subdomains of life-safety exemptions must also pass unconditionally."""
        exempt_subdomains = [
            "sub.emergency.gov",
            "dispatch.911.gov",
            "eu.112.gov",
            "1-courier.push.apple.com",
            "download.windowsupdate.com",
            "api.play.googleapis.com",
        ]
        for sub in exempt_subdomains:
            verdict = self.detector.analyze(sub)
            self.assertFalse(verdict.is_phishing)
            self.assertEqual(verdict.phishing_score, 0.0)
            self.assertEqual(verdict.risk_level, "CLEAN_EXEMPT")

    def test_legitimate_brand_apex_not_phishing(self):
        """Official brand apex and legitimate login domains are clean."""
        legit_domains = [
            "apple.com",
            "paypal.com",
            "google.com",
            "microsoft.com",
            "chase.com",
            "netflix.com",
            "binance.com",
            "amazon.com",
        ]
        for domain in legit_domains:
            verdict = self.detector.analyze(domain)
            self.assertFalse(
                verdict.is_phishing,
                f"Official brand domain {domain} was falsely flagged as phishing!"
            )
            self.assertLess(verdict.phishing_score, 50.0)

    def test_subdomain_brand_impersonation(self):
        """Detects brand tokens deeply embedded in deceptive subdomains."""
        phish_domains = [
            ("paypal.com.verify-account.security-update.xyz", "paypal"),
            ("appleid-login-auth.account-update.top", "apple"),
            ("chase-banking-security.online-portal.cfd", "chase"),
            ("binance-wallet-verify.crypto-auth.sbs", "binance"),
            ("netflix-billing-update.stream-login.rest", "netflix"),
        ]
        for domain, expected_brand in phish_domains:
            verdict = self.detector.analyze(domain)
            self.assertTrue(
                verdict.is_phishing,
                f"Phishing domain {domain} was not detected!"
            )
            self.assertEqual(verdict.targeted_brand, expected_brand)
            self.assertGreaterEqual(verdict.phishing_score, 65.0)

    def test_deceptive_keyword_chaining(self):
        """Detects domains chaining multiple credential harvesting keywords."""
        chain_domain = "login-secure-account-verify-portal.xyz"
        verdict = self.detector.analyze(chain_domain)
        self.assertTrue(verdict.is_phishing)
        self.assertGreaterEqual(len(verdict.deceptive_keywords), 2)
        self.assertGreaterEqual(verdict.phishing_score, 60.0)

    def test_shannon_entropy_calculation(self):
        """Validates mathematical Shannon entropy calculation."""
        # Single repeated character has 0 entropy
        self.assertEqual(self.detector.calculate_entropy("aaaaaaa"), 0.0)
        # Uniform distribution of 4 distinct chars = log2(4) = 2.0
        self.assertAlmostEqual(self.detector.calculate_entropy("abcd"), 2.0, places=3)
        # Empty string has 0 entropy
        self.assertEqual(self.detector.calculate_entropy(""), 0.0)

    def test_high_abuse_tld_multiplier(self):
        """Checks score elevation for domains hosted on high-abuse TLDs."""
        base_domain_safe = "login-verify.com"
        base_domain_abuse = "login-verify.xyz"
        v_safe = self.detector.analyze(base_domain_safe)
        v_abuse = self.detector.analyze(base_domain_abuse)
        self.assertGreater(v_abuse.phishing_score, v_safe.phishing_score)

    def test_verdict_properties_and_serialization(self):
        """Verifies property aliases and to_dict serialization."""
        domain = "paypal-account-security-alert.xyz"
        verdict = self.detector.analyze(domain)
        self.assertEqual(verdict.spoofed_brand, "paypal")
        self.assertTrue(len(verdict.primary_threat_vector) > 0)
        d = verdict.to_dict()
        self.assertTrue(d["is_phishing"])
        self.assertEqual(d["targeted_brand"], "paypal")
        self.assertIn("indicators", d)
        self.assertIn("phishing_score", d)


if __name__ == "__main__":
    unittest.main()
