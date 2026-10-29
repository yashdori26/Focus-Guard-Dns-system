"""
Unit tests for Synthetic DGA Feed Generator and Sinkhole Exporter.
Validates multi-family generation, safety filtering, Conditional Whitelisting Law,
and format exporters.
"""

import json
import unittest
from server.ai.dga_feed_generator import (
    DgaFeedGenerator,
    DgaFeedEntry,
    LIFE_SAFETY_DOMAINS
)


class TestDgaFeedGenerator(unittest.TestCase):

    def setUp(self):
        self.generator = DgaFeedGenerator()

    def test_generate_feed_for_family(self):
        """Generates synthetic domains for a single family with valid metadata."""
        entries = self.generator.generate_feed_for_family("conficker", count=15, base_seed=100)
        self.assertEqual(len(entries), 15)

        for e in entries:
            self.assertEqual(e.family, "Conficker")
            self.assertEqual(e.dga_type, "RANDOM_ALPHANUMERIC")
            self.assertTrue("." in e.domain)
            self.assertGreater(e.entropy, 0.0)
            self.assertGreaterEqual(e.vowel_ratio, 0.0)

    def test_generate_multi_family_feed(self):
        """Generates multi-family threat feed across selected families."""
        families = ["conficker", "mirai", "suppobox", "bamital"]
        entries = self.generator.generate_multi_family_feed(
            families=families,
            count_per_family=10,
            base_seed=555
        )
        self.assertEqual(len(entries), 40)

        found_families = {e.family for e in entries}
        self.assertIn("Conficker", found_families)
        self.assertIn("Mirai", found_families)
        self.assertIn("Suppobox", found_families)
        self.assertIn("Bamital", found_families)

    def test_life_safety_exemption_never_included(self):
        """Verifies life safety domains are never exported into feeds."""
        for exempt in LIFE_SAFETY_DOMAINS:
            self.assertTrue(self.generator.is_life_safety_exempt(exempt))
            self.assertTrue(self.generator.is_life_safety_exempt(f"sub.{exempt}"))

    def test_conditional_whitelisting_law_when_idle(self):
        """Whitelisting works when idle and filters domain out of generated feed."""
        self.assertFalse(self.generator.is_locked)

        # Generate 1 domain first
        single = self.generator.generate_feed_for_family("conficker", count=1, base_seed=777)
        target_domain = single[0].domain

        # Add target_domain to whitelist exception
        success = self.generator.add_whitelist_exception(target_domain)
        self.assertTrue(success)
        self.assertIn(target_domain, self.generator.get_whitelist_exceptions())

        # Re-generating with same seed must omit the whitelisted domain
        re_entries = self.generator.generate_feed_for_family("conficker", count=1, base_seed=777)
        domains = [e.domain for e in re_entries]
        self.assertNotIn(target_domain, domains)

        # Removal succeeds when idle
        removed = self.generator.remove_whitelist_exception(target_domain)
        self.assertTrue(removed)
        self.assertNotIn(target_domain, self.generator.get_whitelist_exceptions())

    def test_conditional_whitelisting_law_denial_when_locked(self):
        """Whitelisting must raise PermissionError ERROR_ACCESS_DENIED (5) when locked."""
        self.generator.set_lock_state(is_locked=True, countdown_seconds=0)
        self.assertTrue(self.generator.is_locked)

        with self.assertRaises(PermissionError) as ctx:
            self.generator.add_whitelist_exception("safe-sample.com")
        self.assertIn("ERROR_ACCESS_DENIED (5)", str(ctx.exception))

        with self.assertRaises(PermissionError) as ctx:
            self.generator.remove_whitelist_exception("safe-sample.com")
        self.assertIn("ERROR_ACCESS_DENIED (5)", str(ctx.exception))

    def test_conditional_whitelisting_law_denial_when_timer_active(self):
        """Whitelisting must raise PermissionError if countdown_seconds > 0 even if is_locked is False."""
        self.generator.set_lock_state(is_locked=False, countdown_seconds=600)
        self.assertTrue(self.generator.is_locked)

        with self.assertRaises(PermissionError) as ctx:
            self.generator.add_whitelist_exception("test-domain.org")
        self.assertIn("ERROR_ACCESS_DENIED (5)", str(ctx.exception))

    def test_export_hosts_format(self):
        """Exports entries into standard hosts file format."""
        entries = self.generator.generate_feed_for_family("conficker", count=3, base_seed=12)
        hosts_output = DgaFeedGenerator.export_hosts_format(entries, sinkhole_ip="0.0.0.0")

        self.assertIn("FocusDNS AI Synthetic DGA Blocklist", hosts_output)
        for e in entries:
            self.assertIn(f"0.0.0.0 {e.domain}", hosts_output)

    def test_export_bind_rpz(self):
        """Exports entries into BIND RPZ format."""
        entries = self.generator.generate_feed_for_family("conficker", count=2, base_seed=45)
        rpz_output = DgaFeedGenerator.export_bind_rpz(entries, zone_origin="rpz.focusguard.internal")

        self.assertIn("Response Policy Zone (RPZ)", rpz_output)
        for e in entries:
            self.assertIn(f"{e.domain}.rpz.focusguard.internal. CNAME .", rpz_output)

    def test_export_unbound_format(self):
        """Exports entries into Unbound format."""
        entries = self.generator.generate_feed_for_family("conficker", count=2, base_seed=88)
        unbound_output = DgaFeedGenerator.export_unbound_format(entries, action="always_refuse")

        self.assertIn("server:", unbound_output)
        for e in entries:
            self.assertIn(f'local-zone: "{e.domain}" always_refuse', unbound_output)

    def test_export_dnsmasq_format(self):
        """Exports entries into Dnsmasq format."""
        entries = self.generator.generate_feed_for_family("conficker", count=2, base_seed=99)
        dnsmasq_output = DgaFeedGenerator.export_dnsmasq_format(entries, sinkhole_ip="0.0.0.0")

        for e in entries:
            self.assertIn(f"address=/{e.domain}/0.0.0.0", dnsmasq_output)

    def test_export_json_feed(self):
        """Exports entries into valid JSON telemetry payload."""
        entries = self.generator.generate_feed_for_family("conficker", count=5, base_seed=33)
        json_output = DgaFeedGenerator.export_json_feed(entries, metadata={"author": "FocusGuard AI"})

        data = json.loads(json_output)
        self.assertEqual(data["version"], "1.0.0")
        self.assertEqual(data["total_entries"], 5)
        self.assertEqual(data["metadata"]["author"], "FocusGuard AI")
        self.assertEqual(len(data["entries"]), 5)
        self.assertEqual(data["entries"][0]["family"], "Conficker")


if __name__ == "__main__":
    unittest.main()
