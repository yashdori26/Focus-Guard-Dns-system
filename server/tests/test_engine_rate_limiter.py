"""
Unit and integration tests for FocusDNS Response Rate Limiting (RRL) Subsystem.
"""

import time
import unittest

from server.engine.rate_limiter import (
    DNSRateLimiter,
    RateLimitAction,
    TokenBucket,
)


class TestRateLimiterSubsystem(unittest.TestCase):
    def setUp(self):
        # Configure small rates for deterministic instant testing
        self.limiter = DNSRateLimiter(
            client_qps=5.0,
            client_burst=5.0,
            subnet_qps=20.0,
            subnet_burst=20.0,
            slip_ratio=2,
            nxdomain_qps=3.0,
        )

    def test_token_bucket_consume_and_refill(self):
        """Verify token bucket consumption and time-based refill."""
        bucket = TokenBucket(rate=10.0, burst=5.0)
        # Consume 5 tokens immediately
        for _ in range(5):
            self.assertTrue(bucket.consume(1.0))
        # 6th should fail
        self.assertFalse(bucket.consume(1.0))

        # Simulate 0.5s passing (refills 5 tokens)
        t_future = time.time() + 0.55
        self.assertTrue(bucket.consume(1.0, now=t_future))

    def test_subnet_key_extraction(self):
        """Verify IPv4 /24 and IPv6 /48 subnet grouping."""
        self.assertEqual(DNSRateLimiter.get_subnet_key("192.168.1.42"), "192.168.1.0/24")
        self.assertEqual(DNSRateLimiter.get_subnet_key("10.200.5.101"), "10.200.5.0/24")
        self.assertEqual(
            DNSRateLimiter.get_subnet_key("2001:db8:abcd:0012::1"),
            "2001:db8:abcd::/48",
        )

    def test_client_burst_and_slip_mitigation(self):
        """
        Verify that queries up to burst are allowed (PASS),
        subsequent queries alternate between DROP and SLIP_TC (slip_ratio=2).
        """
        client_ip = "192.0.2.1"

        # First 5 queries should PASS
        for _ in range(5):
            action = self.limiter.check_query_rate(client_ip)
            self.assertEqual(action, RateLimitAction.PASS)

        # 6th query (exceeded): slip counter 1 -> DROP (1 % 2 != 0)
        action_6 = self.limiter.check_query_rate(client_ip)
        self.assertEqual(action_6, RateLimitAction.DROP)

        # 7th query (exceeded): slip counter 2 -> SLIP_TC (2 % 2 == 0)
        action_7 = self.limiter.check_query_rate(client_ip)
        self.assertEqual(action_7, RateLimitAction.SLIP_TC)

        # 8th query: slip counter 3 -> DROP
        action_8 = self.limiter.check_query_rate(client_ip)
        self.assertEqual(action_8, RateLimitAction.DROP)

        # 9th query: slip counter 4 -> SLIP_TC
        action_9 = self.limiter.check_query_rate(client_ip)
        self.assertEqual(action_9, RateLimitAction.SLIP_TC)

    def test_nxdomain_water_torture_throttling(self):
        """Verify pseudo-random subdomain NXDOMAIN flood protection."""
        apex = "target-bank.example"
        # 6 permitted (burst is nxdomain_qps * 2 = 6)
        for _ in range(6):
            self.assertTrue(self.limiter.check_nxdomain_rate(apex))

        # 7th should be throttled
        self.assertFalse(self.limiter.check_nxdomain_rate(apex))

    def test_rate_limiter_telemetry_and_reset(self):
        """Verify rate limiter metrics and state clearing."""
        self.limiter.check_query_rate("1.1.1.1")
        stats = self.limiter.get_stats()
        self.assertGreaterEqual(stats["total_checked"], 1)
        self.assertGreaterEqual(stats["total_allowed"], 1)

        self.limiter.reset()
        stats_reset = self.limiter.get_stats()
        self.assertEqual(stats_reset["total_checked"], 0)
        self.assertEqual(stats_reset["active_client_buckets"], 0)


if __name__ == "__main__":
    unittest.main()
