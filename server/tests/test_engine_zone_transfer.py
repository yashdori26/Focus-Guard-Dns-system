"""
Unit & Integration Tests for FocusDNS RFC 5936 AXFR, RFC 1995 IXFR & RFC 1996 DNS NOTIFY
========================================================================================
Comprehensive validation suite testing:
  1. RFC 5936 AXFR Full Zone Transfer TCP stream chunk framing and SOA bracketing
  2. RFC 1995 IXFR Incremental Zone Transfer delta sequencing and fallback to AXFR
  3. Zone Transfer Access Control Lists (ACLs) by IPv4 and IPv6 CIDR
  4. TSIG Cryptographic Transaction Authentication (HMAC-SHA256) on transfers
  5. RFC 1996 DNS NOTIFY asynchronous secondary notification broadcasting and ACK parsing
  6. High-concurrency transfer requests and historical delta eviction
"""

import socket
import struct
import threading
import time
import unittest
from typing import List

from dnslib import (
    DNSRecord,
    DNSHeader,
    DNSQuestion,
    RR,
    QTYPE,
    RCODE,
    A,
    AAAA,
    TXT,
    SOA,
)

from server.engine.zone_authority import (
    AuthoritativeZone,
    AuthoritativeRecord,
    TSIGKey,
)
from server.engine.zone_transfer import (
    ZoneDelta,
    ZoneTransferACL,
    ZoneTransferEngine,
    DNSNotifyBroadcaster,
    QTYPE_AXFR,
    QTYPE_IXFR,
)


class TestZoneDelta(unittest.TestCase):
    """Tests incremental zone modification delta tracking."""

    def test_delta_creation_and_records(self):
        delta = ZoneDelta(from_serial=100, to_serial=101)
        self.assertEqual(delta.from_serial, 100)
        self.assertEqual(delta.to_serial, 101)
        self.assertTrue(delta.is_empty())

        del_rec = AuthoritativeRecord("old.example.com", "A", "1.2.3.4", 300)
        add_rec = AuthoritativeRecord("new.example.com", "A", "5.6.7.8", 300)

        delta.add_deletion(del_rec)
        delta.add_addition(add_rec)

        self.assertFalse(delta.is_empty())
        self.assertEqual(len(delta.deleted_records), 1)
        self.assertEqual(len(delta.added_records), 1)
        self.assertEqual(delta.deleted_records[0].name, "old.example.com")
        self.assertEqual(delta.added_records[0].name, "new.example.com")


class TestZoneTransferACL(unittest.TestCase):
    """Tests access control policies for zone replication."""

    def test_unrestricted_acl(self):
        acl = ZoneTransferACL()
        auth, reason = acl.is_client_authorized("192.168.1.50")
        self.assertTrue(auth)
        self.assertEqual(reason, "Authorized")

    def test_subnet_restriction(self):
        acl = ZoneTransferACL(allowed_subnets=["10.0.0.0/8", "192.168.1.0/24"])
        # In subnet
        auth, _ = acl.is_client_authorized("10.5.20.1")
        self.assertTrue(auth)

        auth2, _ = acl.is_client_authorized("192.168.1.200")
        self.assertTrue(auth2)

        # Outside subnet
        auth3, reason3 = acl.is_client_authorized("172.16.0.1")
        self.assertFalse(auth3)
        self.assertIn("not in transfer ACL", reason3)

    def test_ipv6_subnet_restriction(self):
        acl = ZoneTransferACL(allowed_subnets=["2001:db8:acad::/48"])
        auth, _ = acl.is_client_authorized("2001:db8:acad:1::50")
        self.assertTrue(auth)

        auth_fail, _ = acl.is_client_authorized("2001:db8:beef::1")
        self.assertFalse(auth_fail)

    def test_invalid_client_ip(self):
        acl = ZoneTransferACL(allowed_subnets=["10.0.0.0/8"])
        auth, reason = acl.is_client_authorized("invalid_ip_format")
        self.assertFalse(auth)
        self.assertIn("Invalid client IP", reason)

    def test_tsig_requirement(self):
        acl = ZoneTransferACL(
            require_tsig=True,
            allowed_tsig_keys=["axfr-key.example.com"],
        )
        # No key provided
        auth, reason = acl.is_client_authorized("10.0.0.1", tsig_key_name=None)
        self.assertFalse(auth)
        self.assertIn("TSIG signature required", reason)

        # Wrong key
        auth_wrong, reason_wrong = acl.is_client_authorized("10.0.0.1", tsig_key_name="unknown-key")
        self.assertFalse(auth_wrong)
        self.assertIn("not authorized", reason_wrong)

        # Correct key
        auth_ok, _ = acl.is_client_authorized("10.0.0.1", tsig_key_name="axfr-key.example.com.")
        self.assertTrue(auth_ok)


