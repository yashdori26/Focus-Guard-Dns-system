"""
Unit and integration tests for FocusDNS EDNS0 Subsystem (RFC 6891, 7871, 7873, 8914).
"""

import unittest
from dnslib import DNSRecord, RCODE

from server.engine.edns0 import (
    EDNSProcessor,
    EDNSMessage,
    EDNSOption,
    EDNSClientSubnet,
    DNSCookie,
    ExtendedDNSError,
    EDE_BLOCKED,
    EDE_FILTERED,
    EDE_DNSSEC_BOGUS,
    EDE_STALE_ANSWER,
    OPT_CODE_ECS,
    OPT_CODE_COOKIE,
    OPT_CODE_EDE,
    DEFAULT_EDNS_UDP_PAYLOAD_SIZE,
)


class TestEDNS0Subsystem(unittest.TestCase):
    def setUp(self):
        self.secret = b"focusdns-test-secret-key-123456"
        self.processor = EDNSProcessor(cookie_secret=self.secret)

    def test_edns_option_tlv_serialize_parse(self):
        """Verify RFC 6891 TLV option binary packing and unpacking."""
        opt = EDNSOption(code=OPT_CODE_EDE, data=b"\x00\x0fBlocked")
        wire = opt.serialize()
        self.assertEqual(len(wire), 4 + len(b"\x00\x0fBlocked"))
        self.assertEqual(wire[:2], b"\x00\x0f")  # Code 15
        self.assertEqual(wire[2:4], b"\x00\x09")  # Length 9

        parsed, rem = EDNSOption.parse(wire)
        self.assertEqual(rem, b"")
        self.assertEqual(parsed.code, OPT_CODE_EDE)
        self.assertEqual(parsed.data, b"\x00\x0fBlocked")

    def test_edns_client_subnet_ipv4(self):
        """Verify RFC 7871 ECS IPv4 serialization and privacy masking."""
        ecs = EDNSClientSubnet(
            family=EDNSClientSubnet.FAMILY_IPV4,
            source_netmask=24,
            scope_netmask=0,
            address="192.168.1.0",
        )
        self.assertEqual(ecs.family, 1)
        self.assertEqual(ecs.source_netmask, 24)
        self.assertEqual(ecs.address, "192.168.1.0")

        # Binary serialize & parse
        packed = ecs.serialize()
        unpacked = EDNSClientSubnet.parse(packed)
        self.assertEqual(unpacked.family, 1)
        self.assertEqual(unpacked.source_netmask, 24)
        self.assertEqual(unpacked.address, "192.168.1.0")

        # Anonymization test
        ecs_host = EDNSClientSubnet(EDNSClientSubnet.FAMILY_IPV4, 32, 0, "192.168.1.150")
        anon = ecs_host.anonymize(ipv4_mask=24)
        self.assertEqual(anon.source_netmask, 24)
        self.assertEqual(anon.address, "192.168.1.0")

    def test_edns_client_subnet_ipv6(self):
        """Verify RFC 7871 ECS IPv6 serialization and privacy masking."""
        ecs = EDNSClientSubnet(
            family=EDNSClientSubnet.FAMILY_IPV6,
            source_netmask=56,
            scope_netmask=0,
            address="2001:db8:85a3::",
        )
        self.assertEqual(ecs.family, 2)
        self.assertEqual(ecs.source_netmask, 56)

        packed = ecs.serialize()
        unpacked = EDNSClientSubnet.parse(packed)
        self.assertEqual(unpacked.family, 2)
        self.assertEqual(unpacked.source_netmask, 56)

        # Anonymization test
        ecs_host6 = EDNSClientSubnet(EDNSClientSubnet.FAMILY_IPV6, 128, 0, "2001:db8:85a3::8a2e:370:7334")
        anon6 = ecs_host6.anonymize(ipv6_mask=56)
        self.assertEqual(anon6.source_netmask, 56)
        self.assertTrue(anon6.address.startswith("2001:db8:85a3:"))

    def test_dns_cookie_hmac_lifecycle(self):
        """Verify RFC 7873 DNS Cookie generation and cryptographic HMAC verification."""
        client_ip = "203.0.113.195"
        client_cookie = b"01234567"  # 8 bytes

        # Generate server cookie
        server_cookie = DNSCookie.generate_server_cookie(client_ip, client_cookie, self.secret)
        self.assertEqual(len(server_cookie), 16)

        # Verification with identical IP
        is_valid = DNSCookie.verify_server_cookie(server_cookie, client_ip, client_cookie, self.secret)
        self.assertTrue(is_valid)

        # Verification with spoofed/different client IP should fail
        is_invalid_ip = DNSCookie.verify_server_cookie(server_cookie, "198.51.100.1", client_cookie, self.secret)
        self.assertFalse(is_invalid_ip)

        # Verification with tampered cookie data should fail
        tampered_cookie = bytearray(server_cookie)
        tampered_cookie[-1] ^= 0xFF
        is_tampered = DNSCookie.verify_server_cookie(bytes(tampered_cookie), client_ip, client_cookie, self.secret)
        self.assertFalse(is_tampered)

    def test_extended_dns_errors(self):
        """Verify RFC 8914 EDE encoding and diagnostic string representation."""
        ede = ExtendedDNSError(info_code=EDE_BLOCKED, extra_text="Blocked by FocusDNS Policy")
        wire = ede.serialize()
        self.assertGreater(len(wire), 2)

        unpacked = ExtendedDNSError.parse(wire)
        self.assertEqual(unpacked.info_code, EDE_BLOCKED)
        self.assertEqual(unpacked.extra_text, "Blocked by FocusDNS Policy")
        self.assertIn("Blocked by Administrator Policy", str(unpacked))

    def test_processor_plain_query_without_edns(self):
        """Verify query without EDNS OPT record is handled cleanly."""
        req = DNSRecord.question("example.com", "A")
        msg, info = self.processor.process_incoming_query(req, "1.2.3.4")
        self.assertIsNone(msg)
        self.assertFalse(info["has_edns"])

    def test_processor_query_with_edns_and_ecs_stripping(self):
        """Verify query with EDNS OPT and ECS is stripped when strip_ecs=True."""
        req = DNSRecord.question("example.com", "A")
        ecs = EDNSClientSubnet(EDNSClientSubnet.FAMILY_IPV4, 24, 0, "198.51.100.0")

        # Construct OPT pseudo-record
        msg_out = EDNSMessage(udp_payload_size=1232)
        msg_out.set_ecs(ecs)
        msg_out.attach_to_dnslib_record(req)

        # Reparse from wire to simulate network transmission
        wire = req.pack()
        received_req = DNSRecord.parse(wire)

        msg, info = self.processor.process_incoming_query(received_req, "198.51.100.42", strip_ecs=True)
        self.assertIsNotNone(msg)
        self.assertTrue(info["has_edns"])
        self.assertEqual(info["ecs_client_subnet"], "STRIPPED")
        self.assertIsNone(msg.get_ecs())

    def test_attach_error_diagnostics_to_reply(self):
        """Verify EDE option is properly appended to response."""
        req = DNSRecord.question("malware.badsite.com", "A")
        reply = req.reply()
        reply.header.rcode = RCODE.NXDOMAIN

        in_msg = EDNSMessage(udp_payload_size=1232)
        self.processor.attach_error_diagnostics(reply, in_msg, EDE_BLOCKED, "Known Malware Domain")

        # Repack & verify EDNS presence
        rep_wire = reply.pack()
        rep_parsed = DNSRecord.parse(rep_wire)
        self.assertTrue(any(rr.rtype == 41 for rr in rep_parsed.ar))

        # Check EDE parsing
        edns_rep = EDNSMessage.from_dnslib_record(rep_parsed)
        self.assertIsNotNone(edns_rep)
        ede_opt = edns_rep.get_ede()
        self.assertIsNotNone(ede_opt)
        self.assertEqual(ede_opt.info_code, EDE_BLOCKED)
        self.assertEqual(ede_opt.extra_text, "Known Malware Domain")


if __name__ == "__main__":
    unittest.main()
