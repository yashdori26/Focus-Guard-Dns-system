"""
Unit tests for Router Multi-WAN Failover Manager & pfSense PF Sync Daemon.
"""

import unittest
from router.pfsense.pf_sync_daemon import PfSyncDaemon
from router.daemon.router_multiwan_manager import RouterMultiWanManager


class TestMultiWanAndPfSync(unittest.TestCase):

    def setUp(self):
        self.pf_daemon = PfSyncDaemon(anchor_name="focus_dns")
        self.multiwan = RouterMultiWanManager(failure_threshold=3)

    def test_pf_sync_table_crud(self):
        self.pf_daemon.start()
        self.assertTrue(self.pf_daemon.is_active)

        # Check default IPs
        entries = self.pf_daemon.get_table_entries()
        self.assertIn("1.1.1.1", entries)
        self.assertIn("8.8.8.8", entries)

        # Add custom rogue IP
        self.assertTrue(self.pf_daemon.add_rogue_ip("45.33.32.156"))
        self.assertIn("45.33.32.156", self.pf_daemon.get_table_entries())

        # Remove custom rogue IP
        self.assertTrue(self.pf_daemon.remove_rogue_ip("45.33.32.156"))
        self.assertNotIn("45.33.32.156", self.pf_daemon.get_table_entries())

    def test_pf_log_parser(self):
        log_line = "rule 42/(match) block on igb0: 192.168.1.120.51234 > 1.1.1.1.443: tcp"
        record = self.pf_daemon.parse_filter_log_line(log_line)

        self.assertIsNotNone(record)
        self.assertEqual(record["action"], "BLOCK")
        self.assertEqual(record["src_ip"], "192.168.1.120")
        self.assertEqual(record["dst_ip"], "1.1.1.1")
        self.assertEqual(record["dst_port"], 443)

        status = self.pf_daemon.get_status()
        self.assertEqual(status["blocked_packets_count"], 1)

    def test_pf_daemon_conditional_uninstallation(self):
        self.pf_daemon.start()
        self.assertTrue(self.pf_daemon.can_uninstall())

        # When locked, stopping raises PermissionError
        self.pf_daemon.set_lock(locked=True, remaining_seconds=1200)
        self.assertFalse(self.pf_daemon.can_uninstall())
        with self.assertRaises(PermissionError):
            self.pf_daemon.stop()

        # Unlock and verify stop succeeds
        self.pf_daemon.set_lock(locked=False, remaining_seconds=0)
        self.assertTrue(self.pf_daemon.can_uninstall())
        self.assertTrue(self.pf_daemon.stop())
        self.assertFalse(self.pf_daemon.is_active)

    def test_multiwan_failover_and_fallback(self):
        status = self.multiwan.get_status()
        self.assertEqual(status["active_wan"], "wan1")
        self.assertFalse(status["is_lan_fallback_mode"])

        # 1. Fail wan1 (3 consecutive failures)
        for _ in range(3):
            self.multiwan.report_probe_result("wan1", success=False)

        status_after_wan1_fail = self.multiwan.get_status()
        # Failover to backup WAN2
        self.assertEqual(status_after_wan1_fail["active_wan"], "wan2")
        self.assertFalse(status_after_wan1_fail["is_lan_fallback_mode"])

        # 2. Fail wan2 as well (Complete WAN Outage)
        for _ in range(3):
            self.multiwan.report_probe_result("wan2", success=False)

        status_after_both_fail = self.multiwan.get_status()
        # Fail-Safe Guarantee: Engage LAN fallback mode
        self.assertTrue(status_after_both_fail["is_lan_fallback_mode"])

        # 3. Restore wan1
        self.multiwan.report_probe_result("wan1", success=True, latency_ms=14.2)
        status_restored = self.multiwan.get_status()
        self.assertEqual(status_restored["active_wan"], "wan1")
        self.assertFalse(status_restored["is_lan_fallback_mode"])


if __name__ == "__main__":
    unittest.main()
