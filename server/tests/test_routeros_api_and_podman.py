"""
Unit tests for RouterOS API Client and UniFi Podman Daemon.

Verifies:
  1. RouterOS sentence protocol binary word length encoding and decoding.
  2. RouterOS mock API commands, firewall provisioning, and conditional teardown.
  3. UniFi Podman container daemon lifecycle, on_boot script compilation.
  4. Watchdog health probes, consecutive failure tracking, and fail-safe fallback.
  5. Conditional Uninstallation Law across both platforms.
"""

import io
import unittest
from router.mikrotik.routeros_api_client import (
    RouterOSWordEncoder, RouterOSApiClient, RouterOSAPIError
)
from router.ubiquiti.unifi_podman_daemon import UnifiPodmanDaemon


class TestRouterOSApiClient(unittest.TestCase):
    def test_word_encoder_single_byte(self):
        # Length < 0x80 (128)
        encoded = RouterOSWordEncoder.encode_length(42)
        self.assertEqual(len(encoded), 1)
        self.assertEqual(encoded[0], 42)

        stream = io.BytesIO(encoded)
        decoded = RouterOSWordEncoder.decode_length(stream.read)
        self.assertEqual(decoded, 42)

    def test_word_encoder_two_bytes(self):
        # 0x80 <= Length < 0x4000 (16384)
        encoded = RouterOSWordEncoder.encode_length(1024)
        self.assertEqual(len(encoded), 2)
        self.assertTrue(encoded[0] & 0x80 != 0)

        stream = io.BytesIO(encoded)
        decoded = RouterOSWordEncoder.decode_length(stream.read)
        self.assertEqual(decoded, 1024)

    def test_word_encoder_three_bytes(self):
        # 0x4000 <= Length < 0x200000 (2097152)
        encoded = RouterOSWordEncoder.encode_length(70000)
        self.assertEqual(len(encoded), 3)

        stream = io.BytesIO(encoded)
        decoded = RouterOSWordEncoder.decode_length(stream.read)
        self.assertEqual(decoded, 70000)

    def test_client_mock_lifecycle(self):
        client = RouterOSApiClient(mock_mode=True)
        self.assertTrue(client.connect())
        self.assertTrue(client.login("admin", "secret"))

        # Test command execution
        ident = client.execute_command("/system/identity/print")
        self.assertEqual(len(ident), 1)
        self.assertEqual(ident[0]["name"], "FocusGuard-RouterOS-v7")

        res = client.execute_command("/system/resource/print")
        self.assertEqual(res[0]["version"], "7.14")

        # Provision rules
        self.assertTrue(client.provision_focusguard_dns(local_proxy_ip="127.0.0.1", local_port=5353))
        posture = client.get_firewall_posture()
        self.assertTrue(posture["connected"])
        self.assertTrue(posture["can_uninstall"])

        client.close()

    def test_client_conditional_uninstallation_law(self):
        client = RouterOSApiClient(mock_mode=True)
        client.connect()
        client.login()
        client.provision_focusguard_dns()

        # Active focus: deprovisioning strictly prohibited
        client.set_focus_posture(is_active=True, timer_seconds=2400)
        self.assertFalse(client.can_uninstall())
        with self.assertRaises(PermissionError) as ctx:
            client.deprovision_focusguard()
        self.assertIn("ERROR_ACCESS_DENIED", str(ctx.exception))

        # Idle mode: deprovisioning succeeds
        client.set_focus_posture(is_active=False, timer_seconds=0)
        self.assertTrue(client.can_uninstall())
        self.assertTrue(client.deprovision_focusguard())


class TestUnifiPodmanDaemon(unittest.TestCase):
    def setUp(self):
        self.daemon = UnifiPodmanDaemon(mock_mode=True, watchdog_interval_seconds=0.1)

    def tearDown(self):
        self.daemon.stop()

    def test_lifecycle_and_on_boot_script(self):
        script = self.daemon.generate_on_boot_script(profile_id="profile_focus_kids")
        self.assertIn("podman run", script)
        self.assertIn("profile_focus_kids", script)
        self.assertIn("iptables -t nat -A FOCUSGUARD_DNS", script)
        # Port 853 DoT bypass rejection
        self.assertIn("--dport 853 -j FOCUSGUARD_BLOCK_BYPASS", script)

        self.assertTrue(self.daemon.start("profile_focus_kids"))
        status = self.daemon.get_status()
        self.assertTrue(status["is_running"])
        self.assertFalse(status["is_fallback_mode"])
        self.assertTrue(status["can_uninstall"])

        self.daemon.stop()
        self.assertFalse(self.daemon.get_status()["is_running"])

    def test_device_profile_assignment(self):
        self.daemon.assign_device_profile("AA:BB:CC:DD:EE:FF", "profile_gaming_blocked")
        status = self.daemon.get_status()
        self.assertEqual(status["monitored_devices_count"], 1)

    def test_fail_safe_fallback_engagement(self):
        self.daemon.start()
        # Simulate consecutive health failures
        self.daemon._engage_fail_safe_fallback()
        status = self.daemon.get_status()
        self.assertTrue(status["is_fallback_mode"])
        self.assertEqual(status["restart_count"], 1)

        # Recovery
        self.daemon._restore_filtering()
        self.assertFalse(self.daemon.get_status()["is_fallback_mode"])

    def test_conditional_uninstallation_law(self):
        self.daemon.start()

        # Active focus: teardown prohibited
        self.daemon.set_focus_posture(is_active=True, timer_seconds=3600)
        self.assertFalse(self.daemon.can_uninstall())
        with self.assertRaises(PermissionError) as ctx:
            self.daemon.uninstall()
        self.assertIn("ERROR_ACCESS_DENIED", str(ctx.exception))

        # Idle mode: teardown allowed
        self.daemon.set_focus_posture(is_active=False, timer_seconds=0)
        self.assertTrue(self.daemon.can_uninstall())
        self.assertTrue(self.daemon.uninstall())


if __name__ == "__main__":
    unittest.main()
