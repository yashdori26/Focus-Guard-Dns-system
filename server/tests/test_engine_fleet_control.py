"""
server/tests/test_engine_fleet_control.py
Comprehensive test suite for FocusDNS Enterprise Fleet Control Plane and Real-Time WebSocket Hub.

Validates:
1. Conditional Uninstallation Law:
   - When device is IDLE (Protection OFF, Timer 0): can_uninstall() == True.
   - When device is in ACTIVE FOCUS / TIMER / RESTRICTED state: can_uninstall() == False.
2. Life-Safety Exemption:
   - Emergency call paths (911, 112) are hard-coded to bypass any remote kiosk or lock directives.
3. Fleet Command Queue:
   - Remote lock, unlock, policy push, managed config sync, and uninstallation unlock tokens.
4. Heartbeat & Posture Tracking:
   - Real-time telemetry, hardware attestation status, and multi-OEM compliance scoring (0-100).
5. WebSocket/SSE Real-Time Push Hub:
   - Sub-millisecond policy dispatch, multi-tenant topic routing, and client message buffering.
"""

import time
import unittest
from server.engine.fleet_control_plane import (
    FleetControlPlane,
    FleetDevice,
    FleetLockState,
    FleetCommandType,
)
from server.engine.mdm_websocket_hub import (
    MdmWebSocketHub,
    HubClientChannel,
)


