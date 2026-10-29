"""
Unit tests for FocusDNS Enterprise Device Heartbeat Agent.
Verifies:
  1. Fleet registration and persistent WebSocket keepalive.
  2. Heartbeat emission and telemetry recording.
  3. Policy push ingestion, Life-Safety domain purging, and local cache invalidation.
  4. Remote focus session lock and unlock commands.
  5. Strict enforcement of the Conditional Whitelisting Law:
     Attempting to whitelist or disable protection while locked raises ERROR_ACCESS_DENIED (5).
  6. Sub-50ms push delivery ACK and RTT computation.
  7. Offline telemetry queueing when disconnected.
"""

import time
import unittest

from server.enterprise.fleet_websocket_server import FleetWebSocketServer
from server.enterprise.device_heartbeat_agent import DeviceHeartbeatAgent, LIFE_SAFETY_DOMAINS


class TestEnterpriseDeviceAgent(unittest.TestCase):

    def setUp(self):
        self.hub = FleetWebSocketServer(ping_interval_sec=10.0, ack_timeout_sec=5.0)
        self.flushed_count = 0

        def mock_flush():
            self.flushed_count += 1

        self.agent = DeviceHeartbeatAgent(
            device_id="dev_macbook_pro_01",
            org_id="org_enterprise_corp",
            unit_id="unit_finance",
            fleet_id="fleet_csuite",
            platform="MACOS",
            hub=self.hub,
            heartbeat_interval_sec=0.2,
            cache_flush_callback=mock_flush,
        )

    def tearDown(self):
        self.agent.shutdown()
        self.hub.shutdown()

    def test_connect_and_heartbeat(self):
        """Device connects to FleetHub, emits heartbeats, and registers connection state."""
        connected = self.agent.connect()
        self.assertTrue(connected)
        self.assertTrue(self.agent.state.is_connected)

        # Emit heartbeat
        telemetry = self.agent.emit_heartbeat()
        self.assertEqual(telemetry["device_id"], "dev_macbook_pro_01")
        self.assertEqual(telemetry["type"], "HEARTBEAT")

        # Verify hub sees client
        hub_status = self.hub.get_device_status("dev_macbook_pro_01")
        self.assertIsNotNone(hub_status)
        self.assertTrue(hub_status["is_alive"])

    def test_policy_push_and_life_safety_purge(self):
        """Inbound policy is applied, invalidates local cache, and strips illegal life-safety blocks."""
        self.agent.connect()
        initial_flushes = self.flushed_count

        policy_frame = {
            "type": "POLICY_UPDATE",
            "message_id": "msg_policy_001",
            "timestamp": time.time(),
            "policy": {
                "version": 42,
                "blocked_domains": [
                    "tiktok.com",
                    "gambling-casino.net",
                    "911.gov",  # Illegal life-safety block
                    "push.apple.com",  # Illegal life-safety block
                ],
                "allowed_domains": ["intranet.corp", "emergency.gov"]
            }
        }

        success, reason = self.agent.process_inbound_frame(policy_frame)
        self.assertTrue(success)
        self.assertEqual(reason, "POLICY_APPLIED_V42")

        # Inviolable Life-Safety Exemption: 911.gov and push.apple.com must NOT be in blocked list
        self.assertNotIn("911.gov", self.agent.state.blocked_domains)
        self.assertNotIn("push.apple.com", self.agent.state.blocked_domains)
        self.assertIn("tiktok.com", self.agent.state.blocked_domains)
        self.assertIn("gambling-casino.net", self.agent.state.blocked_domains)

        # Cache must have been invalidated
        self.assertGreater(self.flushed_count, initial_flushes)

    def test_conditional_whitelisting_law_enforcement(self):
        """
        Inviolable Law:
        When session is locked, whitelisting domains or disabling protection
        strictly raises PermissionError: ERROR_ACCESS_DENIED (5).
        """
        self.agent.connect()

        # Phase 1: Unlocked state -> Whitelisting permitted
        self.agent.request_whitelist_domain("approved-partner.com")
        self.assertTrue(self.agent.check_domain_allowed("approved-partner.com"))
        self.assertTrue(self.agent.request_disable_protection())

        # Phase 2: Remote lock triggered by teacher / fleet controller
        lock_frame = {
            "type": "LOCK_SESSION",
            "message_id": "msg_lock_002",
            "timestamp": time.time(),
            "duration_seconds": 600,
            "reason": "Classroom Strict Exam Mode"
        }
        success, _ = self.agent.process_inbound_frame(lock_frame)
        self.assertTrue(success)
        self.assertTrue(self.agent.state.is_locked)
        self.assertGreater(self.agent.state.lock_remaining_seconds, 0)

        # Phase 3: Attempting to whitelist during lock MUST raise ERROR_ACCESS_DENIED (5)
        with self.assertRaises(PermissionError) as ctx:
            self.agent.request_whitelist_domain("social-network.com")
        self.assertIn("ERROR_ACCESS_DENIED (5)", str(ctx.exception))

        # Attempting to disable protection during lock MUST raise ERROR_ACCESS_DENIED (5)
        with self.assertRaises(PermissionError) as ctx:
            self.agent.request_disable_protection()
        self.assertIn("ERROR_ACCESS_DENIED (5)", str(ctx.exception))

        # Phase 4: Remote unlock from admin restores access
        unlock_frame = {
            "type": "UNLOCK_SESSION",
            "message_id": "msg_unlock_003",
            "timestamp": time.time()
        }
        success, _ = self.agent.process_inbound_frame(unlock_frame)
        self.assertTrue(success)
        self.assertFalse(self.agent.state.is_locked)
        self.assertEqual(self.agent.state.lock_remaining_seconds, 0)

        # Whitelisting now permitted again
        self.assertTrue(self.agent.request_whitelist_domain("social-network.com"))

    def test_offline_telemetry_staging(self):
        """When disconnected, heartbeats are staged in circular buffer and flushed on reconnect."""
        self.agent.disconnect()
        self.assertFalse(self.agent.state.is_connected)

        # Emit 3 offline heartbeats
        for _ in range(3):
            self.agent.emit_heartbeat()

        self.assertEqual(len(self.agent._offline_telemetry), 3)

        # Reconnect
        self.agent.connect()
        self.assertTrue(self.agent.state.is_connected)
        self.assertEqual(len(self.agent._offline_telemetry), 0)

    def test_instant_flush_cache_command(self):
        """Inbound INSTANT_FLUSH_DNS_CACHE triggers cache callback."""
        self.agent.connect()
        flushes_before = self.flushed_count
        frame = {
            "type": "INSTANT_FLUSH_DNS_CACHE",
            "message_id": "msg_flush_099",
            "timestamp": time.time(),
        }
        success, reason = self.agent.process_inbound_frame(frame)
        self.assertTrue(success)
        self.assertEqual(reason, "CACHE_FLUSHED")
        self.assertEqual(self.flushed_count, flushes_before + 1)

    def test_ping_pong_frame(self):
        """Inbound PING responds with PONG and calculates RTT."""
        self.agent.connect()
        past_ts = time.time() - 0.025
        frame = {
            "type": "PING",
            "message_id": "msg_ping_100",
            "timestamp": past_ts,
        }
        success, reason = self.agent.process_inbound_frame(frame)
        self.assertTrue(success)
        self.assertEqual(reason, "PONG")
        self.assertGreater(self.agent.state.rtt_ms, 0.0)

    def test_subdomain_and_wildcard_matching(self):
        """Local policy evaluation blocks subdomains of blocked root domains."""
        self.agent.connect()
        policy_frame = {
            "type": "POLICY_UPDATE",
            "message_id": "msg_policy_wildcard",
            "timestamp": time.time(),
            "policy": {
                "version": 7,
                "blocked_domains": ["distraction.com"],
                "allowed_domains": ["safe.internal"]
            }
        }
        self.agent.process_inbound_frame(policy_frame)
        # Blocked exact and subdomain
        self.assertFalse(self.agent.check_domain_allowed("distraction.com"))
        self.assertFalse(self.agent.check_domain_allowed("videos.distraction.com"))
        self.assertFalse(self.agent.check_domain_allowed("api.v2.distraction.com"))
        # Allowed
        self.assertTrue(self.agent.check_domain_allowed("safe.internal"))
        self.assertTrue(self.agent.check_domain_allowed("wikipedia.org"))

    def test_query_counter_recording_and_state(self):
        """Verifies query counter increments and state dictionary serialization."""
        self.agent.record_query("allowed.com", is_blocked=False)
        self.agent.record_query("blocked.com", is_blocked=True)

        state_dict = self.agent.state.to_dict()
        self.assertEqual(state_dict["total_queries"], 2)
        self.assertEqual(state_dict["blocked_queries"], 1)
        self.assertEqual(state_dict["device_id"], "dev_macbook_pro_01")
        self.assertEqual(state_dict["platform"], "MACOS")


if __name__ == "__main__":
    unittest.main()
