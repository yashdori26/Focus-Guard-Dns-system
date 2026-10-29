"""
Unit Tests for Master AI Threat Hunting Engine & Orchestrator
Verifies parallel model dispatch, LRU cache performance, composite risk scoring,
Life-Safety exemptions, and strict enforcement of the Conditional Whitelisting Law.
"""

import unittest
import sys
import os

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))))

from server.ai.threat_hunting_engine import (
    ThreatHuntingEngine,
    AiThreatReport,
    ThreatVerdict,
    ACTION_ALLOW,
    ACTION_BLOCK_HOMOGRAPH,
    ACTION_BLOCK_PHISHING,
    ACTION_BLOCK_DGA,
    ACTION_BLOCK_DISTRACTION,
    ACTION_BYPASS_EXEMPT,
)


class TestThreatHuntingEngine(unittest.TestCase):
    """Verifies orchestration, composite scoring, caching, and whitelisting law."""

    def setUp(self):
        self.engine = ThreatHuntingEngine(max_cache_size=1000)

    def test_life_safety_exemptions_unconditionally_bypass(self):
        """Emergency calling and critical OS services bypass all threat checks."""
        exempt_domains = [
            "911.gov",
            "112.gov",
            "emergency.gov",
            "push.apple.com",
            "gateway.push.apple.com",
            "update.microsoft.com",
            "download.windowsupdate.com",
            "play.googleapis.com",
        ]
        for domain in exempt_domains:
            report: AiThreatReport = self.engine.hunt_domain(domain)
            self.assertFalse(report.is_threat)
            self.assertEqual(report.composite_risk_score, 0.0)
            self.assertEqual(report.recommended_action, ACTION_BYPASS_EXEMPT)

    def test_homograph_threat_detection(self):
        """Mixed-script Unicode homograph triggers immediate block."""
        cyrillic_apple = "\u0430pple.com"
        report = self.engine.hunt_domain(cyrillic_apple)
        self.assertTrue(report.is_threat)
        self.assertEqual(report.recommended_action, ACTION_BLOCK_HOMOGRAPH)
        self.assertGreaterEqual(report.composite_risk_score, 80.0)
        self.assertEqual(report.threat_type, "HOMOGRAPH_TYPOSQUAT")
        self.assertEqual(report.detected_brand, "apple")

    def test_zero_hour_phishing_detection(self):
        """Deep subdomain brand impersonation triggers phishing block."""
        phish_domain = "paypal.com.verify-account.security-update.xyz"
        report = self.engine.hunt_domain(phish_domain)
        self.assertTrue(report.is_threat)
        self.assertEqual(report.recommended_action, ACTION_BLOCK_PHISHING)
        self.assertGreaterEqual(report.composite_risk_score, 70.0)
        self.assertEqual(report.threat_type, "PHISHING_ZERO_HOUR")
        self.assertEqual(report.detected_brand, "paypal")

    def test_dga_malware_detection(self):
        """Algorithmic high-entropy consonant domains trigger DGA block."""
        dga_domain = "bcdfghjklmnpqrstvwxyz.org"
        report = self.engine.hunt_domain(dga_domain)
        self.assertTrue(report.is_threat)
        self.assertEqual(report.recommended_action, ACTION_BLOCK_DGA)
        self.assertGreaterEqual(report.composite_risk_score, 80.0)
        self.assertEqual(report.threat_type, "DGA_MALWARE")
        self.assertIsNotNone(report.dga_family)

    def test_benign_domain_allowed_and_categorized(self):
        """Legitimate productive domains are allowed and categorized."""
        report = self.engine.hunt_domain("github.com")
        self.assertFalse(report.is_threat)
        self.assertEqual(report.recommended_action, ACTION_ALLOW)
        self.assertLess(report.composite_risk_score, 25.0)
        self.assertEqual(report.primary_category, "PRODUCTIVITY_WORK")
        self.assertFalse(report.is_distracting)

    def test_lru_cache_hit_and_speedup(self):
        """Subsequent queries for the same domain hit memory cache (< 1µs)."""
        domain = "netflix.com"
        # First query: Cache Miss
        r1 = self.engine.hunt_domain(domain)
        self.assertFalse(r1.cached)

        # Second query: Cache Hit
        r2 = self.engine.hunt_domain(domain)
        self.assertTrue(r2.cached)
        self.assertEqual(r1.composite_risk_score, r2.composite_risk_score)
        self.assertEqual(r1.recommended_action, r2.recommended_action)

    def test_conditional_whitelisting_law_idle(self):
        """
        When system is IDLE (Protection OFF, Timer 0):
        Whitelisting additions and removals proceed with ZERO friction.
        """
        self.engine.set_focus_lock(locked=False, remaining_seconds=0)
        self.assertTrue(self.engine.can_modify_whitelist())

        # Whitelisting domain should succeed cleanly
        success = self.engine.add_whitelist("custom-tool.internal")
        self.assertTrue(success)

        # Whitelisted domain must now bypass checks
        report = self.engine.hunt_domain("custom-tool.internal")
        self.assertFalse(report.is_threat)
        self.assertEqual(report.recommended_action, ACTION_ALLOW)

        # Removal should also succeed cleanly
        removed = self.engine.remove_whitelist("custom-tool.internal")
        self.assertTrue(removed)

    def test_conditional_whitelisting_law_active_lock_blocked(self):
        """
        Inviolable Principle: When Deep Focus mode is ACTIVE or countdown timer > 0,
        whitelisting modifications are STRICTLY FORBIDDEN and MUST raise PermissionError.
        """
        # Activate Focus Mode with 30-minute lock
        self.engine.set_focus_lock(locked=True, remaining_seconds=1800)
        self.assertFalse(self.engine.can_modify_whitelist())

        # Attempting to add domain to whitelist MUST fail
        with self.assertRaises(PermissionError) as ctx:
            self.engine.add_whitelist("bypassed-social-media.com")
        self.assertIn("ERROR_ACCESS_DENIED (5)", str(ctx.exception))

        # Attempting to remove domain from whitelist MUST fail
        with self.assertRaises(PermissionError):
            self.engine.remove_whitelist("bypassed-social-media.com")

    def test_batch_hunting(self):
        """Batch hunt classifies multiple domains efficiently."""
        domains = [
            "google.com",
            "\u0430pple.com",
            "paypal.com.verify-account.security-update.xyz",
            "bcdfghjklmnpqrstvwxyz.org",
        ]
        reports = self.engine.batch_hunt(domains)
        self.assertEqual(len(reports), 4)
        self.assertFalse(reports[0].is_threat)  # google.com
        self.assertTrue(reports[1].is_threat)   # homograph
        self.assertTrue(reports[2].is_threat)   # phishing
        self.assertTrue(reports[3].is_threat)   # dga

    def test_flush_cache_and_telemetry(self):
        """Verifies cache flushing and telemetry collection."""
        self.engine.hunt_domain("domain1.com")
        self.engine.hunt_domain("domain2.com")
        telem = self.engine.get_telemetry()
        self.assertGreaterEqual(telem["total_domains_analyzed"], 2)
        self.assertGreaterEqual(telem["cache_size"], 2)

        flushed = self.engine.flush_cache()
        self.assertEqual(flushed, 2)
        self.assertEqual(len(self.engine._cache), 0)


if __name__ == "__main__":
    unittest.main()