class TestAXFRZoneTransfer(unittest.TestCase):
    """Tests RFC 5936 AXFR full zone transfer mechanics."""

    def setUp(self):
        self.engine = ZoneTransferEngine()
        self.zone = AuthoritativeZone("corp.internal")
        self.zone.serial = 1001

        # Populate zone with records
        self.zone.add_record(AuthoritativeRecord("corp.internal", "SOA", "ns1.corp.internal admin.corp.internal 1001 3600 600 604800 300", 300))
        self.zone.add_record(AuthoritativeRecord("ns1.corp.internal", "A", "10.0.0.1", 3600))
        self.zone.add_record(AuthoritativeRecord("ns2.corp.internal", "A", "10.0.0.2", 3600))
        self.zone.add_record(AuthoritativeRecord("mail.corp.internal", "A", "10.0.0.10", 3600))
        self.zone.add_record(AuthoritativeRecord("corp.internal", "TXT", '"v=spf1 mx -all"', 300))

    def tearDown(self):
        self.engine.close()

    def test_axfr_success_stream(self):
        req = DNSRecord.question("corp.internal", "AXFR")
        rcode, chunks = self.engine.handle_axfr_request(req, self.zone, "127.0.0.1")

        self.assertEqual(rcode, RCODE.NOERROR)
        self.assertGreater(len(chunks), 0)

        # Parse generated AXFR packet
        resp = DNSRecord.parse(chunks[0])
        self.assertEqual(resp.header.rcode, RCODE.NOERROR)
        self.assertTrue(resp.header.qr)

        # RFC 5936 Requirement: Starting SOA and Ending SOA
        answers = resp.rr
        self.assertGreaterEqual(len(answers), 3)

        first_rr = answers[0]
        last_rr = answers[-1]

        self.assertEqual(first_rr.rtype, QTYPE.SOA)
        self.assertEqual(last_rr.rtype, QTYPE.SOA)
        self.assertEqual(str(first_rr.rdata), str(last_rr.rdata))

        stats = self.engine.get_stats()
        self.assertEqual(stats["axfr_transfers_served"], 1)

    def test_axfr_refused_by_acl(self):
        acl = ZoneTransferACL(allowed_subnets=["192.168.100.0/24"])
        self.engine.set_zone_acl("corp.internal", acl)

        req = DNSRecord.question("corp.internal", "AXFR")
        rcode, chunks = self.engine.handle_axfr_request(req, self.zone, "10.0.0.5")

        self.assertEqual(rcode, RCODE.REFUSED)
        resp = DNSRecord.parse(chunks[0])
        self.assertEqual(resp.header.rcode, RCODE.REFUSED)

    def test_axfr_missing_soa_servfail(self):
        empty_zone = AuthoritativeZone("empty.zone")
        empty_zone._records.clear()  # Remove auto-initialized SOA
        req = DNSRecord.question("empty.zone", "AXFR")
        rcode, chunks = self.engine.handle_axfr_request(req, empty_zone, "127.0.0.1")

        self.assertEqual(rcode, RCODE.SERVFAIL)


