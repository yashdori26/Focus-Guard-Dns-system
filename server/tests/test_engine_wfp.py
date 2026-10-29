"""
server/tests/test_engine_wfp.py
Comprehensive Unit Test Suite for Windows Filtering Platform (WFP) Firewall Engine.

Verifies:
1. WFP rule compilation across ALE_AUTH_CONNECT and DATAGRAM_DATA layers.
2. Life-Safety & OS Exemption Law (svchost.exe, DHCP, loopback are never firewalled).
3. Kernel redirection of port 53 UDP/TCP traffic to local proxy (127.0.0.1:5353).
4. Drop rules for hardcoded public DoH IPs (1.1.1.1, 8.8.8.8, 9.9.9.9) and rogue DoT.
5. Inviolable Conditional Service Protection Law on Windows:
   - Normal Mode: Clean uninstallation & service stopping 100% permitted.
   - Active Focus Mode: Service stopping (sc stop) and uninstallation strictly locked.
6. Per-application network blockades (Steam, Discord, Chrome).
7. Win32 C++ header generation.
"""

import unittest
from server.engine.wfp_engine import (
    WfpRuleCompiler,
    WfpLayer,
    WfpAction,
    WfpMatchType,
    WfpCondition,
    WfpFilterRule,
    WfpSubLayer,
)
from server.engine.windows_daemon_controller import (
    WindowsDaemonController,
    WindowsAppPolicy,
    WindowsBypassAuditRecord,
)


class TestWfpEngine(unittest.TestCase):
    """Unit tests for WFP Rule Compiler and policy translation."""

    def setUp(self):
        self.compiler = WfpRuleCompiler(local_dns_proxy_port=5353)

    def test_condition_and_rule_serialization(self):
        """Verifies WfpCondition and WfpFilterRule dictionary serialization."""
        cond = WfpCondition(
            field_name="FWPM_CONDITION_IP_REMOTE_PORT",
            match_type=WfpMatchType.FWP_MATCH_EQUAL,
            value=53,
            description="DNS Port",
        )
        cd = cond.to_dict()
        self.assertEqual(cd["field"], "FWPM_CONDITION_IP_REMOTE_PORT")
        self.assertEqual(cd["match"], "EQUAL")
        self.assertEqual(cd["value"], 53)

        rule = WfpFilterRule(
            rule_id="RULE_001",
            name="Test Rule",
            layer=WfpLayer.FWPM_LAYER_ALE_AUTH_CONNECT_V4,
            action=WfpAction.FWP_ACTION_BLOCK,
            conditions=[cond],
        )
        rd = rule.to_dict()
        self.assertEqual(rd["rule_id"], "RULE_001")
        self.assertEqual(rd["action"], "BLOCK")
        self.assertEqual(len(rd["conditions"]), 1)

    def test_sublayer_registration(self):
        """Verifies creation of Core Interception and Life-Safety sublayers."""
        summary = self.compiler.get_summary()
        sublayers = summary["sublayers"]
        self.assertEqual(len(sublayers), 2)
        keys = [s["sublayer_key"] for s in sublayers]
        self.assertIn(WfpRuleCompiler.SUBLAYER_GUID_CORE, keys)
        self.assertIn(WfpRuleCompiler.SUBLAYER_GUID_OVERRIDE, keys)

    def test_life_safety_and_os_critical_exemptions(self):
        """
        Life Safety & OS Exemption Law Verification:
        Windows Update (svchost.exe), DHCP, loopback, and FocusDNS daemon must be PERMITTED.
        """
        rules = self.compiler.compile_all_rules()
        rule_ids = [r.rule_id for r in rules]

        self.assertIn("EXEMPT_LOOPBACK_TRAFFIC", rule_ids)
        self.assertIn("EXEMPT_DHCP_TRAFFIC", rule_ids)
        self.assertIn("EXEMPT_WINDOWS_UPDATE", rule_ids)
        self.assertIn("EXEMPT_FOCUSDNS_DAEMON", rule_ids)

        for r in rules:
            if r.rule_id.startswith("EXEMPT_"):
                self.assertEqual(r.action, WfpAction.FWP_ACTION_PERMIT)
                self.assertEqual(r.sublayer_key, WfpRuleCompiler.SUBLAYER_GUID_OVERRIDE)
                self.assertGreaterEqual(r.weight, 0xF000)

    def test_port_53_redirection_rules(self):
        """Verifies outbound port 53 UDP/TCP queries are intercepted and directed to callout."""
        rules = self.compiler.compile_all_rules()
        udp_rule = next((r for r in rules if r.rule_id == "REDIRECT_DNS_UDP_PORT_53"), None)
        tcp_rule = next((r for r in rules if r.rule_id == "REDIRECT_DNS_TCP_PORT_53"), None)

        self.assertIsNotNone(udp_rule)
        self.assertIsNotNone(tcp_rule)
        self.assertEqual(udp_rule.action, WfpAction.FWP_ACTION_CALLOUT_TERMINATING)
        self.assertEqual(tcp_rule.action, WfpAction.FWP_ACTION_CALLOUT_TERMINATING)
        self.assertIsNotNone(udp_rule.callout_guid)

    def test_rogue_doh_and_dot_defense(self):
        """Verifies blocking direct HTTPS connections to public DoH resolvers and rogue DoT."""
        rules = self.compiler.compile_all_rules()
        dot_rule = next((r for r in rules if r.rule_id == "BLOCK_ROGUE_DOT_PORT_853"), None)
        self.assertIsNotNone(dot_rule)
        self.assertEqual(dot_rule.action, WfpAction.FWP_ACTION_BLOCK)

        doh_rules = [r for r in rules if r.rule_id.startswith("BLOCK_DOH_RESOLVER_")]
        self.assertEqual(len(doh_rules), len(WfpRuleCompiler.ROGUE_DOH_IPS))
        for dr in doh_rules:
            self.assertEqual(dr.action, WfpAction.FWP_ACTION_BLOCK)

    def test_conditional_uninstallation_law(self):
        """
        Inviolable Conditional Uninstallation Law Verification:
        - Normal Mode: can_uninstall() == True
        - Active Focus Mode: can_uninstall() == False
        """
        self.assertTrue(self.compiler.can_uninstall())

        # Arm timer mode
        self.compiler.set_protection_state(active=False, remaining_seconds=600)
        self.assertFalse(self.compiler.can_uninstall())

        # Arm protection active
        self.compiler.set_protection_state(active=True, remaining_seconds=0)
        self.assertFalse(self.compiler.can_uninstall())

        # Disarm to normal mode
        self.compiler.set_protection_state(active=False, remaining_seconds=0)
        self.assertTrue(self.compiler.can_uninstall())

    def test_per_app_distraction_blockades(self):
        """Verifies per-process network blocks are compiled only during active focus."""
        self.compiler.configure_blocked_apps(["steam.exe", "discord.exe"])

        # When idle: app blockades are NOT active
        self.compiler.set_protection_state(active=False, remaining_seconds=0)
        rules_idle = self.compiler.compile_all_rules()
        steam_rule_idle = next((r for r in rules_idle if r.target_app == "steam.exe"), None)
        self.assertIsNone(steam_rule_idle)

        # When active: app blockades are compiled
        self.compiler.set_protection_state(active=True, remaining_seconds=1800)
        rules_active = self.compiler.compile_all_rules()
        steam_rule_active = next((r for r in rules_active if r.target_app == "steam.exe"), None)
        discord_rule_active = next((r for r in rules_active if r.target_app == "discord.exe"), None)

        self.assertIsNotNone(steam_rule_active)
        self.assertIsNotNone(discord_rule_active)
        self.assertEqual(steam_rule_active.action, WfpAction.FWP_ACTION_BLOCK)
        self.assertEqual(steam_rule_active.weight, 0x9000)

    def test_cpp_header_generation(self):
        """Verifies generation of Win32 C++ header containing GUIDs and macros."""
        self.compiler.compile_all_rules()
        header = self.compiler.generate_cpp_wfp_header()
        self.assertIn("#pragma once", header)
        self.assertIn("FOCUS_DNS_SUBLAYER_CORE", header)
        self.assertIn("FOCUS_DNS_LOCAL_PROXY_PORT 5353", header)
        self.assertIn("G_CAN_UNINSTALL = true", header)


