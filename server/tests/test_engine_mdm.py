"""
Unit and integration tests for FocusDNS Enterprise MDM, Anti-Bypass Device Administration,
and Conditional Uninstallation Protection subsystem.
"""

import io
import json
import time
import unittest
from unittest.mock import MagicMock, patch

from server.engine.mdm_server import (
    DeviceFleetManager,
    DeviceRecord,
    DeviceStatus,
    MdmPolicyProfile,
    PolicyLockMode,
    SplitTunnelPolicyMode,
    get_fleet_manager,
)
from server.engine.cli_engine import (
    cmd_mdm_fleet,
    cmd_mdm_device,
    cmd_mdm_check_uninstall,
    cmd_mdm_policy,
    main,
)
from server.api_router import FocusDNSApiHandler


class TestDeviceRecord(unittest.TestCase):
    def test_default_device_record(self):
        """Validates default initialization of an enrolled device record."""
        dev = DeviceRecord("dev-001", "Pixel 8 Pro")
        self.assertEqual(dev.device_id, "dev-001")
        self.assertEqual(dev.device_name, "Pixel 8 Pro")
        self.assertEqual(dev.platform, "Android")
        self.assertEqual(dev.os_version, "14")
        self.assertEqual(dev.status, DeviceStatus.ACTIVE)
        self.assertTrue(dev.can_uninstall)
        self.assertFalse(dev.is_protection_active)
        self.assertFalse(dev.is_timer_active)
        self.assertEqual(dev.remaining_timer_sec, 0)
        self.assertEqual(dev.integrity_score, 100)
        self.assertIsNotNone(dev.secret_key)

    def test_update_telemetry_active_session(self):
        """Validates parsing of telemetry payload during active focus timer session."""
        dev = DeviceRecord("dev-002", "Galaxy S24")
        payload = {
            "lockStatus": {
                "isProtectionActive": True,
                "isTimerActive": True,
                "remainingSeconds": 1500,
                "canUninstall": False,
            },
            "mdmStatus": {
                "isDeviceAdminActive": True,
                "isDeviceOwner": False,
            },
            "antiTamper": {
                "integrityScore": 95,
            },
            "quarantine": {
                "quarantinedCount": 4,
            },
            "splitTunnel": {
                "selectedCount": 2,
            },
        }
        dev.update_telemetry(payload)
        self.assertTrue(dev.is_protection_active)
        self.assertTrue(dev.is_timer_active)
        self.assertEqual(dev.remaining_timer_sec, 1500)
        self.assertFalse(dev.can_uninstall)
        self.assertTrue(dev.device_admin_active)
        self.assertEqual(dev.integrity_score, 95)
        self.assertEqual(dev.quarantined_apps_count, 4)
        self.assertEqual(dev.split_tunnel_exempt_count, 2)
        self.assertEqual(dev.status, DeviceStatus.ACTIVE)

    def test_tamper_detection_drops_status(self):
        """Validates that integrity score below 50 flags device status as TAMPERED."""
        dev = DeviceRecord("dev-003", "OnePlus 12 Rooted")
        payload = {
            "antiTamper": {
                "integrityScore": 30,
            }
        }
        dev.update_telemetry(payload)
        self.assertEqual(dev.integrity_score, 30)
        self.assertEqual(dev.status, DeviceStatus.TAMPERED)

    def test_to_dict_serialization(self):
        """Verifies dictionary representation for REST responses."""
        dev = DeviceRecord("dev-004", "Xiaomi 14", platform="Android", os_version="15")
        data = dev.to_dict()
        self.assertEqual(data["device_id"], "dev-004")
        self.assertEqual(data["device_name"], "Xiaomi 14")
        self.assertEqual(data["platform"], "Android")
        self.assertEqual(data["os_version"], "15")
        self.assertIn("last_seen_sec_ago", data)
        self.assertIn("enrolled_at", data)


class TestMdmPolicyProfile(unittest.TestCase):
    def test_default_policy(self):
        """Checks default parameters for enterprise policy profiles."""
        pol = MdmPolicyProfile("default", "Standard Policy")
        self.assertEqual(pol.profile_id, "default")
        self.assertEqual(pol.name, "Standard Policy")
        self.assertEqual(pol.lock_mode, PolicyLockMode.CONDITIONAL_ON_PROTECTION)
        self.assertEqual(pol.split_tunnel_mode, SplitTunnelPolicyMode.DISALLOW_LIST)
        self.assertIn("com.whatsapp", pol.exempt_packages)
        self.assertTrue(pol.disallow_safe_boot)
        self.assertTrue(pol.disallow_vpn_config)
        self.assertFalse(pol.camera_disabled)

    def test_custom_policy_to_dict(self):
        """Verifies custom lock modes and split tunnel configurations."""
        pol = MdmPolicyProfile(
            "kiosk-profile",
            "Exam Kiosk Mode",
            lock_mode=PolicyLockMode.ALWAYS_LOCKED,
            split_tunnel_mode=SplitTunnelPolicyMode.ALLOW_LIST,
            exempt_packages=["com.exam.client"],
            camera_disabled=True,
        )
        d = pol.to_dict()
        self.assertEqual(d["profile_id"], "kiosk-profile")
        self.assertEqual(d["lock_mode"], "always_locked")
        self.assertEqual(d["split_tunnel_mode"], "allow_list")
        self.assertEqual(d["exempt_packages"], ["com.exam.client"])
        self.assertTrue(d["camera_disabled"])


