"""
Unit and integration tests for FocusDNS DNSSEC Zone Signer and Key Rollover Engine.
"""

import unittest
from server.engine.dnssec_signer import (
    DNSSECKeyPair,
    DNSSECSignerEngine,
    compute_key_tag,
    canonical_dns_name,
    DNSKEY_FLAG_ZSK,
    DNSKEY_FLAG_KSK,
    DNSSEC_ALG_ECDSAP256SHA256,
    DS_DIGEST_SHA256,
)


class TestDNSSECSignerSubsystem(unittest.TestCase):
    def setUp(self):
        self.signer = DNSSECSignerEngine("secure.example.com", validity_days=7)

    def test_canonical_dns_name_wire_format(self):
        """Verify RFC 4034 §6.1 wire serialization of domain names."""
        wire = canonical_dns_name("example.com")
        self.assertEqual(wire, b"\x07example\x03com\x00")

        root_wire = canonical_dns_name(".")
        self.assertEqual(root_wire, b"\x00")

    def test_dnssec_keypair_and_keytag(self):
        """Verify ECDSA P-256 key generation, flags, and RFC 4034 key tag computation."""
        key = DNSSECKeyPair(flags=DNSKEY_FLAG_ZSK, algorithm=DNSSEC_ALG_ECDSAP256SHA256)
        self.assertTrue(key.is_zsk())
        self.assertFalse(key.is_ksk())
        self.assertEqual(len(key.raw_public_bytes), 64)  # X (32B) + Y (32B)

        tag = key.key_tag
        self.assertIsInstance(tag, int)
        self.assertGreater(tag, 0)
        self.assertLessEqual(tag, 65535)

    def test_ds_record_generation(self):
        """Verify parent zone Delegation Signer (DS) record digest computation."""
        ksk = self.signer.ksk
        ds = ksk.generate_ds_record("secure.example.com", DS_DIGEST_SHA256)

        self.assertEqual(ds["name"], "secure.example.com")
        self.assertEqual(ds["key_tag"], ksk.key_tag)
        self.assertEqual(ds["algorithm"], DNSSEC_ALG_ECDSAP256SHA256)
        self.assertEqual(ds["digest_type"], DS_DIGEST_SHA256)
        self.assertEqual(len(ds["digest_hex"]), 64)  # 32-byte SHA-256 hex string

    def test_rrsig_signing_and_formatting(self):
        """Verify RRset canonical signing generates valid RFC 4034 RRSIG records."""
        # Simulate A record RRset: 198.51.100.1, 198.51.100.2
        rdata1 = b"\xc6\x33\x64\x01"
        rdata2 = b"\xc6\x33\x64\x02"

        rrsig = self.signer.sign_rrset(
            name="host.secure.example.com",
            type_covered_num=1,  # A
            original_ttl=300,
            canonical_rdata_list=[rdata1, rdata2],
        )

        self.assertEqual(rrsig["type_covered"], 1)
        self.assertEqual(rrsig["algorithm"], DNSSEC_ALG_ECDSAP256SHA256)
        self.assertEqual(rrsig["signer_name"], "secure.example.com")
        self.assertEqual(len(rrsig["signature_bytes"]), 64)  # Raw R || S ECDSA P-256
        self.assertIn("signature_b64", rrsig)

    def test_nsec_authenticated_denial_of_existence(self):
        """Verify RFC 4034 NSEC record generation with Type Bit Maps."""
        nsec = self.signer.generate_nsec_record(
            owner_name="alpha.secure.example.com",
            next_domain_name="omega.secure.example.com",
            types_present=[1, 28, 46],  # A (1), AAAA (28), RRSIG (46)
            ttl=300,
        )

        self.assertEqual(nsec["name"], "alpha.secure.example.com")
        self.assertEqual(nsec["next_domain"], "omega.secure.example.com")
        self.assertIn(1, nsec["types"])
        self.assertIn(28, nsec["types"])
        self.assertGreater(len(nsec["rdata_bytes"]), 5)

    def test_key_rollover_lifecycle(self):
        """Verify automated ZSK and KSK rollover mechanisms."""
        initial_zsk_tag = self.signer.zsk.key_tag
        self.signer.rotate_zsk()
        self.assertNotEqual(self.signer.zsk.key_tag, initial_zsk_tag)
        self.assertEqual(len(self.signer._retired_keys), 1)

        initial_ksk_tag = self.signer.ksk.key_tag
        new_ds = self.signer.rotate_ksk()
        self.assertNotEqual(self.signer.ksk.key_tag, initial_ksk_tag)
        self.assertEqual(new_ds["key_tag"], self.signer.ksk.key_tag)


if __name__ == "__main__":
    unittest.main()
