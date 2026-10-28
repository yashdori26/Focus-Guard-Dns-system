"""
Unit & Integration Tests for FocusDNS RFC 9460 §6.1 Encrypted Client Hello Subsystem
====================================================================================
Validates:
  1. HPKE CipherSuite wire encoding and decoding
  2. ECHConfig binary wire serialization and deserialization
  3. ECHConfigList multiple-config encapsulation and Base64 DNS presentation
  4. Integration with SVCB/HTTPS resource records
"""

import base64
import os
import unittest
from server.engine.ech_config import (
    ECH_VERSION_DRAFT13,
    HPKEKemId,
    HPKEKdfId,
    HPKEAeadId,
    HPKECipherSuite,
    ECHConfig,
    ECHConfigList,
)
from server.engine.svcb_https import HTTPSRecord, SvcParam, SvcParamKey


class TestHPKECipherSuite(unittest.TestCase):
    """Tests HPKE CipherSuite wire serialization."""

    def test_ciphersuite_wire_codec(self):
        cs = HPKECipherSuite(HPKEKdfId.HKDF_SHA256, HPKEAeadId.AES_128_GCM)
        wire = cs.to_wire()
        self.assertEqual(len(wire), 4)
        dec, offset = HPKECipherSuite.from_wire(wire)
        self.assertEqual(offset, 4)
        self.assertEqual(dec.kdf_id, 0x0001)
        self.assertEqual(dec.aead_id, 0x0001)


class TestECHConfig(unittest.TestCase):
    """Tests ECHConfig and ECHConfigList codecs."""

    def test_ech_config_wire_roundtrip(self):
        fake_pk = b"\x01" * 32
        cfg = ECHConfig(
            public_name="ech.example.com",
            public_key=fake_pk,
            kem_id=HPKEKemId.DHKEM_X25519_HKDF_SHA256,
            cipher_suites=[
                HPKECipherSuite(HPKEKdfId.HKDF_SHA256, HPKEAeadId.AES_128_GCM),
                HPKECipherSuite(HPKEKdfId.HKDF_SHA384, HPKEAeadId.CHACHA20_POLY1305),
            ],
            config_id=5,
            maximum_name_length=128,
        )

        wire = cfg.to_wire()
        self.assertGreater(len(wire), 40)

        dec, end_offset = ECHConfig.from_wire(wire)
        self.assertEqual(end_offset, len(wire))
        self.assertEqual(dec.version, ECH_VERSION_DRAFT13)
        self.assertEqual(dec.config_id, 5)
        self.assertEqual(dec.public_name, "ech.example.com")
        self.assertEqual(dec.public_key, fake_pk)
        self.assertEqual(dec.maximum_name_length, 128)
        self.assertEqual(len(dec.cipher_suites), 2)
        self.assertEqual(dec.cipher_suites[0].aead_id, HPKEAeadId.AES_128_GCM)

    def test_ech_config_list_base64_roundtrip(self):
        cfg_list = ECHConfigList.generate_carrier_config(public_name="cloudflare-ech.com")
        self.assertEqual(len(cfg_list.configs), 1)

        b64 = cfg_list.to_base64()
        self.assertTrue(len(b64) > 20)

        # Decode back from base64
        recovered = ECHConfigList.from_base64(b64)
        self.assertEqual(len(recovered.configs), 1)
        self.assertEqual(recovered.configs[0].public_name, "cloudflare-ech.com")
        self.assertEqual(len(recovered.configs[0].public_key), 32)

    def test_https_record_with_ech_param(self):
        cfg_list = ECHConfigList.generate_carrier_config(public_name="secure.focusdns.net")
        b64_ech = cfg_list.to_base64()

        rec = HTTPSRecord(
            priority=1,
            target_name=".",
            params=[
                SvcParam(SvcParamKey.ALPN, ["h3", "h2"]),
                SvcParam(SvcParamKey.PORT, 443),
                SvcParam(SvcParamKey.ECH, b64_ech),
            ],
        )

        # Serialize to wire and back
        wire = rec.to_wire()
        dec_rec = HTTPSRecord.from_wire(wire)
        ech_param = dec_rec.get_param(SvcParamKey.ECH)
        self.assertIsNotNone(ech_param)
        self.assertEqual(ech_param.value, b64_ech)

        # Parse ECH from the decoded parameter
        recovered_ech = ECHConfigList.from_base64(ech_param.value)
        self.assertEqual(recovered_ech.configs[0].public_name, "secure.focusdns.net")


if __name__ == "__main__":
    unittest.main()
