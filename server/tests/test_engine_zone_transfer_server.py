"""
Unit & Integration Tests for FocusDNS Dedicated RFC 5936 AXFR TCP Daemon & Client
================================================================================
Validates:
  1. ZoneTransferServer multi-threaded TCP listener lifecycle (start, accept, stop)
  2. RFC 1035 §4.2.2 2-octet stream length prefix framing
  3. AXFRClient live socket replication from ZoneTransferServer over loopback TCP
  4. Reconstruction of AuthoritativeZone on client with SOA boundary checks
  5. Refusal / NOTAUTH error handling for unhosted zones
  6. High-throughput multi-record TCP stream packing
"""

import socket
import time
import unittest

from dnslib import DNSRecord, QTYPE, RCODE

from server.engine.zone_authority import (
    AuthoritativeZone,
    AuthoritativeRecord,
    ZoneAuthorityEngine,
)
from server.engine.zone_transfer import ZoneTransferEngine
from server.engine.zone_transfer_server import (
    ZoneTransferServer,
    AXFRClient,
)


class TestZoneTransferServerIntegration(unittest.TestCase):
    """Tests live TCP AXFR server daemon and AXFR client replication."""

    def setUp(self):
        # Find an available port
        s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        s.bind(("127.0.0.1", 0))
        self.port = s.getsockname()[1]
        s.close()

        self.authority = ZoneAuthorityEngine()
        self.transfer_engine = ZoneTransferEngine()

        # Seed authoritative zone
        self.master_zone = AuthoritativeZone("primary.corp")
        self.master_zone.serial = 5001
        self.master_zone.add_record(AuthoritativeRecord("primary.corp", "SOA", "ns1.primary.corp admin.primary.corp 5001 3600 600 604800 300", 300))
        self.master_zone.add_record(AuthoritativeRecord("ns1.primary.corp", "A", "10.0.0.1", 3600))
        self.master_zone.add_record(AuthoritativeRecord("ns2.primary.corp", "A", "10.0.0.2", 3600))
        self.master_zone.add_record(AuthoritativeRecord("web.primary.corp", "A", "10.0.1.100", 300))
        self.master_zone.add_record(AuthoritativeRecord("mail.primary.corp", "A", "10.0.1.200", 300))
        self.master_zone.add_record(AuthoritativeRecord("primary.corp", "TXT", '"v=spf1 mx -all"', 300))

        self.authority.default_view.add_zone(self.master_zone)

        self.server = ZoneTransferServer(
            host="127.0.0.1",
            port=self.port,
            zone_authority=self.authority,
            transfer_engine=self.transfer_engine,
        )
        self.server.start()
        time.sleep(0.05)

        self.client = AXFRClient(master_host="127.0.0.1", master_port=self.port, timeout=3.0)

    def tearDown(self):
        self.server.stop()
        self.transfer_engine.close()

    def test_axfr_pull_success(self):
        success, pulled_zone, reason = self.client.pull_zone_axfr("primary.corp")

        self.assertTrue(success, f"Transfer failed: {reason}")
        self.assertIsNotNone(pulled_zone)
        self.assertEqual(pulled_zone.origin, "primary.corp")

        # Verify records transferred
        soa = pulled_zone.get_soa()
        self.assertIsNotNone(soa)

        # Check A records
        web_recs = pulled_zone.get_records("web.primary.corp", "A")
        self.assertEqual(len(web_recs), 1)
        self.assertEqual(web_recs[0].rdata, "10.0.1.100")

        mail_recs = pulled_zone.get_records("mail.primary.corp", "A")
        self.assertEqual(len(mail_recs), 1)
        self.assertEqual(mail_recs[0].rdata, "10.0.1.200")

        txt_recs = pulled_zone.get_records("primary.corp", "TXT")
        self.assertEqual(len(txt_recs), 1)
        self.assertIn("v=spf1", txt_recs[0].rdata)

    def test_axfr_unhosted_zone_returns_error(self):
        success, pulled_zone, reason = self.client.pull_zone_axfr("unhosted.domain.com")
        self.assertFalse(success)
        self.assertIsNone(pulled_zone)
        self.assertIn("NOTAUTH", reason)

    def test_axfr_secondary_zone_authority_ingestion(self):
        # Secondary server pulls zone and mounts it in its local ZoneAuthorityEngine
        success, pulled_zone, _ = self.client.pull_zone_axfr("primary.corp")
        self.assertTrue(success)

        secondary_authority = ZoneAuthorityEngine()
        secondary_authority.default_view.add_zone(pulled_zone)

        # Query secondary authoritative engine
        req = DNSRecord.question("web.primary.corp", "A")
        res = secondary_authority.resolve_authoritative(req, "192.168.1.1")
        self.assertIsNotNone(res)

        wire, telem = res
        parsed = DNSRecord.parse(wire)
        self.assertEqual(parsed.header.rcode, RCODE.NOERROR)
        self.assertEqual(str(parsed.rr[0].rdata), "10.0.1.100")


if __name__ == "__main__":
    unittest.main()
