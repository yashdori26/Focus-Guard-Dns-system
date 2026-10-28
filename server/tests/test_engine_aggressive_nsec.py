"""
Unit & Integration Tests for FocusDNS RFC 8198 Aggressive NSEC Cache Subsystem
==============================================================================
Validates:
  1. RFC 4034 Section 6.1 Canonical DNS Name Order comparison
  2. NSEC range coverage computation for standard and wrap-around spans
  3. Proving non-existence (NXDOMAIN synthesis) without upstream recursion
  4. Proving NODATA (NOERROR) for absent record types at existing names
  5. TTL expiration and cache purge mechanisms
"""

import time
import unittest
from server.engine.aggressive_nsec import (
    compare_canonical_names,
    split_canonical_labels,
    NSECRange,
    AggressiveNSECCache,
)


class TestCanonicalNameOrder(unittest.TestCase):
    """Tests RFC 4034 Section 6.1 Canonical DNS Name Order."""

    def test_canonical_ordering_rules(self):
        # 1. example.com comes before a.example.com (shorter)
        self.assertEqual(compare_canonical_names("example.com", "a.example.com"), -1)
        self.assertEqual(compare_canonical_names("a.example.com", "example.com"), 1)

        # 2. a.example.com comes before b.example.com
        self.assertEqual(compare_canonical_names("a.example.com", "b.example.com"), -1)

        # 3. Same name returns 0
        self.assertEqual(compare_canonical_names("test.org", "test.org"), 0)

        # 4. Multi-level hierarchy: z.a.example.com vs b.example.com
        # In canonical order, comparing from root leftwards:
        # labels: com, example, a, z vs com, example, b
        # 'a' < 'b', so z.a.example.com comes before b.example.com!
        self.assertEqual(compare_canonical_names("z.a.example.com", "b.example.com"), -1)


class TestNSECRange(unittest.TestCase):
    """Tests RFC 8198 span coverage for NXDOMAIN and NODATA."""

    def test_standard_range_coverage(self):
        # Span: a.example.com to d.example.com
        span = NSECRange("a.example.com", "d.example.com", ["A", "NSEC"], ttl=300)
        self.assertFalse(span.is_wrap_around)

        # Names strictly inside span
        self.assertTrue(span.covers_name("b.example.com"))
        self.assertTrue(span.covers_name("c.example.com"))

        # Names outside span
        self.assertFalse(span.covers_name("a.example.com"))  # Boundary
        self.assertFalse(span.covers_name("d.example.com"))  # Boundary
        self.assertFalse(span.covers_name("e.example.com"))

    def test_wrap_around_range_coverage(self):
        # Span: z.example.com to a.example.com (wraps around apex)
        span = NSECRange("z.example.com", "a.example.com", ["A", "NSEC"], ttl=300)
        self.assertTrue(span.is_wrap_around)

        # Name lexically greater than z (e.g. zz.example.com)
        self.assertTrue(span.covers_name("zz.example.com"))

    def test_nodata_coverage(self):
        # Owner api.example.com only has A and TXT records
        span = NSECRange("api.example.com", "b.example.com", ["A", "TXT", "NSEC"], ttl=300)

        # AAAA is absent -> covers_nodata is True
        self.assertTrue(span.covers_nodata("api.example.com", "AAAA"))
        self.assertTrue(span.covers_nodata("api.example.com", "MX"))

        # A is present -> covers_nodata is False
        self.assertFalse(span.covers_nodata("api.example.com", "A"))

        # Query for different domain
        self.assertFalse(span.covers_nodata("other.example.com", "AAAA"))


class TestAggressiveNSECCache(unittest.TestCase):
    """Tests RFC 8198 cache synthesis and water-torture mitigation."""

    def setUp(self):
        self.cache = AggressiveNSECCache()
        self.zone = "example.com"
        # Store two NSEC ranges covering:
        # 1. alpha.example.com -> gamma.example.com
        # 2. host.example.com (only A and NSEC) -> next.example.com
        self.cache.store_nsec("alpha.example.com", "gamma.example.com", ["A", "NSEC"], ttl=300, zone_origin=self.zone)
        self.cache.store_nsec("host.example.com", "next.example.com", ["A", "NSEC"], ttl=300, zone_origin=self.zone)

    def test_synthesize_nxdomain(self):
        # beta.example.com falls between alpha and gamma
        covering = self.cache.find_covering_nxdomain("beta.example.com", self.zone)
        self.assertIsNotNone(covering)
        self.assertEqual(covering.owner_name, "alpha.example.com")

        # omega.example.com falls outside alpha->gamma and host->next
        covering2 = self.cache.find_covering_nxdomain("omega.example.com", self.zone)
        self.assertIsNone(covering2)

        stats = self.cache.get_stats()
        self.assertEqual(stats["synthesized_nxdomain"], 1)
        self.assertEqual(stats["total_cache_hits"], 1)

    def test_synthesize_nodata(self):
        # host.example.com lacks AAAA
        covering = self.cache.find_covering_nodata("host.example.com", "AAAA", self.zone)
        self.assertIsNotNone(covering)

        # host.example.com has A
        covering_a = self.cache.find_covering_nodata("host.example.com", "A", self.zone)
        self.assertIsNone(covering_a)

        stats = self.cache.get_stats()
        self.assertEqual(stats["synthesized_nodata"], 1)

    def test_purge_expired_ranges(self):
        # Store short-lived NSEC range
        self.cache.store_nsec("t1.test", "t3.test", ttl=1, zone_origin="test")
        time.sleep(1.05)
        purged = self.cache.purge_expired()
        self.assertGreaterEqual(purged, 1)


if __name__ == "__main__":
    unittest.main()
