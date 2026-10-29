"""
server/tests/test_router_stub_daemon.py
Unit Test Suite for Router DNS Stub Daemon, Local Cache, Fail-Safe Fallback, and Telemetry Reporter.

Verifies:
1. Zero-latency in-memory DNS caching with TTL expiration.
2. LRU cache eviction when capacity limit is reached.
3. Transaction ID preservation on cached DNS response packets.
4. Inviolable Fail-Safe Guarantee: local LAN queries fall back gracefully when upstream times out.
5. Router Telemetry Reporter health snapshots and ring buffer bounds.
6. Router-level Conditional Uninstallation validation (strict lock propagation).
"""

import unittest
import time
from router.daemon.router_stub_daemon import (
    RouterStubDaemon,
    DnsCacheEntry,
)
from router.daemon.router_telemetry_reporter import (
    RouterTelemetryReporter,
    RouterTelemetrySnapshot,
)
from router.openwrt.mac_profile_router import MacProfileRouter


class TestRouterStubDaemon(unittest.TestCase):
    """Exhaustive tests for router forwarding daemon, cache, and fail-safe logic."""

    def setUp(self):
        self.mac_router = MacProfileRouter(default_profile="profile_home_primary")
        self.daemon = RouterStubDaemon(
            listen_ip="127.0.0.1",
            listen_port=5353,
            default_profile_id="profile_home_primary",
            upstream_host="127.0.0.1",
            upstream_port=8853,
            failsafe_ip="127.0.0.1",
            failsafe_port=53,
            failsafe_enabled=True,
            max_cache_entries=10,
            mac_router=self.mac_router,
        )

    def test_dns_cache_entry_ttl_and_expiration(self):
        """Verifies cache entry expiration and remaining TTL calculation."""
        entry = DnsCacheEntry(raw_response=b"\x00\x01\x81\x80\x00\x01", ttl_seconds=2)
        self.assertFalse(entry.is_expired())
        self.assertGreaterEqual(entry.get_remaining_ttl(), 1)

        # Force expiry
        entry.expires_at = time.time() - 1
        self.assertTrue(entry.is_expired())
        self.assertEqual(entry.get_remaining_ttl(), 1)

    def test_cache_insertion_retrieval_and_eviction(self):
        """Verifies storing in cache and FIFO/LRU eviction at max_cache_entries."""
        for i in range(12):
            self.daemon._store_in_cache(f"key_{i}", f"resp_{i}".encode("utf-8"), ttl_seconds=60)

        self.assertEqual(self.daemon.get_cache_size(), 10)
        # Oldest key_0 and key_1 should have been evicted
        self.assertIsNone(self.daemon._get_from_cache("key_0"))
        self.assertIsNotNone(self.daemon._get_from_cache("key_11"))

        self.daemon.clear_cache()
        self.assertEqual(self.daemon.get_cache_size(), 0)

    def test_packet_cache_hit_and_txid_rewrite(self):
        """Verifies that serving a cached packet rewrites the 2-byte DNS Transaction ID."""
        # Query 1 with tx_id 0xABCD
        q1 = b"\xab\xcd\x01\x00\x00\x01\x00\x00\x00\x00\x00\x00\x07example\x03com\x00\x00\x01\x00\x01"
        mock_response = b"\xab\xcd\x81\x80\x00\x01\x00\x01\x00\x00\x00\x00\x07example\x03com\x00\x00\x01\x00\x01\xc0\x0c\x00\x01\x00\x01\x00\x00\x00\x3c\x00\x04\x5d\xb8\xd8\x22"

        # Store in cache
        cache_key = f"profile_home_primary:{q1[12:]}"
        self.daemon._store_in_cache(cache_key, mock_response, ttl_seconds=100)

        # Query 2 from same client with different tx_id 0x1234
        q2 = b"\x12\x34\x01\x00\x00\x01\x00\x00\x00\x00\x00\x00\x07example\x03com\x00\x00\x01\x00\x01"
        resp = self.daemon.handle_packet(q2, ("192.168.1.50", 49152))

        self.assertIsNotNone(resp)
        self.assertEqual(resp[:2], b"\x12\x34")  # Rewritten to query 2 transaction ID
        self.assertEqual(resp[2:], mock_response[2:])

    def test_failsafe_fallback_when_upstream_unreachable(self):
        """
        Fail-Safe Guarantee Verification:
        When upstream FocusDNS cloud is unreachable, daemon falls back to failsafe local resolver.
        """
        query = b"\x99\x88\x01\x00\x00\x01\x00\x00\x00\x00\x00\x00\x05local\x03lan\x00\x00\x01\x00\x01"

        # Simulated fallback hook
        fallback_invoked = []

        def mock_fallback(q):
            fallback_invoked.append(True)
            return b"\x99\x88\x81\x80\x00\x01\x00\x01"

        self.daemon._forward_failsafe = mock_fallback
        resp = self.daemon.handle_packet(query, ("192.168.1.100", 55555))

        self.assertIsNotNone(resp)
        self.assertEqual(len(fallback_invoked), 1)
        self.assertEqual(self.daemon._failsafe_fallbacks, 1)

    def test_router_telemetry_reporter_and_conditional_uninstallation(self):
        """Verifies telemetry snapshots, history bounding (100 limit), and conditional lock."""
        reporter = RouterTelemetryReporter(
            router_id="rtr_test_gw",
            platform_type="pfSense",
            firmware_version="2.7.2-RELEASE",
            stub_daemon=self.daemon,
            mac_router=self.mac_router,
        )

        # Default: normal mode -> can_uninstall is True
        snap1 = reporter.generate_snapshot()
        self.assertTrue(snap1.can_uninstall)
        self.assertEqual(snap1.platform_type, "pfSense")

        # Set strict lock on a device
        self.mac_router.register_manual_mapping("AA:11:22:33:44:55", "profile_strict_kids", strict_lock=True)

        # Now router cannot be cleanly uninstalled / disabled
        snap2 = reporter.generate_snapshot()
        self.assertFalse(snap2.can_uninstall)

        # Bypass increment
        reporter.record_bypass_intercepted(5)
        self.assertEqual(reporter._bypasses_blocked_count, 19)

        # History bounds check
        for _ in range(110):
            reporter.generate_snapshot()
        self.assertEqual(len(reporter._history), 100)


if __name__ == "__main__":
    unittest.main()
