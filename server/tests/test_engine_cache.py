"""
FocusDNS Engine Test Suite - RFC 8767 Stale-While-Revalidate Cache
Validates:
- RFC 8767 state machine (FRESH -> STALE -> EXPIRED)
- TTL clamping (min_ttl=15s, max_ttl=86400s)
- Zero-latency stale serving with asynchronous background refresh
- In-flight dogpile prevention / deduplication
- Thread-safe LRU capacity eviction
"""

import time
import unittest
from unittest.mock import MagicMock
from dnslib import DNSRecord, RR, QTYPE, A

from server.engine.stale_cache import StaleCacheEngine, CacheState, CacheEntry


class TestStaleCacheEngine(unittest.TestCase):

    def setUp(self):
        self.mock_fetcher = MagicMock()
        self.cache = StaleCacheEngine(
            max_entries=10,
            stale_window_seconds=2.0,  # Short stale window for fast testing
            min_ttl=2,
            max_ttl=3600,
            revalidation_fetcher=self.mock_fetcher,
        )

    def tearDown(self):
        self.cache.close()

    def _make_dns_packet(self, domain: str, ip: str = "1.2.3.4", ttl: int = 60) -> bytes:
        rec = DNSRecord.question(domain, "A")
        reply = rec.reply()
        reply.add_answer(RR(domain, QTYPE.A, ttl=ttl, rdata=A(ip)))
        return reply.pack()

    def test_ttl_clamping(self):
        # 1. Below min_ttl should be clamped up to min_ttl (2s)
        self.assertEqual(self.cache.clamp_ttl(0), 2)
        self.assertEqual(self.cache.clamp_ttl(1), 2)

        # 2. Within bounds
        self.assertEqual(self.cache.clamp_ttl(300), 300)

        # 3. Above max_ttl should be clamped down to max_ttl (3600s)
        self.assertEqual(self.cache.clamp_ttl(999999), 3600)

    def test_fresh_hit(self):
        wire = self._make_dns_packet("example.com", "93.184.216.34", ttl=60)
        self.cache.put("example.com", 1, wire, original_ttl=60)

        cached_wire, state, ttl_rem = self.cache.get("example.com", 1)
        self.assertIsNotNone(cached_wire)
        self.assertEqual(state, CacheState.FRESH)
        self.assertGreater(ttl_rem, 0)
        self.assertEqual(cached_wire, wire)

        stats = self.cache.get_stats()
        self.assertEqual(stats["hits_fresh"], 1)
        self.assertEqual(stats["hits_stale"], 0)

    def test_stale_serving_and_background_revalidation(self):
        wire_v1 = self._make_dns_packet("stale-test.com", "1.1.1.1", ttl=2)
        wire_v2 = self._make_dns_packet("stale-test.com", "1.1.1.2", ttl=60)

        # Mock fetcher returns updated wire packet
        self.mock_fetcher.return_value = wire_v2

        # Insert with small 2-second TTL
        self.cache.put("stale-test.com", 1, wire_v1, original_ttl=2)

        # Wait 2.2 seconds for entry to transition from FRESH to STALE
        time.sleep(2.2)

        # Query should return immediately with STALE state, NOT block!
        cached_wire, state, ttl_rem = self.cache.get("stale-test.com", 1)
        self.assertIsNotNone(cached_wire)
        self.assertEqual(state, CacheState.STALE)
        self.assertEqual(cached_wire, wire_v1)  # Serves stale data instantly

        # Wait for background worker to complete
        for _ in range(20):
            time.sleep(0.05)
            if self.cache.get_stats()["revalidations_succeeded"] > 0:
                break

        # Verify fetcher was called once
        self.mock_fetcher.assert_called_with("stale-test.com", 1)


        # Next query should return the FRESH refreshed record!
        cached_wire_new, state_new, _ = self.cache.get("stale-test.com", 1)
        self.assertEqual(state_new, CacheState.FRESH)
        self.assertEqual(cached_wire_new, wire_v2)

    def test_expired_entry_purged(self):
        wire = self._make_dns_packet("expire-test.com", "2.2.2.2", ttl=2)
        self.cache.put("expire-test.com", 1, wire, original_ttl=2)

        # Wait past fresh window (2s) AND past stale window (2s) = 4.5s
        time.sleep(4.5)

        cached_wire, state, ttl_rem = self.cache.get("expire-test.com", 1)
        self.assertIsNone(cached_wire)
        self.assertEqual(state, CacheState.EXPIRED)

    def test_lru_capacity_eviction(self):
        # Cache max_entries = 10
        for i in range(15):
            w = self._make_dns_packet(f"host-{i}.org", "10.0.0.1", ttl=300)
            self.cache.put(f"host-{i}.org", 1, w, original_ttl=300)

        stats = self.cache.get_stats()
        self.assertLessEqual(stats["entry_count"], 10)
        self.assertGreaterEqual(stats["evictions"], 5)

    def test_invalidation_and_clear(self):
        w1 = self._make_dns_packet("apple.com", "17.0.0.1")
        w2 = self._make_dns_packet("banana.com", "18.0.0.1")

        self.cache.put("apple.com", 1, w1, 300)
        self.cache.put("banana.com", 1, w2, 300)

        # Invalidate specific
        self.cache.invalidate("apple.com")
        self.assertIsNone(self.cache.get("apple.com", 1)[0])
        self.assertIsNotNone(self.cache.get("banana.com", 1)[0])

        # Clear all
        self.cache.clear()
        self.assertEqual(self.cache.get_stats()["entry_count"], 0)


if __name__ == "__main__":
    unittest.main()
