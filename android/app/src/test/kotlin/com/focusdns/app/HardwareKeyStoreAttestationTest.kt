package com.focusdns.app

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.security.KeyPairGenerator
import java.security.Signature
import java.security.spec.ECGenParameterSpec

/**
 * Unit tests for HardwareKeyStoreAttestation verifying EC keypair generation,
 * ECDSA SHA-256 signature generation and cryptographic verification.
 */
class HardwareKeyStoreAttestationTest {

    @Test
    fun testKeyPairGeneration_ecP256() {
        val kpg = KeyPairGenerator.getInstance("EC")
        kpg.initialize(ECGenParameterSpec("secp256r1"))
        val keyPair = kpg.generateKeyPair()

        assertNotNull(keyPair.public)
        assertNotNull(keyPair.private)
        assertEquals("EC", keyPair.public.algorithm)
        assertEquals("EC", keyPair.private.algorithm)
    }

    @Test
    fun testSignAndVerify_roundTrip() {
        val kpg = KeyPairGenerator.getInstance("EC")
        kpg.initialize(ECGenParameterSpec("secp256r1"))
        val keyPair = kpg.generateKeyPair()

        val payload = "device_id=pixel-999:can_uninstall=false:timer_remaining=1200"
        val nonce = "7a8b9c0d1e2f3a4b5c6d7e8f9a0b1c2d3e4f5a6b7c8d9e0f1a2b3c4d5e6f7a8b"
        val dataToSign = "$nonce:$payload".toByteArray(Charsets.UTF_8)

        // Sign
        val signer = Signature.getInstance("SHA256withECDSA")
        signer.initSign(keyPair.private)
        signer.update(dataToSign)
        val signatureBytes = signer.sign()
        assertTrue("Signature bytes must not be empty", signatureBytes.isNotEmpty())

        // Verify
        val verifier = Signature.getInstance("SHA256withECDSA")
        verifier.initVerify(keyPair.public)
        verifier.update(dataToSign)
        val verified = verifier.verify(signatureBytes)
        assertTrue("Valid ECDSA signature must verify", verified)
    }

    @Test
    fun testSignAndVerify_tamperedPayloadFails() {
        val kpg = KeyPairGenerator.getInstance("EC")
        kpg.initialize(ECGenParameterSpec("secp256r1"))
        val keyPair = kpg.generateKeyPair()

        val originalPayload = "can_uninstall=false"
        val nonce = "nonce12345"
        val dataToSign = "$nonce:$originalPayload".toByteArray(Charsets.UTF_8)

        val signer = Signature.getInstance("SHA256withECDSA")
        signer.initSign(keyPair.private)
        signer.update(dataToSign)
        val signatureBytes = signer.sign()

        // Attempt to verify against tampered payload "can_uninstall=true"
        val tamperedData = "$nonce:can_uninstall=true".toByteArray(Charsets.UTF_8)
        val verifier = Signature.getInstance("SHA256withECDSA")
        verifier.initVerify(keyPair.public)
        verifier.update(tamperedData)
        val verified = verifier.verify(signatureBytes)
        assertFalse("Tampered payload must fail signature verification", verified)
    }

    @Test
    fun testSignAndVerify_tamperedNonceFails() {
        val kpg = KeyPairGenerator.getInstance("EC")
        kpg.initialize(ECGenParameterSpec("secp256r1"))
        val keyPair = kpg.generateKeyPair()

        val payload = "can_uninstall=false"
        val nonce1 = "nonce_original"
        val signer = Signature.getInstance("SHA256withECDSA")
        signer.initSign(keyPair.private)
        signer.update("$nonce1:$payload".toByteArray(Charsets.UTF_8))
        val sig = signer.sign()

        val nonce2 = "nonce_replayed"
        val verifier = Signature.getInstance("SHA256withECDSA")
        verifier.initVerify(keyPair.public)
        verifier.update("$nonce2:$payload".toByteArray(Charsets.UTF_8))
        assertFalse(verifier.verify(sig))
    }

    @Test
    fun testInspectAttestation_simulationStructure() {
        val att = HardwareKeyStoreAttestation.inspectAttestation()
        assertNotNull(att)
        assertEquals(HardwareKeyStoreAttestation.KEY_ALIAS_FOCUS_GUARD, att.alias)
        assertNotNull(att.securityLevel)
    }
}
