"""
Unit tests for Router IPSet Engine, Netlink Driver, Benchmark, and Unified Orchestrator.

Verifies:
  1. Low-level Netlink struct formatting and binary attribute serialization.
  2. IPSet in-memory and kernel set operations (hash:ip, hash:net, hash:mac).
  3. Life Safety Exemption Guarantee: loopback, broadcast, and VoIP MACs are never blocked.
  4. Router Edge Benchmark Engine throughput and WAN failover stress analysis.
  5. RouterMasterOrchestrator full lifecycle and Conditional Uninstallation Law.
"""

import unittest
from router.daemon.router_ipset_netlink import RouterIPSetNetlink, NetlinkAttributeBuilder
from router.daemon.router_ipset_manager import RouterIpsetManager
from router.daemon.router_benchmark_engine import RouterBenchmarkEngine
from router.daemon.router_orchestrator import RouterMasterOrchestrator


class TestRouterIPSetNetlink(unittest.TestCase):
    def setUp(self):
        self.netlink = RouterIPSetNetlink(mock_mode=True)

    def tearDown(self):
        self.netlink.close()

    def test_netlink_attribute_packing(self):
        # Test u8 packing
        u8_bytes = NetlinkAttributeBuilder.pack_u8(1, 6)
        self.assertEqual(len(u8_bytes), 8)  # 4 header + 1 payload + 3 pad

        # Test u32 packing
        u32_bytes = NetlinkAttributeBuilder.pack_u32(2, 3600)
        self.assertEqual(len(u32_bytes), 8)  # 4 header + 4 payload

        # Test string packing
        str_bytes = NetlinkAttributeBuilder.pack_string(3, "focus_set")
        self.assertEqual(len(str_bytes) % 4, 0)

        # Test ipv4 packing
        ip_bytes = NetlinkAttributeBuilder.pack_ipv4("10.0.0.1")
        self.assertTrue(len(ip_bytes) > 0)
        self.assertEqual(len(ip_bytes) % 4, 0)

    def test_life_safety_exemption(self):
        self.assertTrue(self.netlink.is_exempt("127.0.0.1"))
        self.assertTrue(self.netlink.is_exempt("127.0.0.53"))
        self.assertTrue(self.netlink.is_exempt("255.255.255.255"))
        self.assertTrue(self.netlink.is_exempt("224.0.0.251"))  # mDNS
        self.assertFalse(self.netlink.is_exempt("198.51.100.1"))

        # Adding exempt IP must be rejected
        self.assertFalse(self.netlink.add_ip("127.0.0.1"))
        self.assertFalse(self.netlink.contains("127.0.0.1"))

    def test_add_and_delete_ip(self):
        self.assertTrue(self.netlink.add_ip("203.0.113.10"))
        self.assertTrue(self.netlink.contains("203.0.113.10"))
        self.assertEqual(self.netlink.size(), 1)

        # Batch addition
        self.assertEqual(self.netlink.batch_add_ips(["203.0.113.11", "203.0.113.12"]), 2)
        self.assertEqual(self.netlink.size(), 3)

        # Deletion
        self.assertTrue(self.netlink.delete_ip("203.0.113.10"))
        self.assertFalse(self.netlink.contains("203.0.113.10"))
        self.assertEqual(self.netlink.size(), 2)

        self.netlink.flush()
        self.assertEqual(self.netlink.size(), 0)


class TestRouterIpsetManager(unittest.TestCase):
    def setUp(self):
        self.mgr = RouterIpsetManager()

    def test_set_population_and_match(self):
        self.mgr.add_doh_ip("198.51.100.44")
        self.assertTrue(self.mgr.is_ip_blocked("198.51.100.44"))
        self.assertFalse(self.mgr.is_ip_blocked("198.51.100.45"))

        # Test subnets
        self.mgr.add_blocked_subnet("198.51.100.0/24")
        status = self.mgr.get_status()
        self.assertEqual(status["blocked_subnets_count"], 1)

    def test_life_safety_mac_exemption(self):
        # Emergency VoIP MAC is exempt
        self.assertTrue(self.mgr.is_mac_exempt("00:11:22:33:44:55"))
        self.assertFalse(self.mgr.is_mac_exempt("11:22:33:44:55:66"))

        # Add new exempt MAC
        self.mgr.add_exempt_mac("11:22:33:44:55:66")
        self.assertTrue(self.mgr.is_mac_exempt("11:22:33:44:55:66"))

    def test_restore_script_generation(self):
        self.mgr.add_doh_ip("198.51.100.50")
        script = self.mgr.generate_ipset_restore_script()
        self.assertIn("create focus_doh_v4 hash:ip", script)
        self.assertIn("add focus_doh_v4 198.51.100.50", script)
        self.assertIn("create focus_exempt_macs hash:mac", script)


class TestRouterBenchmarkEngine(unittest.TestCase):
    def test_benchmark_execution(self):
        engine = RouterBenchmarkEngine(mock_mode=True)
        report = engine.run_benchmark(total_queries=200, concurrency=2)
        self.assertEqual(report["status"], "completed")
        self.assertEqual(report["total_queries"], 200)
        self.assertTrue(report["throughput_qps"] > 0)
        self.assertTrue(report["latency_p50_us"] > 0)
        self.assertTrue(report["latency_p99_us"] >= report["latency_p50_us"])

    def test_wan_failover_stress(self):
        engine = RouterBenchmarkEngine(mock_mode=True)
        stress = engine.simulate_wan_failover_stress(total_queries=500, failover_at_query=250)
        self.assertTrue(stress["fail_safe_intact"])
        self.assertEqual(stress["packet_loss_percentage"], 0.0)
        self.assertTrue(stress["convergence_time_ms"] > 0)


class TestRouterMasterOrchestrator(unittest.TestCase):
    def setUp(self):
        self.orch = RouterMasterOrchestrator(router_id="test_rtr_gw_01")

    def tearDown(self):
        try:
            self.orch.set_focus_lock(False, 0)
            self.orch.stop()
        except Exception:
            pass

    def test_orchestrator_lifecycle(self):
        self.assertTrue(self.orch.start())
        status = self.orch.get_unified_status()
        self.assertEqual(status["router_id"], "test_rtr_gw_01")
        self.assertTrue(status["is_running"])
        self.assertTrue(status["can_uninstall"])
        self.assertIn("subsystems", status)
        self.assertIn("stub_daemon", status["subsystems"])
        self.assertIn("doq_engine", status["subsystems"])
        self.assertIn("dnssec_validator", status["subsystems"])
        self.assertIn("multiwan", status["subsystems"])
        self.assertIn("sqm", status["subsystems"])
        self.assertIn("ipset", status["subsystems"])

    def test_conditional_uninstallation_law(self):
        self.orch.start()

        # Engage focus
        self.orch.set_focus_lock(locked=True, remaining_seconds=3600)
        status = self.orch.get_unified_status()
        self.assertTrue(status["is_locked"])
        self.assertFalse(status["can_uninstall"])

        # Attempting stop must raise PermissionError
        with self.assertRaises(PermissionError) as ctx:
            self.orch.stop()
        self.assertIn("ERROR_ACCESS_DENIED", str(ctx.exception))

        # Unlock focus
        self.orch.set_focus_lock(locked=False, remaining_seconds=0)
        self.assertTrue(self.orch.can_uninstall())

        # Stopping now succeeds cleanly
        self.assertTrue(self.orch.stop())
        self.assertFalse(self.orch.is_running)


if __name__ == "__main__":
    unittest.main()
