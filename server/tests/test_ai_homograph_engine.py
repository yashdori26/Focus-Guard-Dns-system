"""
Unit Tests for AI Homograph & Typosquatting Defense Engine
Tests TR39 confusable lookalike detection, Damerau-Levenshtein typosquatting,
QWERTY keyboard adjacency substitutions, bitsquatting, and legitimate apex bypass.
"""

import unittest
import sys
import os

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))))

from server.ai.homograph_engine import HomographEngine, HomographVerdict
from server.ai.brand_dictionary import BrandDictionary


class TestHomographEngine(unittest.TestCase):
    """Verifies homograph and brand spoofing detection accuracy."""

    def setUp(self):
        self.engine = HomographEngine()

    def test_legitimate_apex_domains_not_flagged(self):
        """Legitimate brand apex domains must NEVER be flagged as threats."""
        legit_domains = [
            "apple.com",
            "google.com",
            "paypal.com",
            "microsoft.com",
            "amazon.com",
            "netflix.com",
            "chase.com",
            "binance.com",
            "facebook.com",
            "github.com",
        ]
        for domain in legit_domains:
            res: HomographVerdict = self.engine.analyze(domain)
            self.assertFalse(
                res.is_threat,
                f"Legitimate domain {domain} was incorrectly flagged as threat!"
            )
            self.assertEqual(res.attack_type, "NONE")
            self.assertEqual(res.risk_score, 0.0)

    def test_legitimate_subdomains_not_flagged(self):
        """Legitimate subdomains of protected brands should pass cleanly."""
        safe_subdomains = [
            "support.apple.com",
            "accounts.google.com",
            "developer.paypal.com",
            "portal.azure.microsoft.com",
            "aws.amazon.com",
        ]
        for sub in safe_subdomains:
            res: HomographVerdict = self.engine.analyze(sub)
            self.assertFalse(res.is_threat, f"Safe subdomain {sub} was falsely flagged!")

    def test_mixed_script_cyrillic_spoofing(self):
        """Detects mixed-script homographs where Cyrillic lookalikes replace Latin letters."""
        # Cyrillic 'а' (U+0430) instead of Latin 'a'
        spoof_apple = "\u0430pple.com"
        res = self.engine.analyze(spoof_apple)
        self.assertTrue(res.is_threat)
        self.assertEqual(res.spoofed_brand, "apple")
        self.assertIn("CONFUSABLE", res.attack_type)
        self.assertGreaterEqual(res.risk_score, 80.0)

        # Cyrillic 'о' in google
        spoof_google = "g\u043e\u043egle.com"
        res = self.engine.analyze(spoof_google)
        self.assertTrue(res.is_threat)
        self.assertEqual(res.spoofed_brand, "google")

        # Cyrillic 'р' in paypal
        spoof_paypal = "\u0440aypal.com"
        res = self.engine.analyze(spoof_paypal)
        self.assertTrue(res.is_threat)
        self.assertEqual(res.spoofed_brand, "paypal")

    def test_punycode_encoded_homograph(self):
        """Detects punycode encoded homograph domains."""
        # xn--pple-43d.com -> Cyrillic 'а' + pple.com
        punycode_apple = "xn--pple-43d.com"
        res = self.engine.analyze(punycode_apple)
        self.assertTrue(res.is_threat)
        self.assertEqual(res.spoofed_brand, "apple")
        self.assertGreaterEqual(res.risk_score, 80.0)

    def test_damerau_levenshtein_typosquatting(self):
        """Detects 1-edit distance typosquatting on major brand names."""
        typos = [
            ("goggle.com", "google"),
            ("paypa1.com", "paypal"),
            ("microsft.com", "microsoft"),
            ("amazn.com", "amazon"),
            ("netflx.com", "netflix"),
        ]
        for typo_domain, expected_brand in typos:
            res = self.engine.analyze(typo_domain)
            self.assertTrue(
                res.is_threat,
                f"Typosquatting domain {typo_domain} was not flagged!"
            )
            self.assertEqual(res.spoofed_brand, expected_brand)
            self.assertGreaterEqual(res.risk_score, 60.0)

    def test_qwerty_keyboard_adjacent_substitution(self):
        """Detects typos based on keyboard physical adjacency."""
        # 'o' and 'p' are neighbors; 'i' and 'o' are neighbors
        res = self.engine.analyze("giogle.com")
        self.assertTrue(res.is_threat)
        self.assertEqual(res.spoofed_brand, "google")

    def test_bitsquatting_detection(self):
        """Detects single-bit flip errors occurring in RAM or transmission."""
        # 'a' (01100001) flipped to 'c' (01100011) or similar
        res = self.engine.analyze("cpple.com")
        self.assertTrue(res.is_threat)
        self.assertEqual(res.spoofed_brand, "apple")

    def test_benign_unrelated_domains_not_flagged(self):
        """Regular domains that do not mimic brands should not trigger homograph alert."""
        benign = [
            "wikipedia.org",
            "weather.gov",
            "nytimes.com",
            "mit.edu",
            "kernel.org",
            "stackoverflow.com",
        ]
        for domain in benign:
            res = self.engine.analyze(domain)
            self.assertFalse(res.is_threat, f"Benign domain {domain} falsely flagged")
            self.assertEqual(res.attack_type, "NONE")

    def test_verdict_to_dict_serialization(self):
        """Verifies serialization of HomographVerdict."""
        res = self.engine.analyze("\u0430pple.com")
        d = res.to_dict()
        self.assertIn("is_threat", d)
        self.assertIn("attack_type", d)
        self.assertIn("risk_score", d)
        self.assertIn("spoofed_brand", d)
        self.assertIn("explanation", d)
        self.assertTrue(d["is_threat"])


if __name__ == "__main__":
    unittest.main()
