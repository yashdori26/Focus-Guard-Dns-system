"""
server/tests/test_engine_kiosk.py
Comprehensive unit test suite for FocusDNS LockTask (Dedicated Kiosk) Policy Manager.

Validates:
- Strict mandatory inclusion of emergency telecom dialers across all kiosk profiles:
  * com.android.phone
  * com.google.android.dialer
  * com.samsung.incallui
  * com.android.server.telecom
- Core FocusDNS Conditional Uninstallation & Kiosk Lifecycle Law:
  * When Focus Mode is ACTIVE (is_focus_active=True): Directs endpoint to start LockTask kiosk.
  * When Normal Mode is ACTIVE (is_focus_active=False): Directs endpoint to stop LockTask kiosk,
    restoring standard launcher and permitting clean uninstallation.
- Fleet-wide device profile mapping and dynamic evaluation.
- Custom multi-app study/productivity kiosk configurations.
"""

import unittest
from server.engine.kiosk_policy_manager import (
    KioskPolicyManager,
    KioskProfile,
    MANDATORY_EMERGENCY_PACKAGES,
)


class TestKioskPolicyManager(unittest.TestCase):

    def setUp(self):
        self.manager = KioskPolicyManager()

    def test_default_profiles_initialized(self):
        profiles = self.manager.list_profiles()
        self.assertGreaterEqual(len(profiles), 2)
        p_ids = [p["profile_id"] for p in profiles]
        self.assertIn("kiosk_strict_focus", p_ids)
        self.assertIn("kiosk_study_utility", p_ids)

    def test_mandatory_emergency_packages_constant_integrity(self):
        self.assertIn("com.android.phone", MANDATORY_EMERGENCY_PACKAGES)
        self.assertIn("com.google.android.dialer", MANDATORY_EMERGENCY_PACKAGES)
        self.assertIn("com.samsung.incallui", MANDATORY_EMERGENCY_PACKAGES)
        self.assertIn("com.android.server.telecom", MANDATORY_EMERGENCY_PACKAGES)
        self.assertEqual(len(MANDATORY_EMERGENCY_PACKAGES), 4)

    def test_kiosk_profile_always_includes_emergency_dialers_even_when_omitted(self):
        # Explicitly create profile with empty allowed packages
        prof = KioskProfile(
            profile_id="kiosk_empty_test",
            name="Empty Test Kiosk",
            primary_app="com.focusdns.app",
            allowed_packages=[],
        )
        for emer_pkg in MANDATORY_EMERGENCY_PACKAGES:
            self.assertIn(emer_pkg, prof.allowed_packages)
        self.assertIn("com.focusdns.app", prof.allowed_packages)

    def test_kiosk_profile_always_includes_emergency_dialers_with_custom_apps(self):
        prof = KioskProfile(
            profile_id="kiosk_custom_apps",
            name="Custom Apps Kiosk",
            primary_app="com.focusdns.app",
            allowed_packages=["com.calculator", "com.dictionary"],
        )
        self.assertIn("com.calculator", prof.allowed_packages)
        self.assertIn("com.dictionary", prof.allowed_packages)
        for emer_pkg in MANDATORY_EMERGENCY_PACKAGES:
            self.assertIn(emer_pkg, prof.allowed_packages)

    def test_evaluate_kiosk_directive_normal_mode_clears_kiosk_for_clean_uninstall(self):
        dev_id = "pixel_endpoint_01"
        # In normal mode (focus not active), kiosk directive is FALSE
        res = self.manager.evaluate_kiosk_directive(dev_id, is_focus_active=False)
        self.assertFalse(res["kiosk_active"])
        self.assertEqual(res["action"], "STOP_KIOSK")
        self.assertTrue(res["uninstallation_permitted"])
        self.assertEqual(res["device_id"], dev_id)
        # Normal mode unlocks device, allowing clean uninstallation

    def test_evaluate_kiosk_directive_active_focus_enforces_kiosk(self):
        dev_id = "pixel_endpoint_02"
        # During active focus, kiosk directive is TRUE
        res = self.manager.evaluate_kiosk_directive(dev_id, is_focus_active=True)
        self.assertTrue(res["kiosk_active"])
        self.assertEqual(res["action"], "START_KIOSK")
        self.assertFalse(res["uninstallation_permitted"])
        for emer_pkg in MANDATORY_EMERGENCY_PACKAGES:
            self.assertIn(emer_pkg, res["allowed_packages"])

    def test_assign_profile_to_device(self):
        dev_id = "study_tablet_01"
        self.assertTrue(
            self.manager.assign_profile_to_device(dev_id, "kiosk_study_utility")
        )
        res = self.manager.evaluate_kiosk_directive(dev_id, is_focus_active=True)
        self.assertEqual(res["profile_id"], "kiosk_study_utility")
        self.assertIn("com.google.android.calculator", res["allowed_packages"])

    def test_assign_invalid_profile_returns_false(self):
        self.assertFalse(
            self.manager.assign_profile_to_device("dev_01", "nonexistent_profile")
        )

    def test_save_and_retrieve_custom_profile(self):
        custom = KioskProfile(
            profile_id="kiosk_k12_exam",
            name="K-12 Exam Lockdown",
            primary_app="com.focusdns.app",
            allowed_packages=["org.exam.tester"],
            allow_system_info=False,
            allow_keyguard=False,
            allow_notifications=False,
        )
        self.manager.save_profile(custom)
        retrieved = self.manager.get_profile("kiosk_k12_exam")
        self.assertIsNotNone(retrieved)
        self.assertEqual(retrieved.name, "K-12 Exam Lockdown")
        self.assertFalse(retrieved.allow_system_info)
        self.assertIn("org.exam.tester", retrieved.allowed_packages)
        self.assertIn("com.android.phone", retrieved.allowed_packages)

    def test_get_profile_default_fallback(self):
        default_prof = self.manager.get_profile("default")
        self.assertIsNotNone(default_prof)
        self.assertEqual(default_prof.profile_id, "kiosk_strict_focus")

    def test_profile_serialization_round_trip(self):
        prof = KioskProfile(
            profile_id="kiosk_serial",
            name="Serialization Test Profile",
            primary_app="com.focusdns.app",
            allowed_packages=["com.test.app"],
            allow_system_info=True,
            allow_keyguard=True,
            allow_notifications=True,
            enforce_on_focus=True,
        )
        d = prof.to_dict()
        self.assertEqual(d["profile_id"], "kiosk_serial")
        self.assertEqual(d["name"], "Serialization Test Profile")
        self.assertTrue(d["allow_system_info"])
        self.assertTrue(d["allow_notifications"])
        self.assertIn("com.test.app", d["allowed_packages"])
        self.assertIn("com.android.phone", d["allowed_packages"])
        self.assertIn("created_at", d)


if __name__ == "__main__":
    unittest.main()
