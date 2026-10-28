"""
server/tests/test_engine_attestation.py
Unit and Integration Tests for Android Hardware KeyStore Attestation & Anti-Replay Engine.
"""

import base64
import time
import unittest

from server.engine.attestation_validator import (
    AttestationValidator,
    NonceRecord,
    SECURITY_LEVEL_STRONGBOX,
    SECURITY_LEVEL_TRUSTED_ENVIRONMENT,
    SECURITY_LEVEL_SOFTWARE,
    SECURITY_LEVEL_NAMES,
)


class TestHardwareAttestationValidator(unittest.TestCase):
    def setUp(self):
        self.validator = AttestationValidator(hmac_secret="test_master_secret_12345")
        self.device_id = "test-pixel-device-001"

    def test_security_level_mappings(self):
        self.assertEqual(SECURITY_LEVEL_NAMES[SECURITY_LEVEL_STRONGBOX], "STRONGBOX")
        self.assertEqual(SECURITY_LEVEL_NAMES[SECURITY_LEVEL_TRUSTED_ENVIRONMENT], "TRUSTED_EXECUTION_ENVIRONMENT")
        self.assertEqual(SECURITY_LEVEL_NAMES[SECURITY_LEVEL_SOFTWARE], "SOFTWARE")

    def test_nonce_generation_and_uniqueness(self):
        nonces = set()
        for _ in range(50):
            nonce = self.validator.generate_nonce(self.device_id)
            self.assertEqual(len(nonce), 64)  # 32 bytes hex
            self.assertNotIn(nonce, nonces)
            nonces.add(nonce)

    def test_nonce_single_use_anti_replay_guarantee(self):
        nonce = self.validator.generate_nonce(self.device_id, purpose="attestation")
        # First consumption must succeed
        ok, msg = self.validator.verify_and_consume_nonce(nonce, self.device_id, purpose="attestation")
        self.assertTrue(ok)
        self.assertEqual(msg, "NONCE_VALID")

        # Second consumption of the same nonce MUST be rejected as replay attack
        ok2, msg2 = self.validator.verify_and_consume_nonce(nonce, self.device_id, purpose="attestation")
        self.assertFalse(ok2)
        self.assertEqual(msg2, "NONCE_REPLAY_ATTACK_DETECTED")

    def test_nonce_device_mismatch_rejection(self):
        nonce = self.validator.generate_nonce("device_alpha")
        ok, msg = self.validator.verify_and_consume_nonce(nonce, "device_beta")
        self.assertFalse(ok)
        self.assertEqual(msg, "NONCE_DEVICE_MISMATCH")

    def test_nonce_expiration(self):
        nonce = self.validator.generate_nonce(self.device_id, ttl_seconds=-10)
        ok, msg = self.validator.verify_and_consume_nonce(nonce, self.device_id)
        self.assertFalse(ok)
        self.assertEqual(msg, "NONCE_EXPIRED")

    def test_unknown_nonce_rejection(self):
        ok, msg = self.validator.verify_and_consume_nonce("fake_unregistered_nonce_hex", self.device_id)
        self.assertFalse(ok)
        self.assertEqual(msg, "UNKNOWN_OR_EXPIRED_NONCE")

    def test_device_key_registration_and_retrieval(self):
        reg = self.validator.register_device_attestation(
            device_id=self.device_id,
            security_level="STRONGBOX",
            is_hardware_backed=True,
            public_key_pem="MFkwEwYHKoZIzj0CAQYIKoZIzj0DAQcDQgAE998877",
            key_alias="focus_dns_strongbox_key_v1",
            cert_chain=["cert1_base64", "cert2_base64", "google_root_ca"],
        )
        self.assertEqual(reg["device_id"], self.device_id)
        self.assertEqual(reg["security_level"], "STRONGBOX")
        self.assertEqual(reg["cert_chain_depth"], 3)

        retrieved = self.validator.get_device_attestation(self.device_id)
        self.assertIsNotNone(retrieved)
        self.assertEqual(retrieved["key_alias"], "focus_dns_strongbox_key_v1")

    def test_verify_assertion_success(self):
        nonce = self.validator.generate_nonce(self.device_id)
        sig = base64.b64encode(b"\x30\x45\x02\x20valid_dummy_sig_bytes_here_1234567890\x02\x20second_half").decode("utf-8")
        now_ms = int(time.time() * 1000)

        result = self.validator.verify_assertion(
            device_id=self.device_id,
            payload="STATE_UNINSTALL_LOCKED_FOCUS_MODE",
            nonce=nonce,
            signature_base64=sig,
            timestamp_ms=now_ms,
        )

        self.assertTrue(result.is_valid)
        self.assertEqual(result.security_level, "TRUSTED_EXECUTION_ENVIRONMENT")
        self.assertTrue(result.is_hardware_backed)
        self.assertEqual(result.details["payload"], "STATE_UNINSTALL_LOCKED_FOCUS_MODE")

    def test_verify_assertion_nonce_replay_fails(self):
        nonce = self.validator.generate_nonce(self.device_id)
        sig = base64.b64encode(b"\x30\x45\x02\x20valid_dummy_sig_bytes_here_1234567890\x02\x20second_half").decode("utf-8")
        now_ms = int(time.time() * 1000)

        # 1st assertion: succeeds
        res1 = self.validator.verify_assertion(self.device_id, "PAYLOAD_1", nonce, sig, now_ms)
        self.assertTrue(res1.is_valid)

        # 2nd assertion with reused nonce: fails
        res2 = self.validator.verify_assertion(self.device_id, "PAYLOAD_2", nonce, sig, now_ms)
        self.assertFalse(res2.is_valid)
        self.assertIn("NONCE_REPLAY_ATTACK_DETECTED", res2.error_message)

    def test_verify_assertion_clock_skew_fails(self):
        nonce = self.validator.generate_nonce(self.device_id)
        sig = base64.b64encode(b"\x30\x45\x02\x20valid_dummy_sig_bytes_here_1234567890\x02\x20second_half").decode("utf-8")
        stale_ms = int((time.time() - 3600) * 1000)  # 1 hour ago

        result = self.validator.verify_assertion(self.device_id, "PAYLOAD_1", nonce, sig, stale_ms)
        self.assertFalse(result.is_valid)
        self.assertIn("TIMESTAMP_OUT_OF_BOUNDS_CLOCK_SKEW", result.error_message)

    def test_verify_assertion_corrupt_signature_fails(self):
        nonce = self.validator.generate_nonce(self.device_id)
        now_ms = int(time.time() * 1000)

        result = self.validator.verify_assertion(self.device_id, "PAYLOAD_1", nonce, "NOT_BASE64!??", now_ms)
        self.assertFalse(result.is_valid)
        self.assertIn("CORRUPT_BASE64_SIGNATURE", result.error_message)

    def test_verify_assertion_too_short_signature_fails(self):
        nonce = self.validator.generate_nonce(self.device_id)
        now_ms = int(time.time() * 1000)
        short_sig = base64.b64encode(b"short").decode("utf-8")

        result = self.validator.verify_assertion(self.device_id, "PAYLOAD_1", nonce, short_sig, now_ms)
        self.assertFalse(result.is_valid)
        self.assertIn("INVALID_SIGNATURE_LENGTH", result.error_message)

    def test_multiple_devices_nonce_isolation(self):
        d1 = "pixel_device_001"
        d2 = "galaxy_device_002"
        n1 = self.validator.generate_nonce(d1)
        n2 = self.validator.generate_nonce(d2)

        self.assertNotEqual(n1, n2)
        # Device 1 cannot consume Device 2's nonce
        ok1, msg1 = self.validator.verify_and_consume_nonce(n2, d1)
        self.assertFalse(ok1)
        self.assertEqual(msg1, "NONCE_DEVICE_MISMATCH")

        # Device 2 consumes n2 successfully
        ok2, msg2 = self.validator.verify_and_consume_nonce(n2, d2)
        self.assertTrue(ok2)

    def test_nonce_purging_of_expired_records(self):
        # Create an expired nonce record
        old_nonce = "expired_nonce_sample_12345"
        rec = NonceRecord(
            nonce=old_nonce,
            device_id=self.device_id,
            challenge_purpose="attestation",
            ttl_seconds=-1000,
        )
        self.validator._nonce_store[old_nonce] = rec
        self.assertIn(old_nonce, self.validator._nonce_store)

        # Trigger clean
        self.validator._clean_expired_nonces()
        self.assertNotIn(old_nonce, self.validator._nonce_store)

    def test_nonce_record_attributes(self):
        rec = NonceRecord(
            nonce="valid_nonce_abc",
            device_id="dev_1",
            challenge_purpose="custom_challenge",
            ttl_seconds=60,
        )
        self.assertTrue(rec.is_valid())
        self.assertEqual(rec.challenge_purpose, "custom_challenge")
        rec.consumed = True
        self.assertFalse(rec.is_valid())


if __name__ == "__main__":
    unittest.main()
