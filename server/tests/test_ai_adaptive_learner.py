"""
Unit tests for On-Device Continuous Adaptive Learner and Safety Watchdog.
Validates online gradient descent, weight delta clipping, L2 penalty,
automatic benchmark rollback, life-safety exemptions, and Conditional Whitelisting Law.
"""

import unittest
from server.ai.adaptive_learner import (
    AdaptiveLearner,
    LIFE_SAFETY_DOMAINS
)


class TestAdaptiveLearner(unittest.TestCase):

    def setUp(self):
        self.learner = AdaptiveLearner(learning_rate=0.008)

    def test_benign_evaluation_and_golden_benchmarks(self):
        """Initial weights must correctly identify benign golden domains."""
        benign_domains = ["apple.com", "google.com", "wikipedia.org", "github.com"]
        for domain in benign_domains:
            is_threat, prob = self.learner.evaluate_domain(domain)
            self.assertFalse(is_threat, f"Initial weights misclassified {domain}")
            self.assertLess(prob, 0.50)

    def test_threat_evaluation_initial(self):
        """Initial weights should flag zero-vowel high-entropy DGA domain."""
        is_threat, prob = self.learner.evaluate_domain("bcdfghjklmnpqrstvwxyz.org")
        self.assertTrue(is_threat)
        self.assertGreaterEqual(prob, 0.50)

    def test_safe_online_training_step(self):
        """Online training step updates weights within safety bounds."""
        initial_telemetry = self.learner.get_telemetry()
        initial_steps = initial_telemetry["total_training_steps"]

        # Train on a verified phishing pattern
        success = self.learner.train_sample("phishing-login-update.biz", target_label=1)
        self.assertTrue(success)

        updated_telemetry = self.learner.get_telemetry()
        self.assertEqual(updated_telemetry["total_training_steps"], initial_steps + 1)
        self.assertEqual(updated_telemetry["rollbacks_triggered"], 0)

    def test_life_safety_cannot_be_trained_as_threat(self):
        """Attempting to train an exempt life-safety domain as a threat must raise ValueError."""
        for exempt in LIFE_SAFETY_DOMAINS:
            with self.assertRaises(ValueError) as ctx:
                self.learner.train_sample(exempt, target_label=1)
            self.assertIn("INVIOLABLE SAFETY VIOLATION", str(ctx.exception))

    def test_life_safety_domain_always_returns_clean(self):
        """Exempt domains always evaluate as clean with 0.0 threat probability."""
        for exempt in LIFE_SAFETY_DOMAINS:
            is_threat, prob = self.learner.evaluate_domain(exempt)
            self.assertFalse(is_threat)
            self.assertEqual(prob, 0.0)

    def test_conditional_whitelisting_law_when_idle(self):
        """Whitelisting and training benign feedback works when idle."""
        self.assertFalse(self.learner.is_locked)

        domain = "legitimate-internal-tool.com"
        success = self.learner.add_whitelist(domain)
        self.assertTrue(success)
        self.assertIn(domain, self.learner.get_whitelist())

        # Training benign feedback on normal domain succeeds when idle
        train_success = self.learner.train_sample(domain, target_label=0)
        self.assertTrue(train_success)

        # Removal succeeds when idle
        removed = self.learner.remove_whitelist(domain)
        self.assertTrue(removed)
        self.assertNotIn(domain, self.learner.get_whitelist())

    def test_conditional_whitelisting_law_denial_when_locked(self):
        """Whitelisting and benign sample learning must be rejected when locked."""
        self.learner.set_lock_state(is_locked=True, countdown_seconds=0)
        self.assertTrue(self.learner.is_locked)

        with self.assertRaises(PermissionError) as ctx:
            self.learner.add_whitelist("sample.com")
        self.assertIn("ERROR_ACCESS_DENIED (5)", str(ctx.exception))

        with self.assertRaises(PermissionError) as ctx:
            self.learner.train_sample("sample.com", target_label=0)
        self.assertIn("ERROR_ACCESS_DENIED (5)", str(ctx.exception))

    def test_conditional_whitelisting_law_denial_when_timer_active(self):
        """Whitelisting must raise PermissionError if countdown_seconds > 0 even if is_locked is False."""
        self.learner.set_lock_state(is_locked=False, countdown_seconds=1800)
        self.assertTrue(self.learner.is_locked)

        with self.assertRaises(PermissionError) as ctx:
            self.learner.add_whitelist("domain.com")
        self.assertIn("ERROR_ACCESS_DENIED (5)", str(ctx.exception))

    def test_rollback_on_poisoning_attempt(self):
        """Watchdog must rollback weights if update attempts to poison benign domains."""
        # Force a massive update trying to flip benign features to threats
        # The watchdog should detect that golden benchmark apple.com or google.com is harmed and rollback
        for _ in range(20):
            # Attempting to train google.com-like features as threats
            self.learner.train_sample("google-services-auth.com", target_label=1, sample_weight=10.0)

        # Confirm google.com is STILL classified as benign (watchdog protected it)
        is_threat, prob = self.learner.evaluate_domain("google.com")
        self.assertFalse(is_threat, "Watchdog failed to protect golden benchmark!")


if __name__ == "__main__":
    unittest.main()