class TestDeviceFleetManager(unittest.TestCase):
    def setUp(self):
        self.fleet = DeviceFleetManager()

    def test_enrollment_and_retrieval(self):
        """Tests device enrollment, retrieval, and listing."""
        rec = self.fleet.enroll_device("dev-101", "Work Phone", platform="Android", admin_active=True)
        self.assertEqual(rec.device_id, "dev-101")
        self.assertTrue(rec.device_admin_active)

        retrieved = self.fleet.get_device("dev-101")
        self.assertIsNotNone(retrieved)
        self.assertEqual(retrieved.device_name, "Work Phone")

        devices = self.fleet.list_devices()
        self.assertEqual(len(devices), 1)

    def test_remove_device(self):
        """Tests unenrollment and audit recording."""
        self.fleet.enroll_device("dev-102", "Temporary Tablet")
        self.assertTrue(self.fleet.remove_device("dev-102"))
        self.assertIsNone(self.fleet.get_device("dev-102"))
        self.assertFalse(self.fleet.remove_device("dev-102"))

        # Verify audit log recorded unenrollment
        audit = self.fleet.get_audit_log(10)
        unenroll_events = [ev for ev in audit if ev["event_type"] == "DEVICE_UNENROLLED"]
        self.assertTrue(len(unenroll_events) >= 1)

    def test_telemetry_auto_enrollment(self):
        """Tests that telemetry from a previously unseen device auto-enrolls it."""
        payload = {
            "deviceModel": "Auto-Enrolled Device",
            "lockStatus": {"isProtectionActive": False, "canUninstall": True},
        }
        self.fleet.process_telemetry("dev-auto-1", payload)
        dev = self.fleet.get_device("dev-auto-1")
        self.assertIsNotNone(dev)
        self.assertEqual(dev.device_name, "Auto-Enrolled Device")

    def test_audit_log_ring_buffer(self):
        """Verifies audit log remains bounded at 1000 records."""
        for i in range(1050):
            self.fleet._append_audit("TEST_EVENT", f"target-{i}", f"Log entry {i}")
        self.assertEqual(len(self.fleet._audit_log), 1000)
        logs = self.fleet.get_audit_log(50)
        self.assertEqual(len(logs), 50)

    def test_fleet_telemetry_aggregation(self):
        """Tests aggregated telemetry metrics across fleet devices."""
        # Device 1: idle, unlocked
        self.fleet.enroll_device("d1", "Phone 1", admin_active=True)

        # Device 2: locked with active session
        d2 = self.fleet.enroll_device("d2", "Phone 2", admin_active=True)
        d2.can_uninstall = False

        # Device 3: tampered
        d3 = self.fleet.enroll_device("d3", "Phone 3", admin_active=False)
        d3.status = DeviceStatus.TAMPERED

        summary = self.fleet.get_fleet_telemetry()
        self.assertEqual(summary["total_devices"], 3)
        self.assertEqual(summary["uninstallation_locked_devices"], 1)
        self.assertEqual(summary["device_admin_active_devices"], 2)
        self.assertEqual(summary["tampered_devices"], 1)


