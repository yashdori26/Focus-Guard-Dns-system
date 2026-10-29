"""
Unit Tests for On-Device DGA Neural Network & Markov Classifier
Tests 16-dimensional feature extraction, 3-layer MLP forward pass,
synthetic malware generation across 20 families, and family attribution.
"""

import unittest
import sys
import os

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))))

from server.ai.dga_neural_classifier import DgaNeuralClassifier, DgaVerdict
from server.ai.dga_families import DgaGenerator, DGAFamilyRegistry, DGA_FAMILIES


class TestDgaNeuralClassifier(unittest.TestCase):
    """Verifies DGA neural classification and feature extraction."""

    def setUp(self):
        self.classifier = DgaNeuralClassifier()

    def test_feature_extraction_dimensions(self):
        """Feature vector must have exactly 16 normalized floating-point dimensions."""
        features, feature_dict = self.classifier.extract_features("google.com")
        self.assertEqual(len(features), 16)
        self.assertIsInstance(feature_dict, dict)
        self.assertIn("shannon_entropy", feature_dict)
        self.assertIn("vowel_ratio", feature_dict)
        self.assertIn("bigram_score", feature_dict)

        # Values should be bounded
        for f in features:
            self.assertGreaterEqual(f, 0.0)
            self.assertLessEqual(f, 1.0)

    def test_benign_domains_classified_as_non_dga(self):
        """Benign human-registered domains must NOT be flagged as DGA."""
        benign_domains = [
            "google.com",
            "wikipedia.org",
            "github.com",
            "stackoverflow.com",
            "nytimes.com",
            "apple.com",
            "microsoft.com",
            "reddit.com",
            "amazon.com",
        ]
        for domain in benign_domains:
            verdict: DgaVerdict = self.classifier.predict(domain)
            self.assertFalse(
                verdict.is_dga,
                f"Benign domain {domain} was falsely flagged as DGA (prob={verdict.probability})!"
            )
            self.assertLess(verdict.probability, 0.35)

    def test_high_entropy_vowelless_domain_flagged_as_dga(self):
        """High-entropy consonant strings must trigger DGA classification."""
        dga_domains = [
            "xqzmnprtwkbv.com",
            "bcdfghjklmnpqrstvwxyz.org",
            "7f9a2b8c4d1e.info",
            "zxcvbnmasdfghjklqwerty.biz",
        ]
        for domain in dga_domains:
            verdict = self.classifier.predict(domain)
            self.assertTrue(
                verdict.is_dga,
                f"DGA domain {domain} was missed by classifier (prob={verdict.probability})!"
            )
            self.assertGreaterEqual(verdict.probability, 0.65)
            self.assertIsNotNone(verdict.predicted_family)

    def test_dga_family_registry(self):
        """Verifies that all 20 documented DGA malware families are registered."""
        families = DGAFamilyRegistry.get_supported_families()
        self.assertGreaterEqual(len(families), 20)
        self.assertIn("Conficker", families)
        self.assertIn("GameOver Zeus (GOZ)", families)
        self.assertIn("Necurs", families)
        self.assertIn("Mirai", families)
        self.assertIn("Qakbot", families)
        self.assertIn("Matsnu", families)
        self.assertIn("Bamital", families)

    def test_synthetic_dga_generation(self):
        """Generates synthetic DGA domains using family profiles."""
        for family_name in ["Conficker", "Mirai", "Necurs", "Qakbot"]:
            domain = DgaGenerator.generate(family_name, seed=12345)
            self.assertIsInstance(domain, str)
            self.assertIn(".", domain)
            parts = domain.split(".")
            self.assertGreaterEqual(len(parts[0]), 3)

    def test_malware_family_attribution(self):
        """Verifies family attribution rules."""
        # 12-char hex -> Bamital
        bamital_domain = "0123456789ab.com"
        v_bamital = self.classifier.predict(bamital_domain)
        self.assertEqual(v_bamital.predicted_family, "Bamital")

        # Long hex -> GameOver Zeus
        goz_domain = "0123456789abcdef0123456789abcdef.net"
        v_goz = self.classifier.predict(goz_domain)
        self.assertEqual(v_goz.predicted_family, "GameOver Zeus (GOZ)")

        # No vowels -> Necurs
        necurs_domain = "bcdfghjklmnpqr.org"
        v_necurs = self.classifier.predict(necurs_domain)
        self.assertEqual(v_necurs.predicted_family, "Necurs")

    def test_to_dict_and_property_aliases(self):
        """Checks DgaVerdict serialization and property aliases."""
        verdict = self.classifier.predict("0123456789ab.com")
        self.assertEqual(verdict.attributed_family, verdict.predicted_family)
        d = verdict.to_dict()
        self.assertIn("is_dga", d)
        self.assertIn("probability", d)
        self.assertIn("confidence_score", d)
        self.assertIn("predicted_family", d)
        self.assertIn("entropy", d)
        self.assertIn("features", d)


if __name__ == "__main__":
    unittest.main()
