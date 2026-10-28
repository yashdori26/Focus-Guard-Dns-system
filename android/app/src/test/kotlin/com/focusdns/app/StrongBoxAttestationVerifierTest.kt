package com.focusdns.app

import org.junit.Assert.*
import org.junit.Before
import org.junit.Test
import java.io.ByteArrayOutputStream
import java.security.cert.X509Certificate

class StrongBoxAttestationVerifierTest {

    private lateinit var verifier: StrongBoxAttestationVerifier

    @Before
    fun setUp() {
        verifier = StrongBoxAttestationVerifier()
    }

    @Test
    fun testEmptyCertificateChainReturnsError() {
        val res = verifier.verifyCertificateChain(emptyList())
        assertFalse(res.isValid)
        assertEquals("CERTIFICATE_CHAIN_EMPTY", res.errorMessage)
    }

    @Test
    fun testParseAttestationExtensionStrongBoxRecord() {
        // Construct valid ASN.1 DER sequence:
        // SEQUENCE {
        //   INTEGER 3 (attestationVersion)
        //   ENUMERATED 2 (attestationSecurityLevel = StrongBox)
        //   INTEGER 4 (keymasterVersion)
        //   ENUMERATED 2 (keymasterSecurityLevel = StrongBox)
        //   OCTET STRING "test_challenge_1234"
        //   OCTET STRING "unique_id_xyz"
        // }
        val challengeBytes = "test_challenge_1234".toByteArray()
        val uniqueIdBytes = "unique_id_xyz".toByteArray()

        val derBytes = buildMockAttestationDer(
            attestationVersion = 3,
            attestationSecurityLevel = 2,
            keymasterVersion = 4,
            keymasterSecurityLevel = 2,
            challenge = challengeBytes,
            uniqueId = uniqueIdBytes
        )

        val record = verifier.parseAttestationExtension(derBytes)
        assertNotNull(record)
        assertEquals(3, record!!.attestationVersion)
        assertEquals(2, record.attestationSecurityLevel)
        assertEquals("STRONGBOX", record.securityLevelName)
        assertEquals(4, record.keymasterVersion)
        assertEquals(2, record.keymasterSecurityLevel)
        assertTrue(record.isHardwareBacked)
        assertArrayEquals(challengeBytes, record.attestationChallenge)
        assertArrayEquals(uniqueIdBytes, record.uniqueId)
    }

    @Test
    fun testParseAttestationExtensionTeeRecord() {
        val challengeBytes = "tee_challenge".toByteArray()
        val uniqueIdBytes = "tee_unique".toByteArray()

        val derBytes = buildMockAttestationDer(
            attestationVersion = 2,
            attestationSecurityLevel = 1, // TEE
            keymasterVersion = 3,
            keymasterSecurityLevel = 1, // TEE
            challenge = challengeBytes,
            uniqueId = uniqueIdBytes
        )

        val record = verifier.parseAttestationExtension(derBytes)
        assertNotNull(record)
        assertEquals(1, record!!.attestationSecurityLevel)
        assertEquals("TRUSTED_EXECUTION_ENVIRONMENT", record.securityLevelName)
        assertTrue(record.isHardwareBacked)
    }

    @Test
    fun testParseAttestationExtensionSoftwareRecord() {
        val derBytes = buildMockAttestationDer(
            attestationVersion = 1,
            attestationSecurityLevel = 0, // Software
            keymasterVersion = 2,
            keymasterSecurityLevel = 0, // Software
            challenge = "sw_challenge".toByteArray(),
            uniqueId = ByteArray(0)
        )

        val record = verifier.parseAttestationExtension(derBytes)
        assertNotNull(record)
        assertEquals(0, record!!.attestationSecurityLevel)
        assertEquals("SOFTWARE", record.securityLevelName)
        assertFalse(record.isHardwareBacked)
    }

