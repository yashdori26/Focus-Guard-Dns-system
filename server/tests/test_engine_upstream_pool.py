"""
Unit and integration tests for FocusDNS Upstream Pool & Circuit Breakers.
"""

import time
import unittest
from dnslib import DNSRecord

from server.engine.upstream_pool import (
    UpstreamNode,
    UpstreamPool,
    UpstreamRoutingStrategy,
    CircuitState,
    CIRCUIT_FAILURE_THRESHOLD,
)


class TestUpstreamPoolSubsystem(unittest.TestCase):
    def setUp(self):
        self.pool = UpstreamPool(strategy=UpstreamRoutingStrategy.LOWEST_LATENCY, query_timeout=1.0)
        # Clear default nodes for controlled test isolation
        with self.pool._lock:
            self.pool._nodes.clear()

    def tearDown(self):
        self.pool.close()

    def test_circuit_breaker_transitions(self):
        """Verify CLOSED -> OPEN -> HALF_OPEN -> CLOSED state lifecycle."""
        node = UpstreamNode("TestNode", "127.0.0.1", 53)
        self.assertEqual(node.state, CircuitState.CLOSED)
        self.assertTrue(node.is_available)

        # Record failures up to threshold - 1
        for _ in range(CIRCUIT_FAILURE_THRESHOLD - 1):
            node.record_failure()
            self.assertEqual(node.state, CircuitState.CLOSED)
            self.assertTrue(node.is_available)

        # 4th failure trips circuit OPEN
        node.record_failure()
        self.assertEqual(node.state, CircuitState.OPEN)
        self.assertFalse(node.is_available)

        # Simulate recovery time elapsed -> transitions to HALF_OPEN canary probe
        node.last_failure_time = time.time() - 30.0
        self.assertTrue(node.is_available)
        self.assertEqual(node.state, CircuitState.HALF_OPEN)

        # Successful canary probe resets circuit to CLOSED
        node.record_success(latency_ms=12.5)
        self.assertEqual(node.state, CircuitState.CLOSED)
        self.assertEqual(node.consecutive_failures, 0)
        self.assertTrue(node.is_available)

    def test_node_latency_statistics(self):
        """Verify rolling average and percentile calculation."""
        node = UpstreamNode("MetricNode", "127.0.0.1", 53)
        latencies = [10.0, 15.0, 20.0, 25.0, 30.0]
        for l in latencies:
            node.record_success(l)

        stats = node.get_stats()
        self.assertEqual(stats["avg_latency_ms"], 20.0)
        self.assertEqual(stats["total_queries"], 5)
        self.assertEqual(stats["total_failures"], 0)

    def test_routing_strategy_lowest_latency(self):
        """Verify LOWEST_LATENCY strategy dynamically routes to the lowest latency node."""
        node_fast = UpstreamNode("Fast", "1.1.1.1", 53)
        node_fast.avg_latency_ms = 8.0

        node_slow = UpstreamNode("Slow", "8.8.8.8", 53)
        node_slow.avg_latency_ms = 35.0

        self.pool.add_node(node_fast)
        self.pool.add_node(node_slow)

        selected = self.pool.select_node()
        self.assertIsNotNone(selected)
        self.assertEqual(selected.name, "Fast")

    def test_routing_strategy_failover(self):
        """Verify FAILOVER strategy routes to primary and only uses backup when primary trips."""
        self.pool.strategy = UpstreamRoutingStrategy.FAILOVER

        primary = UpstreamNode("Primary", "1.1.1.1", 53, is_backup=False)
        backup = UpstreamNode("Backup", "8.8.8.8", 53, is_backup=True)

        self.pool.add_node(primary)
        self.pool.add_node(backup)

        # When primary is healthy -> primary selected
        self.assertEqual(self.pool.select_node().name, "Primary")

        # Trip primary circuit OPEN
        for _ in range(CIRCUIT_FAILURE_THRESHOLD):
            primary.record_failure()

        # Primary now unavailable -> failover to backup
        self.assertEqual(self.pool.select_node().name, "Backup")

    def test_all_circuits_open_emergency_fallback(self):
        """Verify pool avoids total blackout if all upstream circuits are tripped."""
        node = UpstreamNode("OnlyNode", "9.9.9.9", 53)
        for _ in range(CIRCUIT_FAILURE_THRESHOLD):
            node.record_failure()
        self.assertEqual(node.state, CircuitState.OPEN)

        self.pool.add_node(node)
        # get_healthy_nodes should return all nodes as emergency fallback
        nodes = self.pool.get_healthy_nodes()
        self.assertEqual(len(nodes), 1)

    def test_pool_stats_telemetry(self):
        """Verify aggregated pool telemetry report."""
        node = UpstreamNode("StatTest", "1.1.1.1", 53)
        node.record_success(15.0)
        self.pool.add_node(node)

        stats = self.pool.get_stats()
        self.assertEqual(stats["total_nodes"], 1)
        self.assertEqual(stats["active_nodes"], 1)
        self.assertEqual(stats["total_queries"], 1)
        self.assertEqual(stats["failover_count"], 0)


if __name__ == "__main__":
    unittest.main()
