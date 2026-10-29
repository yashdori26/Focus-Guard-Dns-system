"""
Unit tests for Multi-Layout Keyboard Adjacency and Typo-Squatting Graph Engine.
Validates QWERTY/AZERTY/QWERTZ fat-finger detection, bitsquatting, omissions,
transpositions, life-safety exemptions, and Conditional Whitelisting Law.
"""

import unittest
from server.ai.typosquat_graph import (
    TyposquatGraphEngine,
    TyposquatVerdict,
    LIFE_SAFETY_DOMAINS
)


class TestTyposquatGraphEngine(unittest.TestCase):

    def setUp(self):
        self.engine = TyposquatGraphEngine(risk_threshold=65.0)

    def test_official_apex_never_flagged(self):
        """Legitimate brand apex domains must be classified as clean."""
        legitimate_domains = [
            "apple.com",
            "google.com",
            "paypal.com",
            "microsoft.com",
            "amazon.com"
        ]
        for domain in legitimate_domains:
            verdict = self.engine.evaluate(domain)
            self.assertFalse(verdict.is_typosquat, f"False positive on legitimate apex: {domain}")
            self.assertEqual(verdict.risk_score, 0.0)

    def test_qwerty_fat_finger_detection(self):
        """Neighboring key on QWERTY keyboard (e.g. 'w' next to 'a' -> 'wpple.com')."""
        verdict = self.engine.evaluate("wpple.com")
        self.assertTrue(verdict.is_typosquat)
        self.assertGreaterEqual(verdict.risk_score, 80.0)
        self.assertEqual(verdict.targeted_brand.lower(), "apple")
        self.assertIn("KEYBOARD_ADJACENCY_FAT_FINGER", verdict.primary_technique)

    def test_omission_typo_detection(self):
        """Single character missing from brand stem (e.g. 'aple.com' or 'paypl.com')."""
        verdict = self.engine.evaluate("paypl.com")
        self.assertTrue(verdict.is_typosquat)
        self.assertEqual(verdict.targeted_brand.lower(), "paypal")
        self.assertEqual(verdict.primary_technique, "CHARACTER_OMISSION")

    def test_duplication_typo_detection(self):
        """Single character duplicated (e.g. 'appple.com' or 'paypaal.com')."""
        verdict = self.engine.evaluate("appple.com")
        self.assertTrue(verdict.is_typosquat)
        self.assertEqual(verdict.targeted_brand.lower(), "apple")
        self.assertEqual(verdict.primary_technique, "CHARACTER_DUPLICATION")

    def test_transposition_swap_detection(self):
        """Adjacent character swap (e.g. 'appel.com' or 'goolge.com')."""
        verdict = self.engine.evaluate("goolge.com")
        self.assertTrue(verdict.is_typosquat)
        self.assertEqual(verdict.targeted_brand.lower(), "google")
        self.assertEqual(verdict.primary_technique, "CHARACTER_TRANSPOSITION")

    def test_bitsquatting_detection(self):
        """Single-bit memory flip mutation (e.g. 'p' (0x70) -> 'q' (0x71) in 'aqple.com')."""
        verdict = self.engine.evaluate("aqple.com")
        self.assertTrue(verdict.is_typosquat)
        self.assertEqual(verdict.targeted_brand.lower(), "apple")
        self.assertEqual(verdict.primary_technique, "BITSQUATTING_BIT_FLIP")

    def test_life_safety_exemption_never_flagged(self):
        """Life safety domains must never be flagged as typosquats."""
        for exempt in LIFE_SAFETY_DOMAINS:
            verdict = self.engine.evaluate(exempt)
            self.assertFalse(verdict.is_typosquat)
            self.assertTrue(verdict.is_exempt)
            self.assertEqual(verdict.risk_score, 0.0)

    def test_conditional_whitelisting_law_when_idle(self):
        """Whitelisting succeeds when idle and permits mutated domain."""
        self.assertFalse(self.engine.is_locked)

        domain = "wpple.com"
        success = self.engine.add_whitelist(domain)
        self.assertTrue(success)
        self.assertIn(domain, self.engine.get_whitelist())

        verdict = self.engine.evaluate(domain)
        self.assertFalse(verdict.is_typosquat)
        self.assertTrue(verdict.is_whitelisted)

        removed = self.engine.remove_whitelist(domain)
        self.assertTrue(removed)
        self.assertNotIn(domain, self.engine.get_whitelist())

    def test_conditional_whitelisting_law_denial_when_locked(self):
        """Whitelisting must raise PermissionError ERROR_ACCESS_DENIED (5) when locked."""
        self.engine.set_lock_state(is_locked=True, countdown_seconds=0)
        self.assertTrue(self.engine.is_locked)

        with self.assertRaises(PermissionError) as ctx:
            self.engine.add_whitelist("paypl.com")
        self.assertIn("ERROR_ACCESS_DENIED (5)", str(ctx.exception))

        with self.assertRaises(PermissionError) as ctx:
            self.engine.remove_whitelist("paypl.com")
        self.assertIn("ERROR_ACCESS_DENIED (5)", str(ctx.exception))

    def test_conditional_whitelisting_law_denial_when_timer_active(self):
        """Whitelisting must raise PermissionError if countdown_seconds > 0 even if is_locked is False."""
        self.engine.set_lock_state(is_locked=False, countdown_seconds=900)
        self.assertTrue(self.engine.is_locked)

        with self.assertRaises(PermissionError) as ctx:
            self.engine.add_whitelist("goolge.com")
        self.assertIn("ERROR_ACCESS_DENIED (5)", str(ctx.exception))


if __name__ == "__main__":
    unittest.main()
