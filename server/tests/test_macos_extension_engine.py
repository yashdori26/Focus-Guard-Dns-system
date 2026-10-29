"""
Unit tests for macOS Network Extension Manager & MobileConfig Generator.
"""

import unittest
import plistlib
from server.engine.macos_extension_manager import MacOsExtensionManager


class TestMacOsExtensionManager(unittest.TestCase):

    def setUp(self):
        self.manager = MacOsExtensionManager()

    def test_initial_state_permits_uninstallation(self):
        status = self.manager.get_status()
        self.assertEqual(status["platform"], "macOS")
        self.assertTrue(status["can_uninstall"])
        self.assertFalse(status["is_protection_active"])
        self.assertEqual(status["remaining_timer_seconds"], 0)

    def test_mobileconfig_unlocked_posture(self):
        config_bytes = self.manager.generate_mobileconfig()
        self.assertIsInstance(config_bytes, bytes)

        parsed = plistlib.loads(config_bytes)
        self.assertEqual(parsed["PayloadType"], "Configuration")
        self.assertFalse(parsed["PayloadRemovalDisallowed"]) # Allowed when idle

        payloads = parsed["PayloadContent"]
        self.assertEqual(len(payloads), 3)

        payload_types = [p["PayloadType"] for p in payloads]
        self.assertIn("com.apple.systemextensions.install", payload_types)
        self.assertIn("com.apple.dnsProxy.managed", payload_types)
        self.assertIn("com.apple.webcontent-filter", payload_types)

    def test_mobileconfig_locked_during_focus_session(self):
        self.manager.set_protection(active=True, timer_seconds=1800)
        self.assertFalse(self.manager.can_uninstall())

        config_bytes = self.manager.generate_mobileconfig()
        parsed = plistlib.loads(config_bytes)
        # Conditional Uninstallation Law: Disallow removal
        self.assertTrue(parsed["PayloadRemovalDisallowed"])

        # Check DNS proxy payload configuration reflects lock
        dns_payload = next(p for p in parsed["PayloadContent"] if p["PayloadType"] == "com.apple.dnsProxy.managed")
        self.assertTrue(dns_payload["ProviderConfiguration"]["isFocusLockActive"])
        self.assertEqual(dns_payload["ProviderConfiguration"]["remainingTimerSeconds"], 1800)

    def test_launchd_plist_generation(self):
        plist_xml = self.manager.generate_launchd_plist()
        self.assertIn("com.focusguard.dns.daemon", plist_xml)
        self.assertIn("/usr/local/bin/focusguard-daemon", plist_xml)
        self.assertIn("KeepAlive", plist_xml)

    def test_telemetry_tamper_attempt_rejection(self):
        # 1. Permitted when idle
        res = self.manager.process_telemetry_event({"event_type": "ATTEMPT_UNINSTALL"})
        self.assertEqual(res["status"], "OK")
        self.assertTrue(res["can_uninstall"])

        # 2. Denied when focus lock is active
        self.manager.set_protection(active=True, timer_seconds=600)
        res_locked = self.manager.process_telemetry_event({"event_type": "ATTEMPT_UNINSTALL"})
        self.assertEqual(res_locked["status"], "REJECTED")
        self.assertEqual(res_locked["error_code"], "ERROR_ACCESS_DENIED")

        # Unlock and verify restoration
        self.manager.set_protection(active=False, timer_seconds=0)
        self.assertTrue(self.manager.can_uninstall())


if __name__ == "__main__":
    unittest.main()