class TestUninstallationTruthTable(unittest.TestCase):
    """
    Exhaustively tests the user's core uninstallation requirement:
    - App CAN be uninstalled normally when idle.
    - BUT if protection mode is ON or timer mode is active, uninstallation is strictly blocked.
    """

    def setUp(self):
        self.fleet = DeviceFleetManager()
        self.dev = self.fleet.enroll_device("user-device", "Primary Pixel")

    def test_truth_table_idle_mode_uninstallation_permitted(self):
        """Protection OFF and Timer 0 => canUninstall == True."""
        self.dev.is_protection_active = False
        self.dev.is_timer_active = False
        self.dev.remaining_timer_sec = 0

        allowed, reason = self.fleet.evaluate_uninstall_permission("user-device")
        self.assertTrue(allowed)
        self.assertEqual(reason, "SESSION_IDLE_UNINSTALL_PERMITTED")

    def test_truth_table_protection_active_blocks_uninstallation(self):
        """Protection ON and Timer 0 => canUninstall == False."""
        self.dev.is_protection_active = True
        self.dev.is_timer_active = False
        self.dev.remaining_timer_sec = 0

        allowed, reason = self.fleet.evaluate_uninstall_permission("user-device")
        self.assertFalse(allowed)
        self.assertEqual(reason, "PROTECTION_ACTIVE")

    def test_truth_table_timer_active_blocks_uninstallation(self):
        """Protection OFF and Timer > 0 => canUninstall == False."""
        self.dev.is_protection_active = False
        self.dev.is_timer_active = True
        self.dev.remaining_timer_sec = 1800

        allowed, reason = self.fleet.evaluate_uninstall_permission("user-device")
        self.assertFalse(allowed)
        self.assertIn("TIMER_ACTIVE_1800s_REMAINING", reason)

    def test_truth_table_both_active_blocks_uninstallation(self):
        """Protection ON and Timer > 0 => canUninstall == False."""
        self.dev.is_protection_active = True
        self.dev.is_timer_active = True
        self.dev.remaining_timer_sec = 3600

        allowed, reason = self.fleet.evaluate_uninstall_permission("user-device")
        self.assertFalse(allowed)
        self.assertEqual(reason, "PROTECTION_ACTIVE")

    def test_truth_table_timer_expiration_allows_uninstallation(self):
        """Active timer expires to 0 and protection turns OFF => canUninstall == True."""
        # 1. Active timer running
        self.dev.is_protection_active = False
        self.dev.is_timer_active = True
        self.dev.remaining_timer_sec = 5
        self.assertFalse(self.fleet.evaluate_uninstall_permission("user-device")[0])

        # 2. Timer elapses to zero
        self.dev.is_timer_active = False
        self.dev.remaining_timer_sec = 0
        allowed, reason = self.fleet.evaluate_uninstall_permission("user-device")
        self.assertTrue(allowed)
        self.assertEqual(reason, "SESSION_IDLE_UNINSTALL_PERMITTED")

    def test_unenrolled_device_is_allowed(self):
        """Non-enrolled endpoints are not blocked."""
        allowed, reason = self.fleet.evaluate_uninstall_permission("unknown-device")
        self.assertTrue(allowed)
        self.assertEqual(reason, "DEVICE_NOT_ENROLLED")

    def test_policy_always_allowed_override(self):
        """Policy override ALWAYS_ALLOWED permits uninstallation even if session is running."""
        custom_pol = MdmPolicyProfile("loose", "Loose Policy", lock_mode=PolicyLockMode.ALWAYS_ALLOWED)
        self.fleet.set_policy(custom_pol)
        self.dev.profile_id = "loose"
        self.dev.is_protection_active = True
        self.dev.remaining_timer_sec = 1000

        allowed, reason = self.fleet.evaluate_uninstall_permission("user-device")
        self.assertTrue(allowed)
        self.assertEqual(reason, "POLICY_ALWAYS_ALLOWED")

    def test_policy_always_locked_enterprise_kiosk(self):
        """Policy override ALWAYS_LOCKED forbids uninstallation even when completely idle."""
        kiosk_pol = MdmPolicyProfile("kiosk", "Kiosk Policy", lock_mode=PolicyLockMode.ALWAYS_LOCKED)
        self.fleet.set_policy(kiosk_pol)
        self.dev.profile_id = "kiosk"
        self.dev.is_protection_active = False
        self.dev.remaining_timer_sec = 0

        allowed, reason = self.fleet.evaluate_uninstall_permission("user-device")
        self.assertFalse(allowed)
        self.assertEqual(reason, "ENTERPRISE_KIOSK_LOCKED")


