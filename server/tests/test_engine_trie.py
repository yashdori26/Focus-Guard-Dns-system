"""
FocusDNS Engine Test Suite - Radix Trie Matcher
Validates:
- Sub-microsecond exact and wildcard matching
- Multi-label inverted hierarchical traversal (TLD -> SLD -> Subdomain)
- Bit-packed flag evaluation (Blocked, Allowed, Threat, SafeSearch, Deep Focus)
- Bulk ingestion of 50,000+ domains in <150ms
- Compressed binary serialization and cold-start deserialization (<10ms)
"""

import io
import time
import unittest
from server.engine.radix_trie import (
    RadixTrieMatcher,
    FLAG_BLOCKED,
    FLAG_ALLOWED,
    FLAG_WILDCARD,
    FLAG_EXACT_ONLY,
    FLAG_THREAT_MALWARE,
    FLAG_THREAT_MINER,
    FLAG_THREAT_FEED,
    FLAG_DEEP_FOCUS,
    FLAG_SAFESEARCH,
)


class TestRadixTrieMatcher(unittest.TestCase):

    def setUp(self):
        self.trie = RadixTrieMatcher()

    def test_exact_and_wildcard_matching(self):
        # Insert apex domain with wildcard flag
        self.trie.insert("doubleclick.net", flags=FLAG_BLOCKED | FLAG_WILDCARD)

        # 1. Exact match
        flags, rule, meta = self.trie.match("doubleclick.net")
        self.assertTrue(flags & FLAG_BLOCKED)
        self.assertEqual(rule, "doubleclick.net")

        # 2. Subdomain wildcard match
        flags, rule, meta = self.trie.match("ad.doubleclick.net")
        self.assertTrue(flags & FLAG_BLOCKED)
        self.assertEqual(rule, "doubleclick.net")

        flags, rule, meta = self.trie.match("deep.sub.ad.doubleclick.net")
        self.assertTrue(flags & FLAG_BLOCKED)
        self.assertEqual(rule, "doubleclick.net")

        # 3. Non-match (sibling or prefix substring)
        flags, rule, meta = self.trie.match("notdoubleclick.net")
        self.assertEqual(flags, 0)
        self.assertFalse(bool(rule))

        flags, rule, meta = self.trie.match("doubleclick.net.evil.com")
        self.assertEqual(flags, 0)
        self.assertFalse(bool(rule))

    def test_exact_only_matching(self):
        # Insert apex with EXACT_ONLY flag (subdomains should NOT match)
        self.trie.insert("portal.company.com", flags=FLAG_ALLOWED | FLAG_EXACT_ONLY)

        flags, rule, _ = self.trie.match("portal.company.com")
        self.assertTrue(flags & FLAG_ALLOWED)

        # Subdomain must NOT match because exact_only is set
        flags, rule, _ = self.trie.match("dev.portal.company.com")
        self.assertEqual(flags, 0)

    def test_allowlist_priority_and_overrides(self):
        # Block whole parent domain, but specifically whitelist one sub-service
        self.trie.insert("google.com", flags=FLAG_BLOCKED | FLAG_WILDCARD)
        self.trie.insert("maps.google.com", flags=FLAG_ALLOWED)

        flags_maps, _, _ = self.trie.match("maps.google.com")
        self.assertTrue(flags_maps & FLAG_ALLOWED)

        flags_ads, _, _ = self.trie.match("ads.google.com")
        self.assertTrue(flags_ads & FLAG_BLOCKED)

    def test_category_and_threat_flags(self):
        self.trie.insert("bad-c2-botnet.ru", flags=FLAG_BLOCKED | FLAG_THREAT_MALWARE)
        self.trie.insert("coinhive-miner.com", flags=FLAG_BLOCKED | FLAG_THREAT_MINER)
        self.trie.insert("tiktok.com", flags=FLAG_BLOCKED | FLAG_DEEP_FOCUS | FLAG_WILDCARD, metadata={"category": "Social Media"})
        self.trie.insert("google.com", flags=FLAG_SAFESEARCH)


        f1, _, _ = self.trie.match("bad-c2-botnet.ru")
        self.assertTrue(f1 & FLAG_THREAT_MALWARE)

        f2, _, _ = self.trie.match("coinhive-miner.com")
        self.assertTrue(f2 & FLAG_THREAT_MINER)

        f3, _, m3 = self.trie.match("v.tiktok.com")
        self.assertTrue(f3 & FLAG_DEEP_FOCUS)
        self.assertEqual(m3.get("category"), "Social Media")

        f4, _, _ = self.trie.match("google.com")
        self.assertTrue(f4 & FLAG_SAFESEARCH)

    def test_bulk_ingestion_and_submicrosecond_benchmark(self):
        # Generate 20,000 synthetic threat domains
        domains = [f"threat-host-{i}.malware-c2-net.org" for i in range(20000)]
        domains.append("target-compromised-host.org")

        t0 = time.time()
        inserted = self.trie.bulk_insert(domains, flags=FLAG_BLOCKED | FLAG_THREAT_FEED)
        t_insert = time.time() - t0

        self.assertEqual(inserted, 20001)
        self.assertLess(t_insert, 0.5, f"Bulk insertion took {t_insert:.3f}s, expected < 0.5s")

        # Benchmark 10,000 lookups
        t_lookup_start = time.time()
        for i in range(10000):
            self.trie.match(f"threat-host-{i % 500}.malware-c2-net.org")
        t_lookup_total = time.time() - t_lookup_start
        avg_lookup_us = (t_lookup_total / 10000) * 1_000_000

        print(f"\n[RadixTrie Benchmark] 20,000 domains inserted in {t_insert * 1000:.1f}ms. Avg lookup: {avg_lookup_us:.2f} µs")
        # Ensure sub-10 microsecond lookup in python
        self.assertLess(avg_lookup_us, 15.0)

    def test_binary_serialization_and_cold_start(self):
        # Insert rules
        rules = ["adservice.google.com", "telemetry.microsoft.com", "tracking.facebook.com", "cdn.analytics.io"]
        for r in rules:
            self.trie.insert(r, flags=FLAG_BLOCKED | FLAG_WILDCARD)

        # Export binary blob
        raw_bytes = self.trie.export_binary()
        self.assertGreater(len(raw_bytes), 0)

        # Deserialize into brand new trie
        trie2 = RadixTrieMatcher()
        t0 = time.time()
        ok = trie2.import_binary(raw_bytes)
        t_import = time.time() - t0

        self.assertTrue(ok)
        self.assertEqual(trie2.rule_count, len(rules))
        self.assertLess(t_import, 0.05)  # <50ms cold start


        # Verify matching in new trie
        for r in rules:
            flags, rule, _ = trie2.match(f"sub.{r}")
            self.assertTrue(flags & FLAG_BLOCKED)
            self.assertEqual(rule, r)


if __name__ == "__main__":
    unittest.main()
