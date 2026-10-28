"""
Unit & Integration Tests for FocusDNS RFC 8806 Hyperlocal Root Zone Subsystem
=============================================================================
Validates:
  1. IANA Root server hint seeding (13 root servers A-M with IPv4/IPv6 glue)
  2. Authoritative root apex queries (SOA, NS, NODATA)
  3. Top-Level Domain (TLD) delegation referral responses (NS and glue records)
  4. Authoritative negative responses (NXDOMAIN) for non-existent TLDs
  5. LocalRootEngine integration and query telemetry
"""

import unittest
from dnslib import QTYPE
from server.engine.local_root import (
    ROOT_SERVER_HINTS,
    LocalRootZone,
    LocalRootEngine,
    TLDDelegation,
)


class TestLocalRootZone(unittest.TestCase):
    """Tests RFC 8806 in-memory root zone answers, referrals, and delegations."""

    def setUp(self):
        self.zone = LocalRootZone()

    def test_root_hints_presence(self):
        # All 13 root server letters A-M must be present
        self.assertEqual(len(ROOT_SERVER_HINTS), 13)
        self.assertIn("a.root-servers.net", ROOT_SERVER_HINTS)
        self.assertIn("m.root-servers.net", ROOT_SERVER_HINTS)
        self.assertEqual(ROOT_SERVER_HINTS["a.root-servers.net"]["ipv4"], "198.41.0.4")

    def test_root_apex_ns_query(self):
        res = self.zone.query(".", "NS")
        self.assertEqual(res["type"], "APEX_ANSWER")
        self.assertEqual(res["rcode"], "NOERROR")
        # 13 NS records in answers
        self.assertEqual(len(res["answers"]), 13)
        # Additional section must contain IPv4 and IPv6 glue records
        self.assertGreaterEqual(len(res["additional"]), 26)

    def test_root_apex_soa_query(self):
        res = self.zone.query(".", "SOA")
        self.assertEqual(res["type"], "APEX_ANSWER")
        self.assertEqual(len(res["answers"]), 1)
        soa_rr = res["answers"][0]
        self.assertEqual(str(soa_rr.rname), ".")
        self.assertEqual(soa_rr.rtype, QTYPE.SOA)

    def test_root_apex_nodata_query(self):
        # Root apex has no MX records
        res = self.zone.query(".", "MX")
        self.assertEqual(res["type"], "APEX_ANSWER")
        self.assertEqual(res["rcode"], "NOERROR")
        self.assertEqual(len(res["answers"]), 0)
        # Authority section must contain SOA
        self.assertEqual(len(res["authority"]), 1)
        self.assertEqual(res["authority"][0].rtype, QTYPE.SOA)

    def test_tld_delegation_referral(self):
        # Querying for something under 'com' returns delegation referral
        res = self.zone.query("google.com", "A")
        self.assertEqual(res["type"], "DELEGATION_REFERRAL")
        self.assertEqual(res["rcode"], "NOERROR")
        self.assertEqual(len(res["answers"]), 0)
        # Authority contains NS records for com.
        self.assertGreaterEqual(len(res["authority"]), 1)
        self.assertEqual(str(res["authority"][0].rname), "com.")
        # Additional section contains glue
        self.assertGreaterEqual(len(res["additional"]), 1)

    def test_custom_tld_delegation(self):
        self.zone.add_delegation(
            tld="internal",
            ns_servers=["ns1.internal.corp", "ns2.internal.corp"],
            glue_ips={"ns1.internal.corp.": ["10.0.0.1"], "ns2.internal.corp.": ["10.0.0.2"]},
        )
        res = self.zone.query("app.internal", "A")
        self.assertEqual(res["type"], "DELEGATION_REFERRAL")
        self.assertEqual(len(res["authority"]), 2)
        self.assertEqual(len(res["additional"]), 2)

    def test_unknown_tld_nxdomain(self):
        res = self.zone.query("mybadtestdomain.unknownrandomtld12345", "A")
        self.assertEqual(res["type"], "NXDOMAIN")
        self.assertEqual(res["rcode"], "NXDOMAIN")
        self.assertEqual(len(res["answers"]), 0)
        self.assertEqual(len(res["authority"]), 1)
        self.assertEqual(res["authority"][0].rtype, QTYPE.SOA)


class TestLocalRootEngine(unittest.TestCase):
    """Tests autonomous engine wrapper and query counters."""

    def setUp(self):
        self.engine = LocalRootEngine()

    def test_engine_query_counters(self):
        # Apex query
        r1 = self.engine.process_query(".", "NS")
        self.assertEqual(r1["type"], "APEX_ANSWER")

        # Referral query
        r2 = self.engine.process_query("service.org", "AAAA")
        self.assertEqual(r2["type"], "DELEGATION_REFERRAL")

        # NXDOMAIN query
        r3 = self.engine.process_query("invalid.nosuchtopdomain", "A")
        self.assertEqual(r3["type"], "NXDOMAIN")

        stats = self.engine.get_stats()
        self.assertEqual(stats["total_queries_served"], 3)
        self.assertEqual(stats["apex_queries_served"], 1)
        self.assertEqual(stats["referrals_served"], 1)
        self.assertEqual(stats["nxdomain_served"], 1)
        self.assertEqual(stats["rfc"], "RFC 8806")


if __name__ == "__main__":
    unittest.main()
