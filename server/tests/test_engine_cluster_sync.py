"""
Unit and integration tests for FocusDNS Cluster Sync, Node Gossip, and Anycast Health Probe Daemon.
"""

import time
import unittest
from unittest.mock import MagicMock, patch

from server.engine.cluster_sync import (
    ClusterNode,
    ThreatIntelMessage,
    ClusterSyncEngine,
    AnycastHealthProbe,
    HEALTH_HEALTHY,
    HEALTH_DEGRADED,
    HEALTH_UNHEALTHY,
)


class TestClusterSyncSubsystem(unittest.TestCase):
    def setUp(self):
        self.sync_engine = ClusterSyncEngine(local_node_id="node-us-east-1")

    def test_cluster_node_registration_and_heartbeat(self):
        """Verify peer node registration, liveness tracking, and heartbeat updates."""
        peer = ClusterNode(node_id="node-eu-west-1", host="10.0.1.25", port=8080)
        self.sync_engine.register_node(peer)

        nodes = self.sync_engine.get_nodes()
        self.assertEqual(len(nodes), 1)
        self.assertEqual(nodes[0]["node_id"], "node-eu-west-1")
        self.assertTrue(nodes[0]["is_alive"])

        # Update heartbeat
        peer.record_heartbeat(status=HEALTH_HEALTHY, qps=1520.5, version="2.0.1")
        self.assertEqual(peer.queries_per_second, 1520.5)

        # Unregister
        self.sync_engine.unregister_node("node-eu-west-1")
        self.assertEqual(len(self.sync_engine.get_nodes()), 0)

    def test_distributed_threat_broadcasting(self):
        """Verify distributed threat intelligence sharing across nodes."""
        # 1. Share blocked attacker IP
        threat_ip = ThreatIntelMessage(
            msg_type=ThreatIntelMessage.TYPE_BLOCK_IP,
            item="203.0.113.88",
            reason="DDoS Flood Target Attacker",
            ttl_seconds=3600,
        )
        self.sync_engine.receive_threat(threat_ip)

        is_blocked, reason = self.sync_engine.is_ip_blocked("203.0.113.88")
        self.assertTrue(is_blocked)
        self.assertEqual(reason, "DDoS Flood Target Attacker")

        # Clean IP check
        is_clean, _ = self.sync_engine.is_ip_blocked("1.1.1.1")
        self.assertFalse(is_clean)

        # 2. Share malicious Fast-Flux domain
        threat_domain = ThreatIntelMessage(
            msg_type=ThreatIntelMessage.TYPE_FAST_FLUX,
            item="fastflux-malware-drop.biz",
            reason="Fast-Flux Rapid IP Agility Network",
            ttl_seconds=1800,
        )
        self.sync_engine.broadcast_threat(threat_domain)

        is_dom_blocked, dom_reason = self.sync_engine.is_domain_blocked("fastflux-malware-drop.biz")
        self.assertTrue(is_dom_blocked)
        self.assertEqual(dom_reason, "Fast-Flux Rapid IP Agility Network")

    def test_threat_expiration_and_pruning(self):
        """Verify expired threat messages are pruned."""
        short_threat = ThreatIntelMessage(
            msg_type=ThreatIntelMessage.TYPE_BLOCK_IP,
            item="198.51.100.11",
            reason="Transient Attack",
            ttl_seconds=0,  # Expired immediately
        )
        short_threat.created_at = time.time() - 10.0
        self.sync_engine.receive_threat(short_threat)

        self.sync_engine.prune_expired()
        is_blocked, _ = self.sync_engine.is_ip_blocked("198.51.100.11")
        self.assertFalse(is_blocked)

    def test_anycast_health_probe_status_transitions(self):
        """Verify health evaluator reports healthy, degraded, and unhealthy appropriately."""
        probe = AnycastHealthProbe(host="127.0.0.1")

        # Mock all probes passing -> HEALTHY
        probe.probe_udp_canary = MagicMock(return_value=True)
        probe.probe_tcp_port = MagicMock(return_value=True)
        status = probe.execute_full_check()
        self.assertEqual(status, HEALTH_HEALTHY)
        report = probe.get_status_report()
        self.assertTrue(report["anycast_ready"])

        # Mock DoT failing -> DEGRADED (UDP & HTTP alive)
        probe.probe_tcp_port = MagicMock(side_effect=lambda p: p != 8853)
        status_deg = probe.execute_full_check()
        self.assertEqual(status_deg, HEALTH_DEGRADED)
        self.assertTrue(probe.get_status_report()["anycast_ready"])

        # Mock all failing -> UNHEALTHY
        probe.probe_udp_canary = MagicMock(return_value=False)
        probe.probe_tcp_port = MagicMock(return_value=False)
        status_unh = probe.execute_full_check()
        self.assertEqual(status_unh, HEALTH_UNHEALTHY)
        self.assertFalse(probe.get_status_report()["anycast_ready"])


if __name__ == "__main__":
    unittest.main()
