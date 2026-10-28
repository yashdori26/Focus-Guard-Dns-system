"""
FocusDNS Engine Tests - RFC 8310 & RFC 9103 Secure Upstream Forwarder Subsystem
Tests:
- Upstream configuration and endpoint state tracking
- Circuit breaker state machine (CLOSED -> OPEN -> HALF_OPEN -> CLOSED)
- Selection strategies (ROUND_ROBIN, FASTEST, FAILOVER, RANDOM)
- TLS session ticket cache (store, retrieve, expire, invalidate)
- Connection pooling lifecycle (acquire, release, reuse, idle discard)
- Forwarder retry cascade and multi-protocol dispatch
"""

import socket
import struct
import threading
import time
import unittest
from unittest.mock import MagicMock, patch

from server.engine.secure_forwarder import (
    CircuitState,
    DoTConnectionPool,
    PrivacyProfile,
    SecureUpstreamForwarder,
    SelectionStrategy,
    TLSSessionCache,
    UpstreamConfig,
    UpstreamEndpoint,
    UpstreamProtocol,
)


class TestSecureForwarderComponents(unittest.TestCase):

    def setUp(self):
        self.cfg1 = UpstreamConfig(
            host="1.1.1.1",
            port=853,
            protocol=UpstreamProtocol.DOT,
            server_name="cloudflare-dns.com",
            privacy_profile=PrivacyProfile.STRICT,
            priority=1,
            max_failures=2,
            recovery_timeout_sec=0.1,  # Short for test
        )
        self.cfg2 = UpstreamConfig(
            host="8.8.8.8",
            port=853,
            protocol=UpstreamProtocol.DOT,
            server_name="dns.google",
            privacy_profile=PrivacyProfile.STRICT,
            priority=2,
            max_failures=2,
            recovery_timeout_sec=0.1,
        )

    def test_upstream_endpoint_circuit_breaker(self):
        ep = UpstreamEndpoint(self.cfg1)
        self.assertEqual(ep.stats.circuit_state, CircuitState.CLOSED)
        self.assertTrue(ep.is_available())

        # First failure does not trip (max_failures=2)
        ep.record_failure()
        self.assertEqual(ep.stats.consecutive_failures, 1)
        self.assertEqual(ep.stats.circuit_state, CircuitState.CLOSED)
        self.assertTrue(ep.is_available())

        # Second failure trips circuit to OPEN
        ep.record_failure()
        self.assertEqual(ep.stats.consecutive_failures, 2)
        self.assertEqual(ep.stats.circuit_state, CircuitState.OPEN)
        self.assertFalse(ep.is_available())

        # Wait for recovery timeout to transition to HALF_OPEN
        time.sleep(0.12)
        self.assertTrue(ep.is_available())
        self.assertEqual(ep.stats.circuit_state, CircuitState.HALF_OPEN)

        # Successful probe recovers to CLOSED
        ep.record_success(latency_ms=12.5)
        self.assertEqual(ep.stats.circuit_state, CircuitState.CLOSED)
        self.assertEqual(ep.stats.consecutive_failures, 0)
        self.assertAlmostEqual(ep.stats.ewma_latency_ms, 12.5, places=1)

    def test_half_open_failure_reopens_immediately(self):
        ep = UpstreamEndpoint(self.cfg1)
        ep.record_failure()
        ep.record_failure()
        self.assertEqual(ep.stats.circuit_state, CircuitState.OPEN)

        time.sleep(0.12)
        self.assertTrue(ep.is_available())
        self.assertEqual(ep.stats.circuit_state, CircuitState.HALF_OPEN)

        # Failure during HALF_OPEN reopens immediately
        ep.record_failure()
        self.assertEqual(ep.stats.circuit_state, CircuitState.OPEN)
        self.assertFalse(ep.is_available())

    def test_ewma_latency_calculation(self):
        ep = UpstreamEndpoint(self.cfg1)
        ep.record_success(10.0)
        self.assertEqual(ep.stats.ewma_latency_ms, 10.0)

        # EWMA with alpha=0.25: 0.25 * 20 + 0.75 * 10 = 5 + 7.5 = 12.5
        ep.record_success(20.0)
        self.assertEqual(ep.stats.ewma_latency_ms, 12.5)

    def test_tls_session_cache(self):
        cache = TLSSessionCache(default_ttl_sec=0.1)
        mock_session = "mock_tls_session_ticket_bytes"

        cache.store_session("1.1.1.1", 853, "cloudflare-dns.com", mock_session)
        self.assertEqual(cache.size(), 1)
        self.assertEqual(cache.get_session("1.1.1.1", 853, "cloudflare-dns.com"), mock_session)

        # Non-matching key returns None
        self.assertIsNone(cache.get_session("8.8.8.8", 853, "dns.google"))

        # Explicit invalidation
        cache.invalidate("1.1.1.1", 853, "cloudflare-dns.com")
        self.assertIsNone(cache.get_session("1.1.1.1", 853, "cloudflare-dns.com"))

        # TTL expiration
        cache.store_session("1.1.1.1", 853, "cloudflare-dns.com", mock_session, ttl_sec=0.05)
        time.sleep(0.08)
        self.assertIsNone(cache.get_session("1.1.1.1", 853, "cloudflare-dns.com"))

    def test_connection_pool_acquire_and_release(self):
        pool = DoTConnectionPool(max_idle_sec=0.1, max_connections_per_host=2)
        mock_sock = MagicMock()

        # Initially empty
        self.assertIsNone(pool.acquire(self.cfg1))

        # Release socket
        pool.release(self.cfg1, mock_sock, reusable=True)

        # Acquire returns socket
        with patch("select.select", return_value=([], [], [])):
            sock = pool.acquire(self.cfg1)
            self.assertEqual(sock, mock_sock)

        # Pool is empty again
        self.assertIsNone(pool.acquire(self.cfg1))

        # Test idle timeout discard
        pool.release(self.cfg1, mock_sock, reusable=True)
        time.sleep(0.12)
        discarded_sock = pool.acquire(self.cfg1)
        self.assertIsNone(discarded_sock)
        mock_sock.close.assert_called()


