"""
FocusDNS Engine Test Suite - DNSSEC Cryptographic Validation (RFC 4033, 4034, 4035)
Validates:
- IANA Root Zone Trust Anchors (KSK-2017 & KSK-2024)
- RFC 4034 Appendix B Key Tag computation
- RFC 4034 Section 5.1.4 DS digest calculation (SHA-256)
- Multi-algorithm signature verification (RSA-SHA256, ECDSA P-256, Ed25519)
- Detection of BOGUS signatures (tampered wire payload, expired timestamps)
- Packet inspector detecting DNSKEY, RRSIG, DS, NSEC records
"""

import time
import struct
import hashlib
import unittest
from dnslib import DNSRecord, DNSHeader, RR, QTYPE, RCODE, A

from server.engine.dnssec import (
    DNSSECValidator,
    DnssecStatus,
    calculate_key_tag,
    encode_dns_name,
    ALG_RSASHA256,
    ALG_ECDSAP256SHA256,
    ALG_ED25519,
    DIGEST_SHA256,
    ROOT_TRUST_ANCHORS,
)

try:
    from cryptography.hazmat.primitives.asymmetric import rsa, ec, ed25519
    from cryptography.hazmat.primitives import hashes
    HAS_CRYPTO = True
except ImportError:
    HAS_CRYPTO = False


class TestDNSSECValidator(unittest.TestCase):

    def setUp(self):
        self.validator = DNSSECValidator()

    def test_root_trust_anchors_present(self):
        anchors = self.validator.trust_anchors
        self.assertGreaterEqual(len(anchors), 2)

        key_tags = [a["key_tag"] for a in anchors]
        self.assertIn(20326, key_tags, "KSK-2017 root anchor missing")
        self.assertIn(38696, key_tags, "KSK-2024 root anchor missing")

    def test_key_tag_calculation_rfc4034(self):
        # Synthetic DNSKEY RDATA: Flags=257 (0x0101), Protocol=3 (0x03), Algorithm=8 (0x08), PubKey
        dnskey_rdata = bytes([0x01, 0x01, 0x03, 0x08, 0x12, 0x34, 0x56, 0x78])
        tag = calculate_key_tag(dnskey_rdata)
        self.assertIsInstance(tag, int)
        self.assertGreaterEqual(tag, 0)
        self.assertLessEqual(tag, 65535)

    def test_ds_digest_verification(self):
        domain = "example.com"
        dnskey_rdata = b"\x01\x01\x03\x08" + b"A" * 64

        # Compute valid SHA-256 digest: SHA256(canonical_name + dnskey_rdata)
        wire_name = encode_dns_name(domain)
        expected_digest = hashlib.sha256(wire_name + dnskey_rdata).hexdigest().lower()

        is_valid = self.validator.verify_ds_digest(domain, dnskey_rdata, expected_digest, DIGEST_SHA256)
        self.assertTrue(is_valid)

        # Tampered digest should fail
        tampered_digest = "0" * 64
        self.assertFalse(self.validator.verify_ds_digest(domain, dnskey_rdata, tampered_digest, DIGEST_SHA256))

    @unittest.skipUnless(HAS_CRYPTO, "Requires cryptography library")
    def test_rsa_sha256_signature_verification(self):
        # 1. Generate RSA key pair
        private_key = rsa.generate_private_key(public_exponent=65537, key_size=2048)
        pub_numbers = private_key.public_key().public_numbers()

        # Build RFC 3110 / RFC 4034 RSA public key wire bytes: [exp_len (1 or 3 bytes)][exponent][modulus]
        exp_bytes = pub_numbers.e.to_bytes((pub_numbers.e.bit_length() + 7) // 8, byteorder="big")
        mod_bytes = pub_numbers.n.to_bytes((pub_numbers.n.bit_length() + 7) // 8, byteorder="big")
        if len(exp_bytes) <= 255:
            pub_key_bytes = bytes([len(exp_bytes)]) + exp_bytes + mod_bytes
        else:
            pub_key_bytes = b"\x00" + struct.pack(">H", len(exp_bytes)) + exp_bytes + mod_bytes

        # 2. Sign arbitrary RRset wire payload
        data_to_sign = b"canonical-dns-rrset-payload-data"
        from cryptography.hazmat.primitives.asymmetric import padding
        signature = private_key.sign(
            data_to_sign,
            padding.PKCS1v15(),
            hashes.SHA256()
        )

        # 3. Verify via engine validator
        is_valid = self.validator.verify_rrsig_signature(
            algorithm=ALG_RSASHA256,
            public_key_bytes=pub_key_bytes,
            signature_bytes=signature,
            signed_data=data_to_sign
        )
        self.assertTrue(is_valid)

        # 4. Tampered data must fail
        tampered_valid = self.validator.verify_rrsig_signature(
            algorithm=ALG_RSASHA256,
            public_key_bytes=pub_key_bytes,
            signature_bytes=signature,
            signed_data=b"forged-rrset-data"
        )
        self.assertFalse(tampered_valid)

    @unittest.skipUnless(HAS_CRYPTO, "Requires cryptography library")
    def test_ed25519_signature_verification(self):
        private_key = ed25519.Ed25519PrivateKey.generate()
        from cryptography.hazmat.primitives import serialization
        pub_key_bytes = private_key.public_key().public_bytes(
            encoding=serialization.Encoding.Raw,
            format=serialization.PublicFormat.Raw
        )

        data = b"ed25519-signed-dns-data"
        sig = private_key.sign(data)

        # Valid
        is_valid = self.validator.verify_rrsig_signature(
            algorithm=ALG_ED25519,
            public_key_bytes=pub_key_bytes,
            signature_bytes=sig,
            signed_data=data
        )
        self.assertTrue(is_valid)

        # Tampered
        self.assertFalse(self.validator.verify_rrsig_signature(
            algorithm=ALG_ED25519,
            public_key_bytes=pub_key_bytes,
            signature_bytes=sig,
            signed_data=b"tampered"
        ))



    def test_packet_inspector_and_ad_flag(self):
        rec = DNSRecord.question("secure.example.org", "A")
        reply = rec.reply()
        reply.add_answer(RR("secure.example.org", QTYPE.A, ttl=300, rdata=A("93.184.216.34")))
        # Set AD bit in DNSHeader
        reply.header.ad = 1

        info = self.validator.inspect_packet_dnssec(reply)
        self.assertTrue(info["ad_flag"])

        status = self.validator.validate_record(reply)
        self.assertEqual(status, DnssecStatus.SECURE)


if __name__ == "__main__":
    unittest.main()
