"""
Unit Tests for Dynamic Multi-Class Domain Categorizer
Tests lexical tokenization, sub-word extraction, Softmax probability distribution,
TLD prior boosts, and classification across 8 standardized categories.
"""

import unittest
import sys
import os

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))))

from server.ai.domain_categorizer import DomainCategorizer, CategoryVerdict
from server.ai.category_lexicon import (
    CategoryLexicon,
    CAT_GAMING, CAT_SOCIAL, CAT_ADULT, CAT_PRODUCTIVITY,
    CAT_SHOPPING, CAT_STREAMING, CAT_CRYPTO_GAMBLING, CAT_MALWARE, CAT_UNCATEGORIZED
)


class TestDomainCategorizer(unittest.TestCase):
    """Verifies domain categorization accuracy and probability calibration."""

    def setUp(self):
        self.categorizer = DomainCategorizer()

    def test_tokenization_and_subwords(self):
        """Extracts sub-words, hyphenated parts, and digit-letter transitions."""
        tokens = [t[0] for t in self.categorizer.tokenize_domain("bet365-online-casino.com")]
        self.assertIn("bet", tokens)
        self.assertIn("365", tokens)
        self.assertIn("casino", tokens)

        steam_tokens = [t[0] for t in self.categorizer.tokenize_domain("steamcommunity.com")]
        self.assertIn("steam", steam_tokens)

    def test_gaming_classification(self):
        """Verifies gaming platforms are categorized as GAMING."""
        gaming_domains = [
            "steampowered.com",
            "epicgames.com",
            "playstation.com",
            "roblox.com",
            "minecraft.net",
        ]
        for domain in gaming_domains:
            v: CategoryVerdict = self.categorizer.predict(domain)
            self.assertEqual(
                v.primary_category, CAT_GAMING,
                f"Domain {domain} was expected GAMING, got {v.primary_category}"
            )
            self.assertTrue(v.is_distracting)
            self.assertGreater(v.confidence, 0.40)

    def test_social_media_classification(self):
        """Verifies social networks are categorized as SOCIAL_MEDIA."""
        social_domains = [
            "tiktok.com",
            "instagram.com",
            "twitter.com",
            "reddit.com",
            "facebook.com",
        ]
        for domain in social_domains:
            v = self.categorizer.predict(domain)
            self.assertEqual(
                v.primary_category, CAT_SOCIAL,
                f"Domain {domain} expected SOCIAL_MEDIA, got {v.primary_category}"
            )
            self.assertTrue(v.is_distracting)

    def test_productivity_classification(self):
        """Verifies work/productivity tools are categorized as PRODUCTIVITY_WORK."""
        work_domains = [
            "atlassian.com",
            "jira.com",
            "github.com",
            "linear.app",
            "trello.com",
            "figma.com",
            "slack.com",
            "notion.so",
        ]
        for domain in work_domains:
            v = self.categorizer.predict(domain)
            self.assertEqual(
                v.primary_category, CAT_PRODUCTIVITY,
                f"Domain {domain} expected PRODUCTIVITY_WORK, got {v.primary_category}"
            )
            self.assertFalse(v.is_distracting)

    def test_shopping_ecommerce_classification(self):
        """Verifies shopping/ecommerce domains are categorized as SHOPPING_ECOMMERCE."""
        shop_domains = [
            "amazon.com",
            "shopify.com",
            "ebay.com",
            "aliexpress.com",
            "walmart.com",
        ]
        for domain in shop_domains:
            v = self.categorizer.predict(domain)
            self.assertEqual(
                v.primary_category, CAT_SHOPPING,
                f"Domain {domain} expected SHOPPING_ECOMMERCE, got {v.primary_category}"
            )

    def test_streaming_entertainment_classification(self):
        """Verifies video/audio streaming services are categorized as STREAMING_ENTERTAINMENT."""
        stream_domains = [
            "netflix.com",
            "youtube.com",
            "spotify.com",
            "disneyplus.com",
            "hulu.com",
        ]
        for domain in stream_domains:
            v = self.categorizer.predict(domain)
            self.assertEqual(
                v.primary_category, CAT_STREAMING,
                f"Domain {domain} expected STREAMING_ENTERTAINMENT, got {v.primary_category}"
            )
            self.assertTrue(v.is_distracting)

    def test_crypto_gambling_classification(self):
        """Verifies crypto exchanges and gambling sites are categorized as CRYPTO_GAMBLING."""
        crypto_domains = [
            "binance.com",
            "stake.com",
            "coinbase.com",
            "bet365.com",
            "pokerstars.com",
        ]
        for domain in crypto_domains:
            v = self.categorizer.predict(domain)
            self.assertEqual(
                v.primary_category, CAT_CRYPTO_GAMBLING,
                f"Domain {domain} expected CRYPTO_GAMBLING, got {v.primary_category}"
            )
            self.assertTrue(v.is_distracting)

    def test_tld_prior_boosts(self):
        """TLDs with strong priors influence classification."""
        v_game = self.categorizer.predict("unknown-brand.game")
        self.assertEqual(v_game.primary_category, CAT_GAMING)

        v_adult = self.categorizer.predict("unknown-portal.xxx")
        self.assertEqual(v_adult.primary_category, CAT_ADULT)

    def test_softmax_probabilities_sum_to_one(self):
        """The category probability distribution must sum to approximately 1.0."""
        v = self.categorizer.predict("netflix.com")
        total_p = sum(v.category_probabilities.values())
        self.assertAlmostEqual(total_p, 1.0, places=2)

    def test_uncategorized_fallback(self):
        """Neutral domains without matching keywords fallback to UNCATEGORIZED."""
        v = self.categorizer.predict("asdfqwerzxcv-random123.org")
        self.assertEqual(v.primary_category, CAT_UNCATEGORIZED)
        self.assertFalse(v.is_distracting)

    def test_serialization(self):
        """Checks CategoryVerdict serialization."""
        v = self.categorizer.predict("github.com")
        d = v.to_dict()
        self.assertEqual(d["primary_category"], CAT_PRODUCTIVITY)
        self.assertIn("category_probabilities", d)
        self.assertIn("matched_tokens", d)
        self.assertIn("is_distracting", d)


if __name__ == "__main__":
    unittest.main()
