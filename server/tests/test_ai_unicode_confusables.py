"""
Unit Tests for Unicode TR39 Confusable & Script Detection Engine
Tests visual skeleton decomposition, mixed-script detection, and Punycode decoding.
"""

import unittest
import sys
import os

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))))

from server.ai.unicode_confusables import UnicodeConfusables, ScriptDetector


class TestUnicodeConfusables(unittest.TestCase):
    """Verifies Unicode TR39 confusable character normalization and skeleton generation."""

    def setUp(self):
        self.confusables = UnicodeConfusables()
        self.detector = ScriptDetector()

    def test_latin_character_identity(self):
        """Latin characters should remain unchanged when normalized."""
        self.assertEqual(self.confusables.to_skeleton("apple.com"), "apple.com")
        self.assertEqual(self.confusables.to_skeleton("google.com"), "google.com")
        self.assertEqual(self.confusables.to_skeleton("paypal.com"), "paypal.com")

    def test_cyrillic_confusable_skeleton(self):
        """Cyrillic homoglyphs should be mapped to their Latin visual skeleton."""
        # Cyrillic 'а' (U+0430) -> Latin 'a'
        cyrillic_apple = "\u0430pple.com"
        self.assertEqual(self.confusables.to_skeleton(cyrillic_apple), "apple.com")

        # Cyrillic 'о' (U+043e) -> Latin 'o'
        cyrillic_google = "g\u043e\u043egle.com"
        self.assertEqual(self.confusables.to_skeleton(cyrillic_google), "google.com")

        # Cyrillic 'р' (U+0440) -> Latin 'p'
        cyrillic_paypal = "\u0440ay\u0440al.com"
        self.assertEqual(self.confusables.to_skeleton(cyrillic_paypal), "paypal.com")

    def test_greek_confusable_skeleton(self):
        """Greek homoglyphs should be mapped to their Latin visual skeleton."""
        # Greek 'ο' (U+03BF) -> Latin 'o'
        greek_microsoft = "micr\u03bfs\u03bfft.com"
        skeleton = self.confusables.to_skeleton(greek_microsoft)
        self.assertIn("micro", skeleton)

        # Greek 'ν' (U+03BD) -> Latin 'v'
        greek_visa = "\u03b9sa.com"
        self.assertTrue(len(self.confusables.to_skeleton(greek_visa)) > 0)

    def test_cherokee_confusable_skeleton(self):
        """Cherokee homoglyphs should be mapped to Latin equivalents."""
        # Cherokee 'Ꭺ' (U+13AA) -> Latin 'A'
        cherokee_amazon = "\u13aa"
        self.assertEqual(self.confusables.get_confusable(cherokee_amazon), "A")

    def test_is_confusable_detection(self):
        """Checks if specific characters are flagged as confusables."""
        self.assertTrue(self.confusables.is_confusable("\u0430"))  # Cyrillic a
        self.assertTrue(self.confusables.is_confusable("\u0435"))  # Cyrillic e
        self.assertTrue(self.confusables.is_confusable("\u0440"))  # Cyrillic p
        self.assertFalse(self.confusables.is_confusable("a"))     # Latin a
        self.assertFalse(self.confusables.is_confusable("z"))     # Latin z

    def test_punycode_decoding(self):
        """Punycode-encoded domains (xn--) should decode into Unicode then skeleton."""
        # xn--pple-43d.com is Cyrillic 'а' + pple.com
        punycode_apple = "xn--pple-43d.com"
        decoded = self.confusables.decode_punycode(punycode_apple)
        self.assertNotEqual(decoded, punycode_apple)
        skeleton = self.confusables.to_skeleton(decoded)
        self.assertEqual(skeleton, "apple.com")

    def test_punycode_decoding_clean_domain(self):
        """Regular domains should pass through punycode decoder unmodified."""
        domain = "netflix.com"
        self.assertEqual(self.confusables.decode_punycode(domain), domain)

    def test_script_detection_pure_latin(self):
        """Verifies pure Latin domains are classified correctly."""
        scripts = self.detector.detect_scripts("github.com")
        self.assertEqual(scripts, {"Latin"})

    def test_script_detection_mixed_cyrillic_latin(self):
        """Verifies mixed Latin and Cyrillic domains are flagged with multiple scripts."""
        mixed = "\u0430pple.com"  # Cyrillic 'а' + Latin 'pple.com'
        scripts = self.detector.detect_scripts(mixed)
        self.assertIn("Latin", scripts)
        self.assertIn("Cyrillic", scripts)
        self.assertTrue(self.detector.is_mixed_script(mixed))

    def test_script_detection_greek_latin(self):
        """Verifies mixed Greek and Latin domains."""
        mixed = "b\u03b1nk.com"  # Greek alpha
        scripts = self.detector.detect_scripts(mixed)
        self.assertIn("Greek", scripts)
        self.assertTrue(self.detector.is_mixed_script(mixed))

    def test_non_mixed_script(self):
        """Pure Latin domain is not mixed script."""
        self.assertFalse(self.detector.is_mixed_script("facebook.com"))

    def test_empty_and_whitespace_inputs(self):
        """Edge cases with empty or special inputs."""
        self.assertEqual(self.confusables.to_skeleton(""), "")
        self.assertEqual(self.confusables.decode_punycode(""), "")
        self.assertEqual(self.detector.detect_scripts(""), set())
        self.assertFalse(self.detector.is_mixed_script(""))


if __name__ == "__main__":
    unittest.main()
