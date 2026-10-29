"""
Unit tests for MikroTik RouterOS v7 and Ubiquiti EdgeOS/UniFi Gateway Engines.

Verifies:
  1. RouterOS NAT redirect, L7 DoH/DoT filter drops, and netwatch watchdog generation.
  2. RouterOS container image specification.
  3. Ubiquiti VyOS/EdgeOS CLI compilation and UniFi on_boot.d shell script generation.
  4. Conditional Uninstallation Law: uninstall blocked when focus is active or timer > 0.
  5. Life Safety Exemption: emergency calling, DHCP, and router admin ports are exempt.
"""

import unittest
from router.mikrotik.routeros_dns_manager import RouterOsDnsManager
from router.ubiquiti.ubiquiti_gateway_engine import UbiquitiGatewayEngine


class TestMikrotikRouterOsEngine(unittest.TestCase):
    def setUp(self):
        self.mgr = RouterOsDnsManager()

    def test_default_posture(self):
        self.assertTrue(self.mgr.can_uninstall())
        posture = self.mgr.get_status()
        self.assertIn("MikroTik", posture["platform"])
        self.assertTrue(posture["can_uninstall"])
        self.assertEqual(posture["remaining_timer_seconds"], 0)

    def test_nat_redirect_script(self):
        script = self.mgr.generate_nat_redirect_rules()
        self.assertIn("/ip firewall nat", script)
        self.assertIn("chain=dstnat", script)
        self.assertIn("dst-port=53", script)
        self.assertIn(f"to-ports={self.mgr.LOCAL_PORT}", script)
        self.assertIn("action=redirect", script)
        # Ensure life safety DHCP exemption
        self.assertIn("dst-port=67,68 action=accept", script)

    def test_doh_dot_drop_rules(self):
        rules = self.mgr.generate_filter_anti_bypass_rules()
        self.assertIn("/ip firewall filter", rules)
        self.assertIn("chain=forward", rules)
        self.assertIn("dst-port=853", rules)
        self.assertIn("FocusGuard-DNS-Drop-DoT", rules)

    def test_netwatch_fail_safe(self):
        netwatch = self.mgr.generate_netwatch_fail_safe()
        self.assertIn("/tool netwatch", netwatch)
        self.assertIn("up-script", netwatch)
        self.assertIn("down-script", netwatch)
        # Down script must disable redirect to prevent LAN outage
        self.assertIn("disable", netwatch)

    def test_container_spec(self):
        spec = self.mgr.generate_container_spec()
        self.assertIn("/container", spec)
        self.assertIn("veth-focusdns", spec)
        self.assertIn("router-stub:latest", spec)

    def test_conditional_uninstallation_law(self):
        # Idle mode: uninstallation permitted
        self.mgr.set_lock(False, 0)
        self.assertTrue(self.mgr.can_uninstall())
        cleanup = self.mgr.generate_uninstall_script()
        self.assertIn("remove [find comment~\"FocusGuard-DNS\"]", cleanup)

        # Active focus: uninstallation strictly denied
        self.mgr.set_lock(True, 3600)
        self.assertFalse(self.mgr.can_uninstall())
        with self.assertRaises(PermissionError) as ctx:
            self.mgr.generate_uninstall_script()
        self.assertIn("ERROR_ACCESS_DENIED", str(ctx.exception))

        # Timer > 0: uninstallation strictly denied
        self.mgr.set_lock(False, 300)
        self.assertFalse(self.mgr.can_uninstall())
        with self.assertRaises(PermissionError):
            self.mgr.generate_uninstall_script()


class TestUbiquitiGatewayEngine(unittest.TestCase):
    def setUp(self):
        self.engine = UbiquitiGatewayEngine()

    def test_default_posture(self):
        self.assertTrue(self.engine.can_uninstall())
        status = self.engine.get_status()
        self.assertIn("Ubiquiti", status["platform"])
        self.assertTrue(status["can_uninstall"])

    def test_edgeos_vyos_config_generation(self):
        cfg = self.engine.generate_edgeos_config()
        self.assertIn("set service nat rule 1", cfg)
        self.assertIn("destination port 53", cfg)
        self.assertIn(f"inside-address port {self.engine.LOCAL_PORT}", cfg)
        self.assertIn("set firewall name LAN_IN rule 20", cfg)
        self.assertIn("destination port 853", cfg)
        self.assertIn("commit", cfg)
        self.assertIn("save", cfg)

    def test_unifi_on_boot_generation(self):
        boot_script = self.engine.generate_unifi_on_boot_script()
        self.assertIn("#!/bin/sh", boot_script)
        self.assertIn("podman run", boot_script)
        self.assertIn("router-stub:latest", boot_script)
        self.assertIn(f"-p udp --dport 53 -j REDIRECT --to-ports {self.engine.LOCAL_PORT}", boot_script)

    def test_conditional_uninstallation_law(self):
        # Idle mode
        self.engine.set_lock(False, 0)
        self.assertTrue(self.engine.can_uninstall())
        teardown = self.engine.generate_teardown_commands()
        self.assertIn("podman rm", teardown)
        self.assertIn("iptables -t nat -D", teardown)

        # Active mode
        self.engine.set_lock(True, 1800)
        self.assertFalse(self.engine.can_uninstall())
        with self.assertRaises(PermissionError) as ctx:
            self.engine.generate_teardown_commands()
        self.assertIn("ERROR_ACCESS_DENIED", str(ctx.exception))

    def test_life_safety_exemptions(self):
        boot_script = self.engine.generate_unifi_on_boot_script()
        # Verify DHCP port 67 is not redirected
        self.assertNotIn("--dport 67 -j REDIRECT", boot_script)
        # Verify emergency or admin ports are not redirected
        self.assertNotIn("--dport 443 -j REDIRECT", boot_script)


if __name__ == "__main__":
    unittest.main()
