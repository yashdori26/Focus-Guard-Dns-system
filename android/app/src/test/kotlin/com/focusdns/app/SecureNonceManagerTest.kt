package com.focusdns.app

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test

/**
 * Unit tests for SecureNonceManager verifying anti-replay guarantees,
 * single-use consumption semantics, and cryptographic signature binding.
 */
class SecureNonceManagerTest {

    @Before
    fun setUp() {
        SecureNonceManager.clearAll()
    }

    @Test
    fun testGenerateNonce_returnsUnique64HexStrings() {
        val n1 = SecureNonceManager.generateNonce()
        val n2 = SecureNonceManager.generateNonce()
        assertEquals(64, n1.length)
        assertEquals(64, n2.length)
        assertNotEquals(n1, n2)
        assertEquals(2, SecureNonceManager.activeCount())
    }

    @Test
    fun testValidateAndConsume_singleUseSemantics() {
        val nonce = SecureNonceManager.generateNonce()

        // 1. First consumption must succeed
        val (valid1, reason1) = SecureNonceManager.validateAndConsume(nonce)
        assertTrue("Fresh nonce must be valid on first consumption", valid1)
        assertEquals("VALID", reason1)

        // 2. Second consumption (replay attack attempt) must be rejected
        val (valid2, reason2) = SecureNonceManager.validateAndConsume(nonce)
        assertFalse("Replaying the same nonce must be rejected", valid2)
        assertEquals("NONCE_ALREADY_REPLAYED", reason2)
    }

    @Test
    fun testValidateAndConsume_notFound() {
        val (valid, reason) = SecureNonceManager.validateAndConsume("0000000000000000000000000000000000000000000000000000000000000000")
        assertFalse(valid)
        assertEquals("NONCE_NOT_FOUND", reason)
    }

    @Test
    fun testSignAndVerifyWithNonce_validSignature() {
        val key = "super-secret-focus-key-32bytes!".toByteArray(Charsets.UTF_8)
        val nonce = SecureNonceManager.generateNonce()
        val payload = "action=START_FOCUS:timer=1800:device_admin=1"

        val signature = SecureNonceManager.signWithNonce(payload, nonce, key)
        assertEquals(64, signature.length)

        val verified = SecureNonceManager.verifyWithNonce(payload, nonce, signature, key)
        assertTrue("Signature matching payload, nonce, and key must verify", verified)
    }

    @Test
    fun testSignAndVerifyWithNonce_detectsTampering() {
        val key = "secret-key-for-anti-replay-tests".toByteArray(Charsets.UTF_8)
        val nonce = SecureNonceManager.generateNonce()
        val payload = "action=START_FOCUS:timer=1800"

        val signature = SecureNonceManager.signWithNonce(payload, nonce, key)

        // Tampering with payload
        val tamperedPayload = "action=END_FOCUS:timer=0"
        assertFalse(SecureNonceManager.verifyWithNonce(tamperedPayload, nonce, signature, key))

        // Tampering with nonce
        val otherNonce = SecureNonceManager.generateNonce()
        assertFalse(SecureNonceManager.verifyWithNonce(payload, otherNonce, signature, key))

        // Tampering with key
        val wrongKey = "wrong-secret-key-32bytes-length!".toByteArray(Charsets.UTF_8)
        assertFalse(SecureNonceManager.verifyWithNonce(payload, nonce, signature, wrongKey))
    }

    @Test
    fun testConstantTimeEquals() {
        assertTrue(MessageDigestUtils.constantTimeEquals("abcdef123456", "abcdef123456"))
        assertFalse(MessageDigestUtils.constantTimeEquals("abcdef123456", "abcdef123457"))
        assertFalse(MessageDigestUtils.constantTimeEquals("short", "longer_string"))
    }
}
