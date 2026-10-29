"""
Unit tests for Router SQM Traffic Shaper & macOS BSD PF Manager.
"""

import unittest
from router.daemon.router_sqm_controller import RouterSqmController
from server.engine.macos_pf_manager import MacOsPfManager


class TestRouterSqmAndMacOsPf(unittest.TestCase):

    def setUp(self):
        self.sqm = RouterSqmController(download_mbps=150, upload_mbps=30)
        self.macos_pf = MacOsPfManager()

    def test_sqm_traffic_shaping_rules(self):
        ingress = self.sqm.generate_tc_cake_ingress_rules()
        self.assertIn("cake bandwidth 150mbit", ingress)
        # Life-safety DSCP check: VoIP/Emergency (EF)
        self.assertIn("--set-dscp-class EF", ingress)
        # DNS priority check: CS6
        self.assertIn("--set-dscp-class CS6", ingress)

        # In focus mode, distraction throttling is active
        self.sqm.set_focus_mode(True)
        ingress_focus = self.sqm.generate_tc_cake_ingress_rules()
        self.assertIn("--set-dscp-class CS1", ingress_focus)

        egress = self.sqm.generate_tc_cake_egress_rules()
        self.assertIn("cake bandwidth 30mbit", egress)

    def test_macos_pf_anchor_rules(self):
        rules = self.macos_pf.generate_anchor_rules()

        # Life safety exemptions: DHCP & APNs
        self.assertIn("port 67:68", rules)
        self.assertIn("port 5223", rules)

        # Drops for DoT and DoH
        self.assertIn("port 853", rules)
        self.assertIn("<focus_rogue_doh>", rules)
        self.assertIn("1.1.1.1", rules)

        activation_script = self.macos_pf.generate_anchor_activation_script()
        self.assertIn("pfctl -a com.focusguard", activation_script)

    def test_macos_pf_conditional_uninstallation(self):
        self.assertTrue(self.macos_pf.can_uninstall())

        # Clean teardown in idle mode
        teardown = self.macos_pf.generate_anchor_teardown_script()
        self.assertIn("pfctl -a com.focusguard -F all", teardown)

        # In locked mode, teardown raises PermissionError
        self.macos_pf.set_focus_lock(locked=True, remaining_seconds=1800)
        self.assertFalse(self.macos_pf.can_uninstall())
        with self.assertRaises(PermissionError):
            self.macos_pf.generate_anchor_teardown_script()


if __name__ == "__main__":
    unittest.main()