    @Test
    fun testCorruptDerReturnsNull() {
        val garbage = byteArrayOf(0x01, 0x02, 0x03, 0x04)
        val record = verifier.parseAttestationExtension(garbage)
        assertNull(record)
    }

    @Test
    fun testGoogleRootCaKnownFingerprints() {
        assertTrue(StrongBoxAttestationVerifier.GOOGLE_ROOT_CA_SHA256.isNotEmpty())
        assertTrue(StrongBoxAttestationVerifier.GOOGLE_ROOT_CA_SHA256.contains(
            "4a24cd80388b818606eb02eb55b650c4035787207dd6551724d2968a07a9e163"
        ))
    }

    @Test
    fun testKeyAttestationRecordEqualityAndHash() {
        val rec1 = StrongBoxAttestationVerifier.KeyAttestationRecord(
            attestationVersion = 3,
            attestationSecurityLevel = 2,
            keymasterVersion = 4,
            keymasterSecurityLevel = 2,
            attestationChallenge = byteArrayOf(1, 2, 3),
            uniqueId = byteArrayOf(4, 5),
            isHardwareBacked = true,
            securityLevelName = "STRONGBOX"
        )
        val rec2 = StrongBoxAttestationVerifier.KeyAttestationRecord(
            attestationVersion = 3,
            attestationSecurityLevel = 2,
            keymasterVersion = 4,
            keymasterSecurityLevel = 2,
            attestationChallenge = byteArrayOf(1, 2, 3),
            uniqueId = byteArrayOf(4, 5),
            isHardwareBacked = true,
            securityLevelName = "STRONGBOX"
        )
        assertEquals(rec1, rec2)
        assertEquals(rec1.hashCode(), rec2.hashCode())
    }

    @Test
    fun testHardwareKeyStoreAttestationHelperVerification() {
        val result = HardwareKeyStoreAttestation.verifyAttestationWithStrongBoxVerifier(
            expectedChallenge = "test_challenge".toByteArray()
        )
        assertNotNull(result)
        assertNotNull(result.securityLevel)
    }

    // Helper to generate DER encoding
    private fun buildMockAttestationDer(
        attestationVersion: Int,
        attestationSecurityLevel: Int,
        keymasterVersion: Int,
        keymasterSecurityLevel: Int,
        challenge: ByteArray,
        uniqueId: ByteArray
    ): ByteArray {
        val inner = ByteArrayOutputStream()

        // 1. attestationVersion (INTEGER, 0x02)
        inner.write(0x02)
        inner.write(0x01)
        inner.write(attestationVersion)

        // 2. attestationSecurityLevel (ENUMERATED, 0x0a)
        inner.write(0x0a)
        inner.write(0x01)
        inner.write(attestationSecurityLevel)

        // 3. keymasterVersion (INTEGER, 0x02)
        inner.write(0x02)
        inner.write(0x01)
        inner.write(keymasterVersion)

        // 4. keymasterSecurityLevel (ENUMERATED, 0x0a)
        inner.write(0x0a)
        inner.write(0x01)
        inner.write(keymasterSecurityLevel)

        // 5. attestationChallenge (OCTET STRING, 0x04)
        inner.write(0x04)
        inner.write(challenge.size)
        inner.write(challenge)

        // 6. uniqueId (OCTET STRING, 0x04)
        inner.write(0x04)
        inner.write(uniqueId.size)
        inner.write(uniqueId)

        val innerBytes = inner.toByteArray()

        // Wrap in SEQUENCE (0x30)
        val seq = ByteArrayOutputStream()
        seq.write(0x30)
        seq.write(innerBytes.size)
        seq.write(innerBytes)

        val seqBytes = seq.toByteArray()

        // Wrap in outer OCTET STRING (0x04) as in X.509 extension value
        val outer = ByteArrayOutputStream()
        outer.write(0x04)
        outer.write(seqBytes.size)
        outer.write(seqBytes)

        return outer.toByteArray()
    }
}
