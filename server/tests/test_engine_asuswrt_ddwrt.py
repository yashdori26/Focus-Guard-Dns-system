"""
Unit tests for Asuswrt-Merlin & DD-WRT Router Firmware Engines.
"""

import unittest
from router.asuswrt.merlin_config_generator import MerlinConfigGenerator
from router.asuswrt.jffs_scripts import AsuswrtJffsScripts
from router.ddwrt.ddwrt_firewall_manager import DdWrtFirewallManager


class TestAsuswrtDdWrtEngine(unittest.TestCase):

    def test_merlin_dnsmasq_postconf_generation(self):
        devices = [
            {"mac": "11:22:33:44:55:66", "profile": "profile_strict_kids"},
            {"mac": "AA:BB:CC:DD:EE:FF", "profile": "profile_ad_free_iot"}
        ]
        postconf = MerlinConfigGenerator.generate_dnsmasq_postconf("profile_home_primary", devices)

        self.assertIn("#!/bin/sh", postconf)
        self.assertIn("pc_replace", postconf)
        self.assertIn("server=127.0.0.1#5353", postconf)
        self.assertIn("dhcp-mac=set:tag_strict_kids,11:22:33:44:55:66", postconf)
        self.assertIn("dhcp-mac=set:tag_ad_free_iot,AA:BB:CC:DD:EE:FF", postconf)

    def test_merlin_nat_start_iptables_generation(self):
        nat_start = MerlinConfigGenerator.generate_nat_start()

        self.assertIn("FOCUS_DNS_NAT", nat_start)
        self.assertIn("REDIRECT --to-ports 5353", nat_start)
        # Port 853 drop
        self.assertIn("--dport 853 -j REJECT", nat_start)
        # Cloudflare DoH drop
        self.assertIn("-d 1.1.1.1 -p tcp --dport 443 -j REJECT", nat_start)
        # DHCP exemption
        self.assertIn("--dport 67:68 -j RETURN", nat_start)

    def test_asuswrt_jffs_scripts_conditional_stop(self):
        # 1. Idle mode stop script permits clean teardown
        stop_idle = AsuswrtJffsScripts.generate_services_stop(can_uninstall=True, remaining_seconds=0)
        self.assertIn("Normal mode verified", stop_idle)
        self.assertIn("iptables -t nat -D PREROUTING -j FOCUS_DNS_NAT", stop_idle)
        self.assertIn("exit 0", stop_idle)

        # 2. Locked mode stop script rejects deactivation
        stop_locked = AsuswrtJffsScripts.generate_services_stop(can_uninstall=False, remaining_seconds=900)
        self.assertIn("ACCESS DENIED", stop_locked)
        self.assertIn("exit 1", stop_locked)

    def test_asuswrt_watchdog_script(self):
        watchdog = AsuswrtJffsScripts.generate_watchdog(check_interval=15)
        self.assertIn("CHECK_INTERVAL=15", watchdog)
        self.assertIn("focus_dns_daemon", watchdog)
        self.assertIn("FAIL-SAFE TRIGGERED", watchdog)

    def test_ddwrt_firewall_manager(self):
        mgr = DdWrtFirewallManager(profile_id="profile_family")
        self.assertTrue(mgr.can_uninstall())

        fw = mgr.generate_rc_firewall()
        self.assertIn("REDIRECT --to-ports 5353", fw)
        self.assertIn("--dport 67:68 -j ACCEPT", fw) # DHCP exemption
        self.assertIn("--dport 853 -j DROP", fw) # DoT drop

        commit_cmds = mgr.generate_nvram_commit_commands()
        self.assertIn("nvram set rc_firewall", commit_cmds)
        self.assertIn("nvram commit", commit_cmds)

        # In idle mode, uninstallation succeeds
        uninst_cmds = mgr.generate_uninstall_commands()
        self.assertIn("nvram unset rc_firewall", uninst_cmds)

        # In focus mode, uninstallation throws PermissionError
        mgr.set_lock(locked=True, remaining_seconds=600)
        self.assertFalse(mgr.can_uninstall())
        with self.assertRaises(PermissionError):
            mgr.generate_uninstall_commands()


if __name__ == "__main__":
    unittest.main()
