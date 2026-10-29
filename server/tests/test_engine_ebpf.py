"""
Unit tests for Linux eBPF Kernel Firewall Loader & XDP Router.
"""

import unittest
from router.linux_ebpf.focus_dns_ebpf_loader import FocusDnsEbpfLoader, EbpfKernelMapMock
from router.linux_ebpf.ebpf_xdp_router import EbpfXdpRouter


class TestEbpfEngine(unittest.TestCase):

    def setUp(self):
        self.loader = FocusDnsEbpfLoader()
        self.router = EbpfXdpRouter(interface="br-lan", loader=self.loader)

    def test_bpf_map_mock_crud(self):
        map_mock = EbpfKernelMapMock("test_map", 2)
        map_mock.update(100, 1)
        map_mock.update(200, 2)
        self.assertEqual(map_mock.lookup(100), 1)
        self.assertEqual(map_mock.lookup(200), 2)
        self.assertIsNone(map_mock.lookup(300))

        # Test capacity overflow
        with self.assertRaises(OverflowError):
            map_mock.update(300, 3)

        self.assertTrue(map_mock.delete(100))
        self.assertIsNone(map_mock.lookup(100))
        map_mock.clear()
        self.assertEqual(len(map_mock.entries), 0)

    def test_default_rogue_ips_preloaded(self):
        # 1.1.1.1 and 8.8.8.8 should be preloaded into rogue_doh_map
        u32_cf = self.loader._ip_to_u32("1.1.1.1")
        u32_gg = self.loader._ip_to_u32("8.8.8.8")
        self.assertEqual(self.loader.rogue_doh_map.lookup(u32_cf), 1)
        self.assertEqual(self.loader.rogue_doh_map.lookup(u32_gg), 1)

    def test_packet_hook_life_safety_exemptions(self):
        # 1. Loopback traffic must pass unimpeded
        verdict, target = self.loader.simulate_packet_hook("127.0.0.1", "127.0.0.1", 53)
        self.assertEqual(verdict, "ALLOW")
        self.assertIsNone(target)

        # 2. DHCP traffic (ports 67 and 68) must pass unimpeded
        verdict_dhcp1, _ = self.loader.simulate_packet_hook("192.168.1.50", "192.168.1.1", 67)
        verdict_dhcp2, _ = self.loader.simulate_packet_hook("192.168.1.1", "192.168.1.50", 68)
        self.assertEqual(verdict_dhcp1, "ALLOW")
        self.assertEqual(verdict_dhcp2, "ALLOW")

    def test_packet_hook_dns_redirection(self):
        # Standard outbound DNS query (Port 53)
        verdict, target = self.loader.simulate_packet_hook("192.168.1.50", "8.8.8.8", 53)
        self.assertEqual(verdict, "REDIRECT")
        self.assertEqual(target, ("127.0.0.1", 5353))

    def test_packet_hook_rogue_dot_drop(self):
        # Rogue DNS-over-TLS (Port 853)
        verdict, target = self.loader.simulate_packet_hook("192.168.1.50", "1.1.1.1", 853)
        self.assertEqual(verdict, "DROP")
        self.assertIsNone(target)

    def test_packet_hook_rogue_doh_drop(self):
        # App attempting direct HTTPS bypass to Cloudflare DoH (1.1.1.1:443)
        verdict, target = self.loader.simulate_packet_hook("192.168.1.50", "1.1.1.1", 443)
        self.assertEqual(verdict, "DROP")

        # Normal HTTPS to Google Search (142.250.190.46:443) must be allowed
        verdict_normal, _ = self.loader.simulate_packet_hook("192.168.1.50", "142.250.190.46", 443)
        self.assertEqual(verdict_normal, "ALLOW")

    def test_conditional_uninstallation_law(self):
        self.loader.load_ebpf_program()
        self.assertTrue(self.loader.is_loaded)

        # In normal mode, unloading succeeds
        self.assertTrue(self.loader.unload_ebpf_program())
        self.assertFalse(self.loader.is_loaded)

        # In focus mode, unloading raises PermissionError
        self.loader.load_ebpf_program()
        self.loader.set_protection_policy(active=True, timer_seconds=1200)
        self.assertFalse(self.loader.can_uninstall())

        with self.assertRaises(PermissionError):
            self.loader.unload_ebpf_program()

        # Unlock and verify clean unload
        self.loader.set_protection_policy(active=False, timer_seconds=0)
        self.assertTrue(self.loader.can_uninstall())
        self.assertTrue(self.loader.unload_ebpf_program())

    def test_xdp_router_dhcp_sync_and_fail_safe(self):
        self.router.start()
        self.assertTrue(self.router.is_active)

        # Sync DHCP lease
        synced = self.router.sync_dhcp_lease("AA:BB:CC:DD:EE:FF", "192.168.1.110", "Kids-Tablet", "profile_strict_kids")
        self.assertTrue(synced)

        ip_u32 = self.loader._ip_to_u32("192.168.1.110")
        self.assertEqual(self.loader.client_profile_map.lookup(ip_u32), 0)

        # Fail-Safe check
        self.assertFalse(self.router.is_fallback_mode)
        self.router.trigger_fail_safe_check(upstream_reachable=False)
        self.assertTrue(self.router.is_fallback_mode)
        self.router.trigger_fail_safe_check(upstream_reachable=True)
        self.assertFalse(self.router.is_fallback_mode)


if __name__ == "__main__":
    unittest.main()
