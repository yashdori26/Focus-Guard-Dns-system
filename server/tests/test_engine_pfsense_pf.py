"""
server/tests/test_engine_pfsense_pf.py
Unit Test Suite for FreeBSD Packet Filter (PF) Engine, pfSense, and OPNSense Suite.

Verifies:
1. BSD Packet Filter (pf.conf) rule string compilation and syntax.
2. Multi-VLAN and multi-interface port 53 redirection to local daemon (127.0.0.1:5353).
3. Rogue public DoH resolver (1.1.1.1, 8.8.8.8, 9.9.9.9) drop rule generation.
4. Rogue port 853 DoT drop rule generation with daemon user egress exemption.
5. Inviolable loopback (lo0) exemption rule.
6. Package specification and include file presence.
"""

import unittest
import os
from router.pfsense.pf_rules_generator import (
    PfRulesGenerator,
    PfProtocol,
    PfAction,
    PfRule,
)


class TestPfSensePf(unittest.TestCase):
    """Exhaustive tests for BSD Packet Filter generator and pfSense/OPNSense integration."""

    def setUp(self):
        self.generator = PfRulesGenerator(
            lan_interfaces=["em0", "igb0", "vlan10"],
            local_proxy_port=5353,
            focus_dot_port=853,
            block_rogue_doh=True,
            block_rogue_dot=True,
        )

    def test_pf_rule_string_rendering(self):
        """Verifies standard pf.conf rule syntax formatting."""
        rule = PfRule(
            action=PfAction.BLOCK,
            interfaces=["em0"],
            protocol=PfProtocol.TCP,
            src="any",
            dst="1.1.1.1",
            dst_port="443",
            quick=True,
            direction="out",
            label="Block Cloudflare DoH",
        )
        s = rule.to_pf_string()
        self.assertIn("block drop out quick", s)
        self.assertIn("on em0", s)
        self.assertIn("proto tcp", s)
        self.assertIn("to 1.1.1.1 port 443", s)
        self.assertIn('label "Block Cloudflare DoH"', s)

    def test_rdr_rule_multi_interface(self):
        """Verifies NAT redirection rule across multiple LAN interfaces."""
        rule_rdr = PfRule(
            action=PfAction.RDR,
            interfaces=["em0", "igb0"],
            protocol=PfProtocol.BOTH,
            src="any",
            dst="! 127.0.0.1",
            dst_port="53",
            redirect_ip="127.0.0.1",
            redirect_port="5353",
            label="FocusDNS_DNS_Redirect",
        )
        s = rule_rdr.to_pf_string()
        self.assertTrue(s.startswith("rdr pass on {em0 igb0}"))
        self.assertIn("proto { udp tcp }", s)
        self.assertIn("port 53 -> 127.0.0.1 port 5353", s)
        self.assertIn('tag "FocusDNS_DNS_Redirect"', s)

    def test_generator_compilation_and_exemptions(self):
        """
        Life Safety & Local Network Exemption Verification:
        Loopback lo0 must be passed quick without state.
        """
        rules = self.generator.compile_rules()
        self.assertGreaterEqual(len(rules), 4)

        loopback_rule = next((r for r in rules if r.interfaces == ["lo0"] and r.action == PfAction.PASS), None)
        self.assertIsNotNone(loopback_rule)
        self.assertEqual(loopback_rule.direction, "")
        self.assertTrue(loopback_rule.quick)

    def test_doh_and_dot_drop_rules(self):
        """Verifies generation of drop rules for rogue public DoH and unauthorized DoT."""
        rules = self.generator.compile_rules()

        # Check DoH drop rule
        doh_rule = next((r for r in rules if r.dst_port == "443" and r.action == PfAction.BLOCK), None)
        self.assertIsNotNone(doh_rule)
        self.assertEqual(doh_rule.protocol, PfProtocol.TCP)
        self.assertIn("1.1.1.1", doh_rule.dst)
        self.assertIn("8.8.8.8", doh_rule.dst)

        # Check DoT drop rule
        dot_drop = next((r for r in rules if r.dst_port == "853" and r.action == PfAction.BLOCK), None)
        self.assertIsNotNone(dot_drop)

        # Check FocusDNS daemon user egress exemption
        daemon_rule = next((r for r in rules if r.user == "_focusdns" and r.action == PfAction.PASS), None)
        self.assertIsNotNone(daemon_rule)
        self.assertEqual(daemon_rule.dst_port, "853")

    def test_pf_anchor_output_generation(self):
        """Verifies complete pf.conf anchor output generation."""
        anchor_text = self.generator.generate_pf_anchor_config()
        self.assertIn("# FocusDNS Whole-Home Firewall Anchor Configuration", anchor_text)
        self.assertIn("rdr pass on", anchor_text)
        self.assertIn("tag \"FocusDNS_DNS_Redirect\"", anchor_text)
        self.assertIn("focus_lan_ifs", anchor_text)

    def test_pfsense_and_opnsense_package_files_exist(self):
        """Verifies pfSense and OPNSense integration files exist."""
        pfsense_dir = "/home/ya5/.gemini/antigravity/scratch/focus_dns/router/pfsense"
        opnsense_dir = "/home/ya5/.gemini/antigravity/scratch/focus_dns/router/opnsense"

        self.assertTrue(os.path.exists(os.path.join(pfsense_dir, "pf_rules_generator.py")))
        self.assertTrue(os.path.exists(os.path.join(pfsense_dir, "focus_dns.xml")))
        self.assertTrue(os.path.exists(os.path.join(pfsense_dir, "focus_dns.inc")))
        self.assertTrue(os.path.exists(os.path.join(opnsense_dir, "FocusDnsController.php")))


if __name__ == "__main__":
    unittest.main()