class TestWindowsDaemonController(unittest.TestCase):
    """Unit tests for Windows Daemon Controller, service lifecycle, and anti-tamper logic."""

    def setUp(self):
        self.controller = WindowsDaemonController(is_mock_mode=True)

    def test_initial_state_normal_mode(self):
        """Verifies default controller state permits clean uninstallation."""
        status = self.controller.get_status()
        self.assertTrue(status["service_running"])
        self.assertFalse(status["is_protection_active"])
        self.assertEqual(status["remaining_timer_seconds"], 0)
        self.assertTrue(status["can_uninstall"])
        self.assertGreaterEqual(status["total_filters_installed"], 14)

    def test_service_stop_rejection_during_active_focus(self):
        """
        Anti-Tamper Law Verification:
        net stop FocusDnsWfpService must return ERROR_ACCESS_DENIED when focus is armed.
        """
        self.controller.arm_focus_lock(duration_seconds=1200)
        self.assertFalse(self.controller.can_uninstall())

        # Attempt to stop service
        allowed, msg = self.controller.simulate_service_stop_attempt()
        self.assertFalse(allowed)
        self.assertIn("ERROR_ACCESS_DENIED", msg)
        self.assertIn("1200s remaining", msg)
        self.assertTrue(self.controller.get_status()["service_running"])

        # Disarm to normal mode
        self.controller.disarm_focus_lock()
        self.assertTrue(self.controller.can_uninstall())

        # Now clean stop is permitted
        allowed_idle, msg_idle = self.controller.simulate_service_stop_attempt()
        self.assertTrue(allowed_idle)
        self.assertIn("SERVICE_STOPPED", msg_idle)
        self.assertFalse(self.controller.get_status()["service_running"])

    def test_app_blocking_and_unblocking(self):
        """Verifies adding and removing application-specific firewall filters."""
        self.controller.block_application("Spotify")
        status = self.controller.get_status()
        app_names = [a["app_name"].lower() for a in status["app_policies"]]
        self.assertIn("spotify", app_names)

        # Unblock
        success = self.controller.unblock_application("Spotify")
        self.assertTrue(success)
        status2 = self.controller.get_status()
        spot = next(a for a in status2["app_policies"] if a["app_name"].lower() == "spotify")
        self.assertFalse(spot["is_blocked"])

    def test_bypass_audit_logging_and_capping(self):
        """Verifies logging intercepted bypass events with ring buffer bounds (500 limit)."""
        for i in range(550):
            self.controller.record_bypass_attempt(
                app_name="chrome.exe",
                target_ip="1.1.1.1",
                target_port=443,
                protocol="TCP",
            )

        logs = self.controller.get_audit_log(limit=100)
        self.assertEqual(len(logs), 100)
        self.assertEqual(len(self.controller._audit_log), 500)
        self.assertEqual(logs[0]["app_name"], "chrome.exe")
        self.assertEqual(logs[0]["action_taken"], "BLOCKED_BY_WFP_KERNEL")


if __name__ == "__main__":
    unittest.main()