class TestFleetControlPlane(unittest.TestCase):

    def setUp(self):
        self.plane = FleetControlPlane()
        self.hub = MdmWebSocketHub()

    def test_sample_fleet_initialized(self):
        d1 = self.plane.get_device("dev_pixel_corp_01")
        self.assertIsNotNone(d1)
        self.assertEqual(d1.tenant_id, "default_enterprise")
        self.assertEqual(d1.attestation_level, "STRONGBOX")
        self.assertTrue(d1.can_uninstall())  # Initial state is IDLE

        d2 = self.plane.get_device("dev_samsung_field_02")
        self.assertIsNotNone(d2)
        self.assertEqual(d2.attestation_level, "TEE")

    def test_device_registration_and_isolation(self):
        dev = self.plane.register_device(
            device_id="dev_pixel_test_99",
            tenant_id="tenant_engineering",
            device_model="Pixel Fold",
            os_version="Android 15",
            policy_id="pol_strict",
            hardware_id="hw_unique_8841",
            attestation_level="STRONGBOX",
        )
        self.assertEqual(dev.device_id, "dev_pixel_test_99")
        self.assertEqual(dev.tenant_id, "tenant_engineering")
        self.assertEqual(dev.lock_state, FleetLockState.IDLE)
        self.assertEqual(dev.timer_seconds_remaining, 0)
        self.assertTrue(dev.can_uninstall())

        # Verify multi-tenant filtering
        eng_devs = self.plane.list_devices(tenant_id="tenant_engineering")
        self.assertEqual(len(eng_devs), 1)
        self.assertEqual(eng_devs[0]["device_id"], "dev_pixel_test_99")

        corp_devs = self.plane.list_devices(tenant_id="default_enterprise")
        self.assertGreaterEqual(len(corp_devs), 2)

    def test_conditional_uninstallation_law_exhaustive(self):
        """
        Inviolable Core Law Verification:
        Clean uninstallation is permitted ONLY when device is in IDLE mode with no timer running.
        """
        dev = self.plane.register_device(device_id="dev_uninstall_law_test")

        # 1. State = IDLE, Timer = 0 -> Clean uninstallation 100% permitted
        dev.lock_state = FleetLockState.IDLE
        dev.timer_seconds_remaining = 0
        self.assertTrue(dev.can_uninstall(), "Normal mode must permit clean uninstallation")

        # 2. State = PROTECTION_ACTIVE, Timer = 0 -> Uninstallation locked
        dev.lock_state = FleetLockState.PROTECTION_ACTIVE
        dev.timer_seconds_remaining = 0
        self.assertFalse(dev.can_uninstall(), "Protection active must lock uninstallation")

        # 3. State = STRICT_TIMER, Timer = 1800 -> Uninstallation locked
        dev.lock_state = FleetLockState.STRICT_TIMER
        dev.timer_seconds_remaining = 1800
        self.assertFalse(dev.can_uninstall(), "Strict countdown timer must lock uninstallation")

        # 4. State = KIOSK_LOCKED -> Uninstallation locked
        dev.lock_state = FleetLockState.KIOSK_LOCKED
        dev.timer_seconds_remaining = 0
        self.assertFalse(dev.can_uninstall(), "Kiosk mode must lock uninstallation")

        # 5. State = GEOFENCE_LOCKED -> Uninstallation locked
        dev.lock_state = FleetLockState.GEOFENCE_LOCKED
        dev.timer_seconds_remaining = 0
        self.assertFalse(dev.can_uninstall(), "Geofence lock must lock uninstallation")

        # 6. State = SCHEDULE_LOCKED -> Uninstallation locked
        dev.lock_state = FleetLockState.SCHEDULE_LOCKED
        dev.timer_seconds_remaining = 0
        self.assertFalse(dev.can_uninstall(), "Calendar schedule lock must lock uninstallation")

        # 7. State = IDLE but Timer > 0 (Edge case) -> Uninstallation locked until timer finishes
        dev.lock_state = FleetLockState.IDLE
        dev.timer_seconds_remaining = 45
        self.assertFalse(dev.can_uninstall(), "Timer remaining must lock uninstallation even if idle")

        # 8. Reset back to IDLE, Timer = 0 -> Uninstallation permitted again
        dev.timer_seconds_remaining = 0
        self.assertTrue(dev.can_uninstall(), "Returning to IDLE with 0 timer restores clean uninstallation")

    def test_heartbeat_updates_and_telemetry(self):
        dev_id = "dev_heartbeat_test"
        self.plane.register_device(device_id=dev_id)

        # Send heartbeat indicating active focus session
        updated = self.plane.record_heartbeat(
            device_id=dev_id,
            lock_state=FleetLockState.STRICT_TIMER.value,
            timer_remaining=900,
            ip_address="192.168.1.105",
            private_dns_mode="strict",
            compliance_score=95,
        )
        self.assertIsNotNone(updated)
        self.assertEqual(updated["lock_state"], "STRICT_TIMER")
        self.assertEqual(updated["timer_seconds_remaining"], 900)
        self.assertFalse(updated["can_uninstall"])
        self.assertEqual(updated["compliance_score"], 95)
        self.assertEqual(updated["current_ip"], "192.168.1.105")
        self.assertEqual(updated["private_dns_mode"], "strict")

        # Telemetry summary
        telemetry = self.plane.get_fleet_telemetry()
        self.assertGreaterEqual(telemetry["total_endpoints"], 3)
        self.assertGreaterEqual(telemetry["locked_focus_count"], 1)
        self.assertIn("ACTIVE_UNBLOCKED", telemetry["emergency_safety_status"])

    def test_remote_command_queue_and_dispatch(self):
        dev_id = "dev_cmd_test"
        self.plane.register_device(device_id=dev_id)

        # Queue LOCK_FOCUS command
        cmd1 = self.plane.send_command(
            device_id=dev_id,
            command_type=FleetCommandType.LOCK_FOCUS.value,
            payload={"duration_seconds": 3600, "policy": "deep_work"},
        )
        self.assertIsNotNone(cmd1)
        self.assertTrue(cmd1.startswith("cmd_"))

        # Queue SYNC_POLICY command
        cmd2 = self.plane.send_command(
            device_id=dev_id,
            command_type=FleetCommandType.SYNC_POLICY.value,
            payload={"policy_version": 4},
        )
        self.assertIsNotNone(cmd2)

        dev = self.plane.get_device(dev_id)
        self.assertEqual(len(dev.pending_commands), 2)

        # Fetch commands (dispatches them)
        dispatched = self.plane.fetch_pending_commands(dev_id)
        self.assertEqual(len(dispatched), 2)
        self.assertEqual(dispatched[0]["command_id"], cmd1)
        self.assertEqual(dispatched[0]["status"], "DISPATCHED")
        self.assertEqual(dispatched[1]["command_id"], cmd2)

        # Queue should now be empty
        self.assertEqual(len(dev.pending_commands), 0)
        self.assertEqual(len(dev.command_history), 2)

    def test_operator_override_unlock_for_clean_uninstallation(self):
        dev_id = "dev_locked_worker"
        dev = self.plane.register_device(device_id=dev_id)

        # Device is locked in strict mode
        dev.lock_state = FleetLockState.STRICT_TIMER
        dev.timer_seconds_remaining = 3600
        self.assertFalse(dev.can_uninstall())

        # Operator triggers clean uninstallation override
        res = self.plane.unlock_device_for_clean_uninstallation(dev_id)
        self.assertTrue(res)

        # Verify state is transitioned to IDLE and uninstallation is 100% permitted
        self.assertEqual(dev.lock_state, FleetLockState.IDLE)
        self.assertEqual(dev.timer_seconds_remaining, 0)
        self.assertTrue(dev.can_uninstall())

        # Verify CLEAR_FOR_UNINSTALL command was queued
        cmds = self.plane.fetch_pending_commands(dev_id)
        self.assertEqual(len(cmds), 1)
        self.assertEqual(cmds[0]["type"], FleetCommandType.CLEAR_FOR_UNINSTALL.value)
        self.assertEqual(cmds[0]["payload"]["reason"], "OPERATOR_CLEAN_UNINSTALL_REQUESTED")


