"""
server/tests/test_engine_private_dns.py
Unit and Integration Tests for Android 9+ Private DNS (DoT) Defense & Multi-OEM Telemetry.
"""

import time
import unittest

from server.engine.private_dns_server import (
    PrivateDnsRule,
    PrivateDnsServerManager,
    PrivateDnsAuditLog,
)
from server.engine.oem_telemetry_collector import (
    OemTelemetryCollector,
    EVASION_CLEAR_STORAGE,
    EVASION_FORCE_STOP,
    EVASION_ADMIN_DISABLE,
    EVASION_PRIVATE_DNS,
    EVASION_TIME_ROLLBACK,
    EVASION_DEVELOPER_OPTIONS,
    EVASION_ROOT_PROBE,
    EXEMPTION_EMERGENCY_CALL,
)


class TestPrivateDnsEngine(unittest.TestCase):
    def setUp(self):
        self.mgr = PrivateDnsServerManager()
        self.device_id = "test-galaxy-s24-001"

    def test_default_enterprise_rule_evaluates_compliant_opportunistic(self):
        res = self.mgr.evaluate_device_dns(self.device_id, mode="opportunistic", specifier="")
        self.assertTrue(res["compliant"])
        self.assertEqual(res["reason"], "PRIVATE_DNS_COMPLIANT")
        self.assertEqual(res["recommended_action"], "NONE")

    def test_default_enterprise_rule_evaluates_compliant_off(self):
        res = self.mgr.evaluate_device_dns(self.device_id, mode="off", specifier="")
        self.assertTrue(res["compliant"])
        self.assertEqual(res["reason"], "PRIVATE_DNS_COMPLIANT")

    def test_strict_mode_with_blacklisted_specifier_detected(self):
        res = self.mgr.evaluate_device_dns(self.device_id, mode="strict", specifier="dns.rogue-bypass.com")
        self.assertFalse(res["compliant"])
        self.assertIn("not permitted by policy", res["reason"])

    def test_custom_rule_with_approved_dot_specifier(self):
        custom_rule = PrivateDnsRule(
            rule_id="custom_dot_rule",
            name="Custom Corporate DoT",
            mode_allowed=["off", "opportunistic", "strict"],
            approved_hostnames=["dot.corporate-corp.internal"],
            blocked_hostnames=["dns.rogue-bypass.com"],
        )
        self.mgr.create_or_update_rule(custom_rule)
        self.mgr.assign_rule_to_device(self.device_id, "custom_dot_rule")

        # Approved corporate DoT passes
        res_approved = self.mgr.evaluate_device_dns(self.device_id, mode="strict", specifier="dot.corporate-corp.internal")
        self.assertTrue(res_approved["compliant"])

        # Unapproved third-party DoT fails
        res_unapproved = self.mgr.evaluate_device_dns(self.device_id, mode="strict", specifier="unapproved.freedns.org")
        self.assertFalse(res_unapproved["compliant"])
        self.assertIn("UNAPPROVED_DOT_HOST", res_unapproved["reason"])

    def test_audit_history_and_fleet_compliance_rate(self):
        self.mgr.evaluate_device_dns(self.device_id, mode="opportunistic", specifier="")
        self.mgr.evaluate_device_dns(self.device_id, mode="off", specifier="")
        self.mgr.evaluate_device_dns(self.device_id, mode="strict", specifier="dns.rogue-bypass.com")

        history = self.mgr.get_audit_history(self.device_id)
        self.assertEqual(len(history), 3)

        summary = self.mgr.get_fleet_compliance_summary()
        self.assertEqual(summary["total_checks"], 3)
        self.assertEqual(summary["compliant_checks"], 2)
        self.assertEqual(summary["non_compliant_checks"], 1)
        self.assertAlmostEqual(summary["compliance_rate_percent"], 66.67, places=1)


class TestOemTelemetryCollector(unittest.TestCase):
    def setUp(self):
        self.collector = OemTelemetryCollector()
        self.dev_oneui = "dev-samsung-oneui"
        self.dev_hyperos = "dev-xiaomi-hyperos"

    def test_emergency_calls_have_zero_penalty(self):
        self.collector.record_event(
            event_id="sos_001",
            device_id=self.dev_oneui,
            oem_vendor="Samsung OneUI",
            event_type=EXEMPTION_EMERGENCY_CALL,
            package_name="com.samsung.incallui",
            window_title="Emergency Call 911",
        )
        risk = self.collector.calculate_device_risk_score(self.dev_oneui)
        self.assertEqual(risk["risk_score"], 0)
        self.assertEqual(risk["risk_level"], "LOW")

    def test_repeated_evasion_accumulates_risk(self):
        # 1. Clear storage attempt (weight: 25)
        self.collector.record_event(
            event_id="ev_001",
            device_id=self.dev_hyperos,
            oem_vendor="Xiaomi HyperOS",
            event_type=EVASION_CLEAR_STORAGE,
            package_name="com.miui.securitycenter",
            window_title="Manage Apps - Storage",
        )
        risk1 = self.collector.calculate_device_risk_score(self.dev_hyperos)
        self.assertEqual(risk1["risk_score"], 25)
        self.assertEqual(risk1["risk_level"], "MODERATE")

        # 2. Admin disable attempt (weight: 35) -> total 60 (ELEVATED)
        self.collector.record_event(
            event_id="ev_002",
            device_id=self.dev_hyperos,
            oem_vendor="Xiaomi HyperOS",
            event_type=EVASION_ADMIN_DISABLE,
            package_name="com.android.settings",
            window_title="Device Admin Apps",
        )
        risk2 = self.collector.calculate_device_risk_score(self.dev_hyperos)
        self.assertEqual(risk2["risk_score"], 60)
        self.assertEqual(risk2["risk_level"], "ELEVATED")

        # 3. Time rollback attempt (weight: 40) -> total 100 (CRITICAL)
        self.collector.record_event(
            event_id="ev_003",
            device_id=self.dev_hyperos,
            oem_vendor="Xiaomi HyperOS",
            event_type=EVASION_TIME_ROLLBACK,
            package_name="com.android.settings",
            window_title="Date and Time",
        )
        risk3 = self.collector.calculate_device_risk_score(self.dev_hyperos)
        self.assertEqual(risk3["risk_score"], 100)
        self.assertEqual(risk3["risk_level"], "CRITICAL")

    def test_fleet_security_summary(self):
        self.collector.record_event(
            event_id="e1",
            device_id="dev-pixel",
            oem_vendor="Google Pixel",
            event_type=EXEMPTION_EMERGENCY_CALL,
            package_name="com.google.android.dialer",
            window_title="Phone",
        )
        self.collector.record_event(
            event_id="e2",
            device_id="dev-samsung",
            oem_vendor="Samsung OneUI",
            event_type=EVASION_FORCE_STOP,
            package_name="com.samsung.android.settings",
            window_title="App Info",
        )

        summary = self.collector.get_fleet_security_summary()
        self.assertEqual(summary["total_monitored_devices"], 2)
        self.assertEqual(summary["emergency_calls_exempted"], 1)
        self.assertIn("Google Pixel", summary["oem_distribution"])
        self.assertIn("Samsung OneUI", summary["oem_distribution"])


if __name__ == "__main__":
    unittest.main()
