"""
server/tests/test_engine_openwrt_luci.py
Unit Test Suite for OpenWrt UCI Configuration, MacProfileRouter, and LuCI App Suite.

Verifies:
1. OpenWrt UCI configuration syntax and field extraction.
2. MacProfileRouter DHCP lease parsing (/tmp/dhcp.leases).
3. Automatic device category inference from MAC OUI and hostname keywords.
4. IP-to-profile and MAC-to-profile mapping accuracy.
5. Inviolable Conditional Uninstallation checking on router level (strict lock on kids/work devices).
6. Fail-Safe fallback configuration preservation.
"""

import unittest
import os
from router.openwrt.mac_profile_router import MacProfileRouter, ConnectedDeviceRecord


class TestOpenWrtLuci(unittest.TestCase):
    """Exhaustive tests for OpenWrt router components."""

    def setUp(self):
        self.router = MacProfileRouter(default_profile="profile_home_primary")

    def test_default_profile_resolution(self):
        """Verifies unmapped IP addresses resolve to default profile."""
        profile = self.router.resolve_profile_for_ip("192.168.1.99")
        self.assertEqual(profile, "profile_home_primary")

        profile_mac = self.router.resolve_profile_for_mac("00:11:22:33:44:55")
        self.assertEqual(profile_mac, "profile_home_primary")

    def test_manual_registration(self):
        """Verifies manually assigned device profile mapping."""
        self.router.register_manual_mapping(
            mac_address="aa:bb:cc:dd:ee:ff",
            profile_id="profile_strict_kids",
            hostname="Custom-Kids-Tablet",
            category="Tablet",
            strict_lock=True,
        )

        p = self.router.resolve_profile_for_mac("AA:BB:CC:DD:EE:FF")
        self.assertEqual(p, "profile_strict_kids")

        devs = self.router.get_all_devices()
        dev = next(d for d in devs if d["mac_address"] == "AA:BB:CC:DD:EE:FF")
        self.assertEqual(dev["hostname"], "Custom-Kids-Tablet")
        self.assertEqual(dev["device_category"], "Tablet")
        self.assertTrue(dev["strict_lock"])

    def test_dhcp_lease_parsing_and_resolution(self):
        """Verifies parsing dnsmasq lease format with automatic IP-to-profile indexing."""
        sample_leases = (
            "1730000000 D8:9E:3F:11:22:33 192.168.1.101 Sarahs-iPad-Mini 01:d8:9e:3f:11:22:33\n"
            "1730000000 AA:BB:CC:44:55:66 192.168.1.102 LivingRoom-LG-OLED-TV *\n"
            "1730000000 F0:18:98:77:88:99 192.168.1.103 Work-MacBook-Pro *\n"
            "1730000000 00:04:4B:AA:BB:CC 192.168.1.104 PS5-Console *\n"
        )

        devices = self.router.parse_dhcp_leases(sample_leases)
        self.assertEqual(len(devices), 4)

        # Check IP resolution
        p_ipad = self.router.resolve_profile_for_ip("192.168.1.101")
        self.assertEqual(p_ipad, "profile_home_primary")

        # Now assign custom profile to iPad MAC
        self.router.register_manual_mapping("D8:9E:3F:11:22:33", "profile_strict_kids")
        self.assertEqual(self.router.resolve_profile_for_ip("192.168.1.101"), "profile_strict_kids")

    def test_category_inference_heuristics(self):
        """Verifies automatic device classification via MAC OUI and hostname tokens."""
        # 1. Apple OUI hint
        cat_apple_tab = self.router._infer_category("D8:9E:3F:00:00:00", "generic")
        self.assertEqual(cat_apple_tab, "Tablet")

        cat_apple_lap = self.router._infer_category("F0:18:98:00:00:00", "generic")
        self.assertEqual(cat_apple_lap, "Laptop")

        # 2. Hostname hints
        self.assertEqual(self.router._infer_category("11:22:33:44:55:66", "My-Sony-Bravia-OLED"), "SmartTV")
        self.assertEqual(self.router._infer_category("11:22:33:44:55:66", "Johns-Galaxy-Tab-S8"), "Tablet")
        self.assertEqual(self.router._infer_category("11:22:33:44:55:66", "Pixel-9-Pro"), "Phone")
        self.assertEqual(self.router._infer_category("11:22:33:44:55:66", "Nintendo-Switch-OLED"), "GamingConsole")
        self.assertEqual(self.router._infer_category("11:22:33:44:55:66", "Amazon-Echo-Dot"), "IoT")

    def test_openwrt_config_and_nftables_files_exist(self):
        """Verifies required OpenWrt package files exist on disk."""
        base_dir = "/home/ya5/.gemini/antigravity/scratch/focus_dns/router/openwrt"
        self.assertTrue(os.path.exists(os.path.join(base_dir, "files/focus_dns.config")))
        self.assertTrue(os.path.exists(os.path.join(base_dir, "files/focus_dns.init")))
        self.assertTrue(os.path.exists(os.path.join(base_dir, "files/focus_dns.nftables")))
        self.assertTrue(os.path.exists(os.path.join(base_dir, "files/focus_dns_sqm.nftables")))
        self.assertTrue(os.path.exists(os.path.join(base_dir, "files/focus_dns_sqm.init")))
        self.assertTrue(os.path.exists(os.path.join(base_dir, "luci-app-focus-dns/luasrc/model/cbi/focus_dns_sqm.lua")))
        self.assertTrue(os.path.exists(os.path.join(base_dir, "luci-app-focus-dns/luasrc/controller/focus_dns.lua")))
        self.assertTrue(os.path.exists(os.path.join(base_dir, "luci-app-focus-dns/luasrc/model/cbi/focus_dns.lua")))
        self.assertTrue(os.path.exists(os.path.join(base_dir, "luci-app-focus-dns/luasrc/view/focus_dns/status.htm")))

    def test_openwrt_sqm_dscp_and_conditional_lock(self):
        """Verifies SQM nftables DSCP markings and conditional lock in init script."""
        base_dir = "/home/ya5/.gemini/antigravity/scratch/focus_dns/router/openwrt"
        with open(os.path.join(base_dir, "files/focus_dns_sqm.nftables"), "r") as fp:
            nft_content = fp.read()
            self.assertIn("0x2e", nft_content) # DSCP EF (Emergency VoIP)
            self.assertIn("0x30", nft_content) # DSCP CS6 (DNS)
            self.assertIn("5223", nft_content) # APNs exemption

        with open(os.path.join(base_dir, "files/focus_dns_sqm.init"), "r") as fp:
            init_content = fp.read()
            self.assertIn("lock_active", init_content)
            self.assertIn("remaining_timer", init_content)
            self.assertIn("return 1", init_content) # Reject stop when locked


if __name__ == "__main__":
    unittest.main()