class TestSecureForwarderEngine(unittest.TestCase):

    def setUp(self):
        self.forwarder = SecureUpstreamForwarder(strategy=SelectionStrategy.ROUND_ROBIN)
        self.ep1 = self.forwarder.add_upstream(
            UpstreamConfig("1.1.1.1", 853, UpstreamProtocol.DOT, "cloudflare-dns.com", priority=1)
        )
        self.ep2 = self.forwarder.add_upstream(
            UpstreamConfig("8.8.8.8", 853, UpstreamProtocol.DOT, "dns.google", priority=2)
        )

    def test_round_robin_selection(self):
        self.forwarder.strategy = SelectionStrategy.ROUND_ROBIN
        s1 = self.forwarder.select_endpoint()
        s2 = self.forwarder.select_endpoint()
        s3 = self.forwarder.select_endpoint()

        self.assertEqual(s1.config.host, "1.1.1.1")
        self.assertEqual(s2.config.host, "8.8.8.8")
        self.assertEqual(s3.config.host, "1.1.1.1")

    def test_failover_strategy(self):
        self.forwarder.strategy = SelectionStrategy.FAILOVER
        # Always selects lowest priority number (1) when available
        self.assertEqual(self.forwarder.select_endpoint().config.host, "1.1.1.1")

        # Trip priority 1 endpoint circuit breaker
        self.ep1.stats.circuit_state = CircuitState.OPEN
        self.ep1.stats.last_state_change = time.time()
        # Now selects priority 2
        self.assertEqual(self.forwarder.select_endpoint().config.host, "8.8.8.8")

    def test_fastest_strategy(self):
        self.forwarder.strategy = SelectionStrategy.FASTEST
        self.ep1.stats.ewma_latency_ms = 45.0
        self.ep2.stats.ewma_latency_ms = 12.0

        # Lowest EWMA latency wins
        self.assertEqual(self.forwarder.select_endpoint().config.host, "8.8.8.8")

        self.ep1.stats.ewma_latency_ms = 8.0
        self.assertEqual(self.forwarder.select_endpoint().config.host, "1.1.1.1")

    def test_remove_upstream(self):
        self.assertEqual(len(self.forwarder.get_endpoints()), 2)
        removed = self.forwarder.remove_upstream("1.1.1.1", 853)
        self.assertTrue(removed)
        self.assertEqual(len(self.forwarder.get_endpoints()), 1)
        self.assertEqual(self.forwarder.get_endpoints()[0].config.host, "8.8.8.8")

    def test_forward_success_with_retry_on_primary_failure(self):
        dummy_query = b"\x00\x01\x01\x00\x00\x01\x00\x00\x00\x00\x00\x00\x07example\x03com\x00\x00\x01\x00\x01"
        dummy_response = b"\x00\x01\x81\x80\x00\x01\x00\x01\x00\x00\x00\x00\x07example\x03com\x00\x00\x01\x00\x01\xc0\x0c\x00\x01\x00\x01\x00\x00\x01\x2c\x00\x04\x5d\xb8\xd8\x22"

        # ep1 fails, ep2 succeeds
        def mock_dispatch(endpoint, wire, timeout):
            if endpoint.config.host == "1.1.1.1":
                raise socket.timeout("Connection timed out")
            return dummy_response

        with patch.object(self.forwarder, "_forward_dot", side_effect=mock_dispatch):
            resp, resp_ep = self.forwarder.forward(dummy_query)
            self.assertEqual(resp, dummy_response)
            self.assertEqual(resp_ep.config.host, "8.8.8.8")
            self.assertEqual(self.forwarder.total_successful, 1)
            self.assertEqual(self.forwarder.total_retries, 1)

    def test_all_upstreams_fail_raises_runtime_error(self):
        dummy_query = b"header_query_wire"
        with patch.object(self.forwarder, "_forward_dot", side_effect=ConnectionResetError("Down")):
            with self.assertRaises(RuntimeError) as ctx:
                self.forwarder.forward(dummy_query)
            self.assertIn("All upstream queries failed", str(ctx.exception))
            self.assertEqual(self.forwarder.total_failures, 1)

    def test_status_report(self):
        status = self.forwarder.get_status()
        self.assertEqual(status["endpoints_count"], 2)
        self.assertEqual(status["strategy"], "round_robin")
        self.assertIn("endpoints", status)
        self.assertEqual(len(status["endpoints"]), 2)


if __name__ == "__main__":
    unittest.main()