class TestCLIMdmCommands(unittest.TestCase):
    def setUp(self):
        self.fm = get_fleet_manager()
        self.fm._devices.clear()
        self.fm._policies.clear()
        self.fm._policies["default"] = MdmPolicyProfile("default", "Standard Focus Guard Policy")

    def test_cli_mdm_fleet_empty(self):
        stdout_trap = io.StringIO()
        with patch("sys.stdout", stdout_trap):
            with patch("sys.argv", ["cli_engine", "mdm-fleet"]):
                main()
        out = stdout_trap.getvalue()
        self.assertIn("FOCUS-DNS ENTERPRISE MDM & DEVICE FLEET TELEMETRY", out)
        self.assertIn("Total Enrolled Endpoints:      0", out)

    def test_cli_mdm_fleet_with_devices(self):
        self.fm.enroll_device("cli-dev-1", "Samsung Note", platform="Android")
        stdout_trap = io.StringIO()
        with patch("sys.stdout", stdout_trap):
            with patch("sys.argv", ["cli_engine", "mdm-fleet"]):
                main()
        out = stdout_trap.getvalue()
        self.assertIn("Total Enrolled Endpoints:      1", out)
        self.assertIn("cli-dev-1", out)
        self.assertIn("Samsung Note", out)

    def test_cli_mdm_device_details(self):
        d = self.fm.enroll_device("cli-dev-2", "Pixel 7a", platform="Android", os_version="14")
        d.is_protection_active = True
        d.can_uninstall = False
        d.integrity_score = 98

        stdout_trap = io.StringIO()
        with patch("sys.stdout", stdout_trap):
            with patch("sys.argv", ["cli_engine", "mdm-device", "cli-dev-2"]):
                main()
        out = stdout_trap.getvalue()
        self.assertIn("DEVICE DETAILS: Pixel 7a (cli-dev-2)", out)
        self.assertIn("Protection Active:    YES", out)
        self.assertIn("Can Uninstall:        NO (STRICTLY LOCKED)", out)
        self.assertIn("Integrity Score:      98 / 100", out)

    def test_cli_mdm_check_uninstall_allowed(self):
        self.fm.enroll_device("cli-dev-3", "Test Device")
        stdout_trap = io.StringIO()
        with patch("sys.stdout", stdout_trap):
            with patch("sys.argv", ["cli_engine", "mdm-check-uninstall", "cli-dev-3"]):
                main()
        out = stdout_trap.getvalue()
        self.assertIn("Allowed: True", out)
        self.assertIn("UNINSTALL PERMITTED", out)

    def test_cli_mdm_check_uninstall_blocked(self):
        d = self.fm.enroll_device("cli-dev-4", "Test Device 4")
        d.is_protection_active = True
        d.is_timer_active = True
        d.remaining_timer_sec = 600

        stdout_trap = io.StringIO()
        with patch("sys.stdout", stdout_trap):
            with patch("sys.argv", ["cli_engine", "mdm-check-uninstall", "cli-dev-4"]):
                main()
        out = stdout_trap.getvalue()
        self.assertIn("Allowed: False", out)
        self.assertIn("UNINSTALLATION BLOCKED", out)

    def test_cli_mdm_policy_inspection_and_update(self):
        stdout_trap = io.StringIO()
        with patch("sys.stdout", stdout_trap):
            with patch("sys.argv", ["cli_engine", "mdm-policy", "--profile-id", "default"]):
                main()
        out = stdout_trap.getvalue()
        self.assertIn("MDM POLICY PROFILE", out)
        self.assertIn("conditional_on_protection", out)

        # Update lock mode via CLI
        stdout_trap2 = io.StringIO()
        with patch("sys.stdout", stdout_trap2):
            with patch("sys.argv", ["cli_engine", "mdm-policy", "--profile-id", "default", "--set-lock-mode", "always_locked"]):
                main()
        out2 = stdout_trap2.getvalue()
        self.assertIn("Policy 'default' lock mode updated to: always_locked", out2)

        pol = self.fm.get_policy("default")
        self.assertEqual(pol.lock_mode, PolicyLockMode.ALWAYS_LOCKED)


class TestRestMdmApiEndpoints(unittest.TestCase):
    def setUp(self):
        self.fm = get_fleet_manager()
        self.fm._devices.clear()
        self.fm._policies.clear()
        self.fm._policies["default"] = MdmPolicyProfile("default", "Standard Focus Guard Policy")

    @patch("server.api_router.db.verify_api_token", return_value=True)
    def test_api_enroll_and_telemetry(self, mock_auth):
        """Simulates REST API calls to /api/v1/mdm/enroll and /api/v1/mdm/telemetry."""
        handler = MagicMock()
        FocusDNSApiHandler._set_cors_headers = MagicMock()
        FocusDNSApiHandler._send_json = MagicMock()
        FocusDNSApiHandler._send_error = MagicMock()

        # Enroll
        self.fm.enroll_device("api-dev-1", "Moto G84", platform="Android", os_version="14")
        dev = self.fm.get_device("api-dev-1")
        self.assertIsNotNone(dev)
        self.assertTrue(dev.can_uninstall)

        # Process telemetry payload indicating active timer
        telemetry_payload = {
            "lockStatus": {
                "isProtectionActive": True,
                "isTimerActive": True,
                "remainingSeconds": 900,
                "canUninstall": False,
            }
        }
        self.fm.process_telemetry("api-dev-1", telemetry_payload)
        self.assertFalse(dev.can_uninstall)
        self.assertTrue(dev.is_protection_active)
        self.assertEqual(dev.remaining_timer_sec, 900)

        # Check uninstall permission
        allowed, reason = self.fm.evaluate_uninstall_permission("api-dev-1")
        self.assertFalse(allowed)
        self.assertEqual(reason, "PROTECTION_ACTIVE")


if __name__ == "__main__":
    unittest.main()
