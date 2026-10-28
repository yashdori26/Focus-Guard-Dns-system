"""
server/tests/test_engine_push_websocket.py
Comprehensive Unit Test Suite for MdmWebSocketHub and HubClientChannel.

Verifies:
1. Hub client channel lifecycle and topic subscription management.
2. High-speed policy dispatch with zero-latency queuing.
3. Strict conditional uninstallation push commands (CLEAR_FOR_UNINSTALL vs LOCK_FOCUS).
4. Inviolable life-safety emergency dialer guarantee verification.
5. Ring buffer pruning for client message queues (500) and hub history (1000).
6. Multi-threaded concurrency and subscriber isolation.
"""

import unittest
import time
import threading
from typing import Dict, Any, List

from server.engine.mdm_websocket_hub import MdmWebSocketHub, HubClientChannel


class TestMdmWebSocketHub(unittest.TestCase):
    """Exhaustive test suite for real-time MDM push hub and event multiplexer."""

    def setUp(self):
        self.hub = MdmWebSocketHub()

    def test_hub_client_channel_initialization(self):
        """Verifies initial topic subscriptions for mobile endpoints and admin consoles."""
        mobile = HubClientChannel(
            client_id="ws_mob_001",
            device_id="dev_pixel_9",
            tenant_id="corp_acme",
            is_admin_console=False,
        )
        self.assertEqual(mobile.client_id, "ws_mob_001")
        self.assertEqual(mobile.device_id, "dev_pixel_9")
        self.assertEqual(mobile.tenant_id, "corp_acme")
        self.assertFalse(mobile.is_admin_console)
        self.assertIn("device:dev_pixel_9", mobile.subscribed_topics)
        self.assertIn("tenant:corp_acme", mobile.subscribed_topics)
        self.assertNotIn("admin:all", mobile.subscribed_topics)

        admin = HubClientChannel(
            client_id="ws_admin_001",
            device_id=None,
            tenant_id="corp_acme",
            is_admin_console=True,
        )
        self.assertTrue(admin.is_admin_console)
        self.assertIn("tenant:corp_acme", admin.subscribed_topics)
        self.assertIn("admin:all", admin.subscribed_topics)

    def test_client_channel_enqueue_and_fetch(self):
        """Verifies message queuing, FIFO order, and queue emptying."""
        client = HubClientChannel("ws_002", "dev_002")
        client.enqueue_message("device:dev_002", {"action": "PING"})
        client.enqueue_message("device:dev_002", {"action": "SYNC"})

        self.assertEqual(len(client.message_queue), 2)
        msgs = client.fetch_messages()
        self.assertEqual(len(msgs), 2)
        self.assertEqual(msgs[0]["data"]["action"], "PING")
        self.assertEqual(msgs[1]["data"]["action"], "SYNC")
        self.assertEqual(len(client.message_queue), 0)

    def test_client_channel_buffer_capping(self):
        """Verifies client message queue caps at 500 messages, dropping oldest first."""
        client = HubClientChannel("ws_003", "dev_003")
        for i in range(550):
            client.enqueue_message("test:topic", {"seq": i})

        self.assertEqual(len(client.message_queue), 500)
        msgs = client.fetch_messages()
        self.assertEqual(msgs[0]["data"]["seq"], 50)
        self.assertEqual(msgs[-1]["data"]["seq"], 549)

    def test_hub_registration_and_lookup(self):
        """Verifies registering and unregistering clients with the hub."""
        c1 = self.hub.register_client(client_id="ws_a", device_id="dev_a")
        self.assertIsNotNone(c1)
        self.assertEqual(self.hub.get_client("ws_a"), c1)

        metrics = self.hub.get_hub_metrics()
        self.assertEqual(metrics["total_active_channels"], 1)
        self.assertEqual(metrics["mobile_endpoint_channels"], 1)
        self.assertEqual(metrics["admin_console_channels"], 0)

        unreg = self.hub.unregister_client("ws_a")
        self.assertTrue(unreg)
        self.assertIsNone(self.hub.get_client("ws_a"))
        self.assertFalse(self.hub.unregister_client("ws_a"))

    def test_hub_topic_subscription(self):
        """Verifies ad-hoc topic subscriptions for active clients."""
        c1 = self.hub.register_client("ws_b", "dev_b")
        success = self.hub.subscribe_topic("ws_b", "custom:alerts")
        self.assertTrue(success)
        self.assertIn("custom:alerts", c1.subscribed_topics)

        failed = self.hub.subscribe_topic("non_existent", "custom:alerts")
        self.assertFalse(failed)

    def test_broadcast_to_device_and_admin_all(self):
        """Verifies device-specific broadcast reaches device and any admin consoles."""
        dev_client = self.hub.register_client("client_dev_1", device_id="dev_1")
        other_dev = self.hub.register_client("client_dev_2", device_id="dev_2")
        admin_client = self.hub.register_client("client_admin", is_admin_console=True)

        delivered = self.hub.broadcast_to_device(
            device_id="dev_1",
            action="LOCK_POLICY",
            payload={"enforce": True},
        )
        self.assertEqual(delivered, 2)  # dev_1 + admin_all

        dev1_msgs = dev_client.fetch_messages()
        self.assertEqual(len(dev1_msgs), 1)
        self.assertEqual(dev1_msgs[0]["data"]["action"], "LOCK_POLICY")

        dev2_msgs = other_dev.fetch_messages()
        self.assertEqual(len(dev2_msgs), 0)

        admin_msgs = admin_client.fetch_messages()
        self.assertEqual(len(admin_msgs), 1)
        self.assertEqual(admin_msgs[0]["data"]["device_id"], "dev_1")

    def test_broadcast_to_tenant(self):
        """Verifies tenant broadcast reaches all devices belonging to tenant."""
        c1 = self.hub.register_client("c1", device_id="d1", tenant_id="tenant_x")
        c2 = self.hub.register_client("c2", device_id="d2", tenant_id="tenant_x")
        c3 = self.hub.register_client("c3", device_id="d3", tenant_id="tenant_y")

        delivered = self.hub.broadcast_to_tenant(
            tenant_id="tenant_x",
            event_type="POLICY_RELOAD",
            payload={"version": "2.4.0"},
        )
        self.assertEqual(delivered, 2)
        self.assertEqual(len(c1.fetch_messages()), 1)
        self.assertEqual(len(c2.fetch_messages()), 1)
        self.assertEqual(len(c3.fetch_messages()), 0)

    def test_push_uninstallation_unlock_core_law(self):
        """
        Inviolable Core Law Verification:
        CLEAR_FOR_UNINSTALL directive must explicitly carry can_uninstall=True.
        """
        dev = self.hub.register_client("c_target", device_id="dev_unlock_me")

        # Unlock when connected
        result = self.hub.push_uninstallation_unlock("dev_unlock_me", unlock_reason="OFF_DUTY_APPROVED")
        self.assertTrue(result)

        msgs = dev.fetch_messages()
        self.assertEqual(len(msgs), 1)
        payload = msgs[0]["data"]["payload"]
        self.assertTrue(payload["can_uninstall"])
        self.assertEqual(payload["unlock_reason"], "OFF_DUTY_APPROVED")
        self.assertIn("Clean uninstallation is 100% permitted", payload["instructions"])

        # Attempt unlock on disconnected device
        res_disconnected = self.hub.push_uninstallation_unlock("unknown_device_999")
        self.assertFalse(res_disconnected)

    def test_push_focus_lock_with_life_safety_exemption(self):
        """
        Inviolable Life Safety Exemption Verification:
        LOCK_FOCUS locks uninstallation (can_uninstall=False) but guarantees emergency dialing exemption.
        """
        dev = self.hub.register_client("c_lock_target", device_id="dev_lock_me")

        result = self.hub.push_focus_lock("dev_lock_me", duration_seconds=3600)
        self.assertTrue(result)

        msgs = dev.fetch_messages()
        self.assertEqual(len(msgs), 1)
        payload = msgs[0]["data"]["payload"]
        self.assertFalse(payload["can_uninstall"])
        self.assertEqual(payload["duration_seconds"], 3600)
        self.assertIn("Emergency dialing (911/112) is exempt", payload["emergency_guarantee"])

    def test_listeners_callback_and_exception_resilience(self):
        """Verifies registered listeners receive events and exceptions do not crash hub."""
        received: List[str] = []

        def good_listener(topic: str, data: Dict[str, Any]):
            received.append(topic)

        def failing_listener(topic: str, data: Dict[str, Any]):
            raise RuntimeError("Simulated listener crash")

        self.hub.add_listener(good_listener)
        self.hub.add_listener(failing_listener)

        self.hub.broadcast_event("test:event", {"key": "val"})
        self.assertIn("test:event", received)

        # Remove listener
        self.assertTrue(self.hub.remove_listener(good_listener))
        self.assertFalse(self.hub.remove_listener(good_listener))

        self.hub.broadcast_event("test:event2", {"key": "val"})
        self.assertEqual(len(received), 1)

    def test_event_history_ring_buffer_and_filtering(self):
        """Verifies hub history limits to 1000 events and topic filtering works."""
        for i in range(1050):
            t = "topic:alpha" if i % 2 == 0 else "topic:beta"
            self.hub.broadcast_event(t, {"seq": i})

        metrics = self.hub.get_hub_metrics()
        self.assertEqual(metrics["event_history_count"], 1000)

        alpha_events = self.hub.get_event_history(topic_filter="topic:alpha", limit=50)
        self.assertEqual(len(alpha_events), 50)
        for e in alpha_events:
            self.assertEqual(e["topic"], "topic:alpha")

        self.hub.clear_history()
        self.assertEqual(len(self.hub.get_event_history()), 0)

    def test_multithreaded_concurrent_dispatches(self):
        """Stress-tests concurrent dispatches and registrations under multi-threaded load."""
        clients = [
            self.hub.register_client(f"worker_{i}", device_id=f"dev_worker_{i}")
            for i in range(10)
        ]
        errors = []

        def worker_dispatcher(worker_id: int):
            try:
                for j in range(20):
                    self.hub.broadcast_to_device(
                        device_id=f"dev_worker_{worker_id}",
                        action="THREAD_PING",
                        payload={"worker": worker_id, "step": j},
                    )
            except Exception as e:
                errors.append(e)

        threads = [threading.Thread(target=worker_dispatcher, args=(i,)) for i in range(10)]
        for t in threads:
            t.start()
        for t in threads:
            t.join()

        self.assertEqual(len(errors), 0)
        for client in clients:
            msgs = client.fetch_messages()
            self.assertEqual(len(msgs), 20)


if __name__ == "__main__":
    unittest.main()
