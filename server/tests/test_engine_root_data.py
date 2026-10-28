"""
Unit & Integration Tests for FocusDNS IANA Root Registry Database & Trust Anchors
=================================================================================
Validates:
  1. ICANN Root Zone Trust Anchors (KSK-2010, KSK-2017, KSK-2024)
  2. Global TLD profile lookups by apex and FQDN
  3. Category classification (generic, country-code, sponsored, infrastructure)
  4. Registry nameservers, whois servers, and DNSSEC signed status
  5. RootRegistryCatalog stats and filtering
"""

import unittest
from server.engine.root_data import (
    ICANN_ROOT_TRUST_ANCHORS,
    TLDProfile,
    RootRegistryCatalog,
    GLOBAL_TLD_DATABASE,
)


class TestRootData(unittest.TestCase):
    """Tests ICANN Trust Anchors and global TLD registry profiles."""

    def setUp(self):
        self.catalog = RootRegistryCatalog()

    def test_icann_trust_anchors_lifecycle(self):
        # 1. KSK-2010 should be present and marked REVOKED
        self.assertIn(19036, ICANN_ROOT_TRUST_ANCHORS)
        self.assertEqual(ICANN_ROOT_TRUST_ANCHORS[19036]["status"], "REVOKED")

        # 2. KSK-2017 should be VALID active anchor
        self.assertIn(20326, ICANN_ROOT_TRUST_ANCHORS)
        ksk_2017 = ICANN_ROOT_TRUST_ANCHORS[20326]
        self.assertEqual(ksk_2017["status"], "VALID")
        self.assertEqual(ksk_2017["algorithm"], 8)
        self.assertTrue(ksk_2017["digest"].startswith("E06D44B8"))

        # 3. KSK-2024 should be STANDBY anchor
        self.assertIn(38533, ICANN_ROOT_TRUST_ANCHORS)
        self.assertEqual(ICANN_ROOT_TRUST_ANCHORS[38533]["status"], "STANDBY")

        # Active lookup
        active = self.catalog.get_active_root_trust_anchors()
        self.assertEqual(len(active), 1)
        self.assertEqual(active[0]["key_tag"], 20326)

    def test_tld_lookups(self):
        # Direct TLD lookup
        com = self.catalog.get_tld("com")
        self.assertIsNotNone(com)
        self.assertEqual(com.category, "generic")
        self.assertTrue(com.dnssec_signed)
        self.assertIn("a.gtld-servers.net.", com.primary_ns)

        # FQDN lookup: extracts TLD
        dev = self.catalog.get_tld("api.subdomain.dev")
        self.assertIsNotNone(dev)
        self.assertEqual(dev.category, "generic")
        self.assertIn("ns1.google.com.", dev.primary_ns)

        # ccTLD lookup
        india = self.catalog.get_tld("in")
        self.assertIsNotNone(india)
        self.assertEqual(india.category, "country-code")
        self.assertEqual(india.whois_server, "whois.registry.in")

    def test_list_tlds_by_category(self):
        cctlds = self.catalog.list_tlds_by_category("country-code")
        self.assertGreaterEqual(len(cctlds), 10)
        cctld_names = [t.tld for t in cctlds]
        self.assertIn("uk", cctld_names)
        self.assertIn("de", cctld_names)
        self.assertIn("jp", cctld_names)

        infra = self.catalog.list_tlds_by_category("infrastructure")
        self.assertEqual(len(infra), 1)
        self.assertEqual(infra[0].tld, "arpa")

    def test_catalog_stats(self):
        st = self.catalog.get_stats()
        self.assertGreaterEqual(st["total_registered_tlds"], 20)
        self.assertGreaterEqual(st["generic_tlds"], 10)
        self.assertGreaterEqual(st["country_code_tlds"], 10)
        self.assertEqual(st["root_trust_anchors"], 3)


if __name__ == "__main__":
    unittest.main()
