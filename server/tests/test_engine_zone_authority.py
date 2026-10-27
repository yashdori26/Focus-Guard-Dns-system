"""
Unit and integration tests for Authoritative Zones, Split-Horizon Views, and RFC 2136/2845 TSIG Dynamic DNS.
"""

import time
import unittest
from dnslib import DNSRecord, QTYPE, RCODE, CLASS

from server.engine.zone_authority import (
    AuthoritativeRecord,
    AuthoritativeZone,
    SplitHorizonView,
    ZoneAuthorityEngine,
    TSIGKey,
    TSIG_HMAC_SHA256,
)


class TestZoneAuthoritySubsystem(unittest.TestCase):
    def setUp(self):
        self.engine = ZoneAuthorityEngine()

    def test_zone_record_conversion(self):
        """Verify AuthoritativeRecord converts accurately to dnslib RR."""
        rec_a = AuthoritativeRecord("host.example.com", "A", "192.0.2.1", ttl=300)
        rr_a = rec_a.to_dnslib_rr()
        self.assertIsNotNone(rr_a)
        self.assertEqual(str(rr_a.rname), "host.example.com.")
        self.assertEqual(rr_a.rtype, QTYPE.A)

        rec_txt = AuthoritativeRecord("example.com", "TXT", "v=spf1 include:_spf.google.com ~all")
        rr_txt = rec_txt.to_dnslib_rr()
        self.assertIsNotNone(rr_txt)
        self.assertEqual(rr_txt.rtype, QTYPE.TXT)

    def test_authoritative_zone_queries_and_wildcards(self):
        """Verify authoritative zone resolution for exact matches and wildcards."""
        zone = AuthoritativeZone("corp.local")
        zone.add_record(AuthoritativeRecord("app.corp.local", "A", "10.10.1.5"))
        zone.add_record(AuthoritativeRecord("mail.corp.local", "A", "10.10.1.6"))
        zone.add_record(AuthoritativeRecord("*.dev.corp.local", "A", "10.10.99.1"))

        # 1. Exact match
        recs, is_auth, exists = zone.query("app.corp.local", "A")
        self.assertTrue(is_auth)
        self.assertEqual(len(recs), 1)
        self.assertEqual(recs[0].rdata, "10.10.1.5")

        # 2. Wildcard match (*.dev.corp.local)
        recs_wc, is_auth, exists = zone.query("feature-123.dev.corp.local", "A")
        self.assertTrue(is_auth)
        self.assertEqual(len(recs_wc), 1)
        self.assertEqual(recs_wc[0].rdata, "10.10.99.1")

        # 3. Non-existent name
        recs_nx, is_auth, exists = zone.query("missing.corp.local", "A")
        self.assertTrue(is_auth)
        self.assertFalse(exists)
        self.assertEqual(len(recs_nx), 0)

    def test_split_horizon_view_routing(self):
        """Verify client IP is steered to appropriate split-horizon view."""
        internal_view = SplitHorizonView("Internal-LAN", subnets=["192.168.1.0/24"], priority=100)
        guest_view = SplitHorizonView("Guest-WiFi", subnets=["172.16.0.0/16"], priority=50)

        # Internal view zone gives 10.0.0.10
        int_zone = AuthoritativeZone("portal.local")
        int_zone.add_record(AuthoritativeRecord("portal.local", "A", "10.0.0.10"))
        internal_view.add_zone(int_zone)

        # Guest view zone gives 203.0.113.1
        guest_zone = AuthoritativeZone("portal.local")
        guest_zone.add_record(AuthoritativeRecord("portal.local", "A", "203.0.113.1"))
        guest_view.add_zone(guest_zone)

        self.engine.add_view(internal_view)
        self.engine.add_view(guest_view)

        # Query from internal IP
        req = DNSRecord.question("portal.local", "A")
        wire_int, telem_int = self.engine.resolve_authoritative(req, client_ip="192.168.1.45")
        self.assertEqual(telem_int["view"], "Internal-LAN")
        resp_int = DNSRecord.parse(wire_int)
        self.assertEqual(str(resp_int.rr[0].rdata), "10.0.0.10")

        # Query from guest IP
        wire_guest, telem_guest = self.engine.resolve_authoritative(req, client_ip="172.16.5.99")
        self.assertEqual(telem_guest["view"], "Guest-WiFi")
        resp_guest = DNSRecord.parse(wire_guest)
        self.assertEqual(str(resp_guest.rr[0].rdata), "203.0.113.1")

    def test_tsig_authentication_and_dynamic_dns_update(self):
        """Verify RFC 2845 TSIG HMAC authentication and RFC 2136 DNS UPDATE processing."""
        zone = AuthoritativeZone("dyn.example")
        self.engine._default_view.add_zone(zone)

        # Setup TSIG key
        key_name = "dynupdate.key"
        secret = b"focusdns-tsig-super-secret-key-bytes"
        tsig = TSIGKey(key_name, secret, TSIG_HMAC_SHA256)
        self.engine.add_tsig_key(tsig)

        # Construct DNS UPDATE record (RFC 2136)
        update_rec = DNSRecord()
        update_rec.header.opcode = 5  # UPDATE
        update_rec.add_question(DNSRecord.question("dyn.example", "SOA").q)
        # Add dynamic A record: newhost.dyn.example IN A 198.51.100.77
        new_rr = AuthoritativeRecord("newhost.dyn.example", "A", "198.51.100.77", ttl=60).to_dnslib_rr()
        update_rec.add_auth(new_rr)

        wire_update = update_rec.pack()
        timestamp = int(time.time())
        mac = tsig.generate_mac(wire_update, timestamp)

        # 1. Update with valid TSIG
        rcode, msg = self.engine.process_dynamic_update(
            wire_update, "127.0.0.1", tsig_key_name=key_name, tsig_mac=mac, tsig_time=timestamp
        )
        self.assertEqual(rcode, RCODE.NOERROR)

        # Verify dynamic record is now resolvable
        recs, is_auth, exists = zone.query("newhost.dyn.example", "A")
        self.assertEqual(len(recs), 1)
        self.assertEqual(recs[0].rdata, "198.51.100.77")

        # 2. Update with invalid MAC should be rejected
        bad_mac = b"invalid-corrupt-mac-bytes-123456"
        bad_rcode, _ = self.engine.process_dynamic_update(
            wire_update, "127.0.0.1", tsig_key_name=key_name, tsig_mac=bad_mac, tsig_time=timestamp
        )
        self.assertEqual(bad_rcode, RCODE.NOTAUTH)

    def test_zone_import_export(self):
        """Verify master zone file RFC 1035 export and re-import."""
        zone = AuthoritativeZone("simple.local")
        zone.add_record(AuthoritativeRecord("web.simple.local", "A", "1.2.3.4", ttl=600))
        zone.add_record(AuthoritativeRecord("mail.simple.local", "A", "5.6.7.8", ttl=600))

        exported = zone.export_zone_file()
        self.assertIn("web.simple.local", exported)
        self.assertIn("1.2.3.4", exported)

        # Re-import into new zone
        zone2 = AuthoritativeZone("simple.local")
        zone2.import_zone_file(exported)
        recs, _, _ = zone2.query("web.simple.local", "A")
        self.assertEqual(len(recs), 1)
        self.assertEqual(recs[0].rdata, "1.2.3.4")


if __name__ == "__main__":
    unittest.main()
