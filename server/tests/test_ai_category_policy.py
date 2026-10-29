"""
Unit tests for AI Category Policy Engine.
Validates profile evaluation, life safety exemptions, and Conditional Whitelisting Law.
"""

import unittest
from server.engine.ai_category_policy import (
    AiCategoryPolicyEngine,
    CategoryPolicyProfile,
    CategoryPolicyDecision,
    PROFILE_FOCUS_WORK,
    PROFILE_FOCUS_STUDY,
    PROFILE_CHILD_SAFE,
    PROFILE_STRICT_SECURITY,
    ACTION_ALLOW,
    ACTION_BLOCK,
    ACTION_EXEMPT,
    LIFE_SAFETY_DOMAINS
)
from server.ai.category_lexicon import (
    CAT_GAMING, CAT_SOCIAL, CAT_ADULT, CAT_PRODUCTIVITY,
    CAT_SHOPPING, CAT_STREAMING, CAT_CRYPTO_GAMBLING, CAT_MALWARE
)


class TestAiCategoryPolicyEngine(unittest.TestCase):

    def setUp(self):
        self.engine = AiCategoryPolicyEngine(profile=PROFILE_FOCUS_WORK)

    def test_predefined_profiles_structure(self):
        """Validates predefined profiles contain expected categories."""
        self.assertIn(CAT_GAMING, PROFILE_FOCUS_WORK.blocked_categories)
        self.assertIn(CAT_SOCIAL, PROFILE_FOCUS_WORK.blocked_categories)
        self.assertIn(CAT_ADULT, PROFILE_FOCUS_WORK.blocked_categories)
        self.assertIn(CAT_PRODUCTIVITY, PROFILE_FOCUS_WORK.allowed_categories)

        self.assertIn(CAT_SHOPPING, PROFILE_FOCUS_STUDY.blocked_categories)
        self.assertIn(CAT_ADULT, PROFILE_CHILD_SAFE.blocked_categories)
        self.assertIn(CAT_MALWARE, PROFILE_STRICT_SECURITY.blocked_categories)

    def test_focus_work_blocks_gaming_and_social(self):
        """Verifies gaming and social domains are blocked under focus_work."""
        gaming_decision = self.engine.evaluate("playstation.com")
        self.assertTrue(gaming_decision.is_blocked)
        self.assertEqual(gaming_decision.action, ACTION_BLOCK)
        self.assertEqual(gaming_decision.category, CAT_GAMING)

        social_decision = self.engine.evaluate("instagram.com")
        self.assertTrue(social_decision.is_blocked)
        self.assertEqual(social_decision.action, ACTION_BLOCK)
        self.assertEqual(social_decision.category, CAT_SOCIAL)

    def test_focus_work_allows_productivity(self):
        """Verifies productivity domains are allowed under focus_work."""
        prod_decision = self.engine.evaluate("github.com")
        self.assertFalse(prod_decision.is_blocked)
        self.assertEqual(prod_decision.action, ACTION_ALLOW)

    def test_life_safety_exemption_never_blocked(self):
        """Verifies emergency calling and system updates are NEVER blocked."""
        for exempt in LIFE_SAFETY_DOMAINS:
            dec = self.engine.evaluate(exempt)
            self.assertFalse(dec.is_blocked, f"{exempt} must never be blocked!")
            self.assertEqual(dec.action, ACTION_EXEMPT)
            self.assertTrue(dec.is_exempt)

        # Also test subdomains
        sub_exempt = self.engine.evaluate("siren.911.gov")
        self.assertFalse(sub_exempt.is_blocked)
        self.assertEqual(sub_exempt.action, ACTION_EXEMPT)

    def test_conditional_whitelisting_law_when_idle(self):
        """Whitelisting must succeed with 0 friction when idle."""
        self.assertFalse(self.engine.is_locked)
        success = self.engine.add_whitelist("steamcommunity.com")
        self.assertTrue(success)
        self.assertIn("steamcommunity.com", self.engine.get_whitelist())

        # Now evaluating steamcommunity.com should be ALLOWED because of whitelist
        dec = self.engine.evaluate("steamcommunity.com")
        self.assertFalse(dec.is_blocked)
        self.assertEqual(dec.action, ACTION_ALLOW)
        self.assertTrue(dec.is_whitelisted)

        # Removal succeeds when idle
        removed = self.engine.remove_whitelist("steamcommunity.com")
        self.assertTrue(removed)
        self.assertNotIn("steamcommunity.com", self.engine.get_whitelist())

    def test_conditional_whitelisting_law_denial_when_locked(self):
        """Whitelisting must raise PermissionError ERROR_ACCESS_DENIED (5) when locked."""
        self.engine.set_lock_state(is_locked=True, countdown_seconds=0)
        self.assertTrue(self.engine.is_locked)

        with self.assertRaises(PermissionError) as ctx:
            self.engine.add_whitelist("twitch.tv")
        self.assertIn("ERROR_ACCESS_DENIED (5)", str(ctx.exception))

        with self.assertRaises(PermissionError) as ctx:
            self.engine.remove_whitelist("twitch.tv")
        self.assertIn("ERROR_ACCESS_DENIED (5)", str(ctx.exception))

        with self.assertRaises(PermissionError) as ctx:
            self.engine.clear_whitelist()
        self.assertIn("ERROR_ACCESS_DENIED (5)", str(ctx.exception))

    def test_conditional_whitelisting_law_denial_when_timer_active(self):
        """Whitelisting must raise PermissionError if countdown_seconds > 0 even if is_locked is False."""
        self.engine.set_lock_state(is_locked=False, countdown_seconds=1800)
        self.assertTrue(self.engine.is_locked)

        with self.assertRaises(PermissionError) as ctx:
            self.engine.add_whitelist("reddit.com")
        self.assertIn("ERROR_ACCESS_DENIED (5)", str(ctx.exception))

    def test_cache_hits_and_telemetry(self):
        """Verifies repeated queries hit in-memory LRU cache and increment telemetry."""
        domain = "netflix.com"
        d1 = self.engine.evaluate(domain)
        d2 = self.engine.evaluate(domain)

        self.assertEqual(d1.category, d2.category)
        self.assertEqual(d1.action, d2.action)

        telemetry = self.engine.get_telemetry()
        self.assertGreaterEqual(telemetry["total_evaluations"], 2)
        self.assertGreaterEqual(telemetry["cache_hits"], 1)

    def test_profile_switching(self):
        """Verifies switching profile clears cache and changes evaluation logic."""
        # Under CHILD_SAFE, twitch.tv (gaming/streaming) is allowed because only Adult/Crypto/Malware are blocked
        self.engine.set_profile(PROFILE_CHILD_SAFE)
        dec = self.engine.evaluate("twitch.tv")
        self.assertFalse(dec.is_blocked)

        # Under FOCUS_WORK, twitch.tv is blocked
        self.engine.set_profile(PROFILE_FOCUS_WORK)
        dec2 = self.engine.evaluate("twitch.tv")
        self.assertTrue(dec2.is_blocked)


if __name__ == "__main__":
    unittest.main()