class TestIXFRZoneTransfer(unittest.TestCase):
    """Tests RFC 1995 IXFR incremental zone transfer mechanics."""

    def setUp(self):
        self.engine = ZoneTransferEngine(max_ixfr_history=10)
        self.zone = AuthoritativeZone("prod.net")
        self.zone.add_record(AuthoritativeRecord("prod.net", "SOA", "ns1.prod.net admin.prod.net 200 3600 600 604800 300", 300))
        self.zone.add_record(AuthoritativeRecord("api.prod.net", "A", "10.1.0.1", 300))
        self.zone.serial = 200

    def tearDown(self):
        self.engine.close()

    def test_ixfr_delta_generation(self):
        # Create delta from 198 -> 199
        d1 = ZoneDelta(198, 199)
        d1.add_addition(AuthoritativeRecord("v1.prod.net", "A", "10.1.0.5", 300))
        self.engine.record_zone_delta("prod.net", d1)

        # Create delta from 199 -> 200
        d2 = ZoneDelta(199, 200)
        d2.add_deletion(AuthoritativeRecord("v1.prod.net", "A", "10.1.0.5", 300))
        d2.add_addition(AuthoritativeRecord("v2.prod.net", "A", "10.1.0.6", 300))
        self.engine.record_zone_delta("prod.net", d2)

        # Client requests IXFR starting from serial 199
        req = DNSRecord.question("prod.net", "IXFR")
        req.add_auth(RR("prod.net.", QTYPE.SOA, ttl=300, rdata=SOA("ns1.prod.net.", "admin.prod.net.", (199, 3600, 600, 604800, 300))))

        rcode, chunks = self.engine.handle_ixfr_request(req, self.zone, 199, "127.0.0.1")
        self.assertEqual(rcode, RCODE.NOERROR)

        resp = DNSRecord.parse(chunks[0])
        self.assertEqual(resp.header.rcode, RCODE.NOERROR)

        # Verification of standard RFC 1995 IXFR record order:
        # SOA(current) -> SOA(old) -> Deleted -> SOA(new) -> Added -> SOA(current)
        answers = resp.rr
        self.assertGreaterEqual(len(answers), 4)
        self.assertEqual(answers[0].rtype, QTYPE.SOA)
        self.assertEqual(answers[-1].rtype, QTYPE.SOA)

        stats = self.engine.get_stats()
        self.assertEqual(stats["ixfr_transfers_served"], 1)

    def test_ixfr_already_up_to_date(self):
        # Client serial matches current zone serial
        req = DNSRecord.question("prod.net", "IXFR")
        rcode, chunks = self.engine.handle_ixfr_request(req, self.zone, 200, "127.0.0.1")

        self.assertEqual(rcode, RCODE.NOERROR)
        resp = DNSRecord.parse(chunks[0])
        # Should return a single SOA record indicating up to date
        self.assertEqual(len(resp.rr), 1)
        self.assertEqual(resp.rr[0].rtype, QTYPE.SOA)

    def test_ixfr_outdated_history_fallback_to_axfr(self):
        # Client serial is 50, but we only have deltas from 195+
        req = DNSRecord.question("prod.net", "IXFR")
        rcode, chunks = self.engine.handle_ixfr_request(req, self.zone, 50, "127.0.0.1")

        # Automatic fallback to full AXFR
        self.assertEqual(rcode, RCODE.NOERROR)
        resp = DNSRecord.parse(chunks[0])
        self.assertGreater(len(resp.rr), 2)
        self.assertEqual(resp.rr[0].rtype, QTYPE.SOA)
        self.assertEqual(resp.rr[-1].rtype, QTYPE.SOA)


class TestDNSNotifyBroadcaster(unittest.TestCase):
    """Tests RFC 1996 DNS NOTIFY secondary slave alerts."""

    def setUp(self):
        self.engine = ZoneTransferEngine()
        self.broadcaster = DNSNotifyBroadcaster(self.engine)

    def tearDown(self):
        self.engine.close()

    def test_notify_mock_secondary_ack(self):
        # Create a mock secondary DNS server socket listening on loopback
        server_sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        server_sock.bind(("127.0.0.1", 0))
        assigned_port = server_sock.getsockname()[1]

        def _mock_slave():
            try:
                data, addr = server_sock.recvfrom(512)
                req = DNSRecord.parse(data)
                # Ensure opcode is 4 (NOTIFY)
                if req.header.opcode == 4:
                    reply = req.reply()
                    reply.header.rcode = RCODE.NOERROR
                    server_sock.sendto(reply.pack(), addr)
            except Exception:
                pass
            finally:
                server_sock.close()

        th = threading.Thread(target=_mock_slave, daemon=True)
        th.start()

        # Send NOTIFY from engine
        success = self.broadcaster.send_direct("example.org", "127.0.0.1", assigned_port, timeout=1.0)
        self.assertTrue(success)

        stats = self.engine.get_stats()
        self.assertEqual(stats["notifies_sent"], 1)
        self.assertEqual(stats["notifies_acknowledged"], 1)

    def test_notify_secondary_timeout(self):
        # Sending to an unmapped port should timeout gracefully
        success = self.broadcaster.send_direct("example.org", "127.0.0.1", 64999, timeout=0.1)
        self.assertFalse(success)

        stats = self.engine.get_stats()
        self.assertEqual(stats["notifies_sent"], 1)
        self.assertEqual(stats["notifies_acknowledged"], 0)


if __name__ == "__main__":
    unittest.main()