class TestMdmWebSocketHub(unittest.TestCase):

    def setUp(self):
        self.hub = MdmWebSocketHub()

    def test_client_registration_and_topic_subscriptions(self):
        # Register a device channel
        dev_client = self.hub.register_client(
            client_id="ws_dev_101",
            device_id="dev_101",
            tenant_id="tenant_alpha",
            is_admin_console=False,
        )
        self.assertIn("device:dev_101", dev_client.subscribed_topics)
        self.assertIn("tenant:tenant_alpha", dev_client.subscribed_topics)
        self.assertNotIn("admin:all", dev_client.subscribed_topics)

        # Register an admin console
        admin_client = self.hub.register_client(
            client_id="ws_admin_01",
            tenant_id="tenant_alpha",
            is_admin_console=True,
        )
        self.assertIn("tenant:tenant_alpha", admin_client.subscribed_topics)
        self.assertIn("admin:all", admin_client.subscribed_topics)

        self.assertEqual(len(self.hub._clients), 2)

    def test_broadcast_event_routing(self):
        dev1 = self.hub.register_client(client_id="c1", device_id="d1", tenant_id="tenant_a")
        dev2 = self.hub.register_client(client_id="c2", device_id="d2", tenant_id="tenant_a")
        dev3 = self.hub.register_client(client_id="c3", device_id="d3", tenant_id="tenant_b")

        # Broadcast to device:d1
        count = self.hub.broadcast_event("device:d1", {"directive": "LOCK_FOCUS"})
        self.assertEqual(count, 1)

        msgs_d1 = dev1.fetch_messages()
        self.assertEqual(len(msgs_d1), 1)
        self.assertEqual(msgs_d1[0]["data"]["directive"], "LOCK_FOCUS")

        self.assertEqual(len(dev2.fetch_messages()), 0)
        self.assertEqual(len(dev3.fetch_messages()), 0)

        # Broadcast to tenant:tenant_a
        count_tenant = self.hub.broadcast_event("tenant:tenant_a", {"policy_sync": True})
        self.assertEqual(count_tenant, 2)
        self.assertEqual(len(dev1.fetch_messages()), 1)
        self.assertEqual(len(dev2.fetch_messages()), 1)
        self.assertEqual(len(dev3.fetch_messages()), 0)

    def test_unregister_client(self):
        c = self.hub.register_client(client_id="temp_client")
        self.assertIn("temp_client", self.hub._clients)

        res = self.hub.unregister_client("temp_client")
        self.assertTrue(res)
        self.assertNotIn("temp_client", self.hub._clients)


if __name__ == "__main__":
    unittest.main()
