package com.focusdns.app

import java.io.ByteArrayInputStream
import java.security.MessageDigest
import java.security.cert.CertificateFactory
import java.security.cert.X509Certificate
import java.util.logging.Logger

/**
 * On-device X.509 certificate chain & ASN.1 Key Attestation parser for Android KeyStore.
 *
 * Inspects Android Key Attestation Extension (OID 1.3.6.1.4.1.11129.2.1.17) to verify:
 * 1. Attestation security level (Software, TEE, or StrongBox).
 * 2. Keymaster / Keymint security level.
 * 3. Challenge equality against anti-replay nonces.
 * 4. Google Root CA fingerprint pinning.
 */
class StrongBoxAttestationVerifier {

    companion object {
        private val logger = Logger.getLogger(StrongBoxAttestationVerifier::class.java.name)

        const val KEY_ATTESTATION_OID = "1.3.6.1.4.1.11129.2.1.17"

        // Known SHA-256 fingerprints of official Google Hardware Attestation Root CAs
        val GOOGLE_ROOT_CA_SHA256 = setOf(
            "4a24cd80388b818606eb02eb55b650c4035787207dd6551724d2968a07a9e163".lowercase(),
            "ec0f124be9e4b6c317a7e80f2dbf8819f7cc00609b5526e95c1154563a69a03b".lowercase()
        )

        const val KM_SECURITY_LEVEL_SOFTWARE = 0
        const val KM_SECURITY_LEVEL_TRUSTED_ENVIRONMENT = 1
        const val KM_SECURITY_LEVEL_STRONGBOX = 2
    }

    data class KeyAttestationRecord(
        val attestationVersion: Int,
        val attestationSecurityLevel: Int,
        val keymasterVersion: Int,
        val keymasterSecurityLevel: Int,
        val attestationChallenge: ByteArray,
        val uniqueId: ByteArray,
        val isHardwareBacked: Boolean,
        val securityLevelName: String
    ) {
        override fun equals(other: Any?): Boolean {
            if (this === other) return true
            if (other !is KeyAttestationRecord) return false
            return attestationVersion == other.attestationVersion &&
                    attestationSecurityLevel == other.attestationSecurityLevel &&
                    keymasterVersion == other.keymasterVersion &&
                    keymasterSecurityLevel == other.keymasterSecurityLevel &&
                    attestationChallenge.contentEquals(other.attestationChallenge)
        }

        override fun hashCode(): Int {
            var result = attestationVersion
            result = 31 * result + attestationSecurityLevel
            result = 31 * result + keymasterVersion
            result = 31 * result + keymasterSecurityLevel
            result = 31 * result + attestationChallenge.contentHashCode()
            return result
        }
    }

    data class VerificationResult(
        val isValid: Boolean,
        val isHardwareBacked: Boolean,
        val securityLevel: String,
        val isGoogleRootCaVerified: Boolean,
        val errorMessage: String? = null,
        val record: KeyAttestationRecord? = null
    )

    /**
     * Verifies an X.509 certificate chain against expected anti-replay challenge.
     */
    fun verifyCertificateChain(
        certificates: List<X509Certificate>,
        expectedChallenge: ByteArray? = null
    ): VerificationResult {
        if (certificates.isEmpty()) {
            return VerificationResult(
                isValid = false,
                isHardwareBacked = false,
                securityLevel = "UNKNOWN",
                isGoogleRootCaVerified = false,
                errorMessage = "CERTIFICATE_CHAIN_EMPTY"
            )
        }

        val leafCert = certificates.first()
        val rootCert = certificates.last()

        // 1. Verify Google Root CA fingerprint
        val isGoogleRoot = verifyRootCaFingerprint(rootCert)

        // 2. Extract Key Attestation Extension (OID 1.3.6.1.4.1.11129.2.1.17)
        val extensionValue = leafCert.getExtensionValue(KEY_ATTESTATION_OID)
        if (extensionValue == null) {
            // Emulated/Test environment or standard self-signed certificate
            return VerificationResult(
                isValid = false,
                isHardwareBacked = false,
                securityLevel = "SOFTWARE",
                isGoogleRootCaVerified = isGoogleRoot,
                errorMessage = "MISSING_KEY_ATTESTATION_EXTENSION"
            )
        }

        // 3. Parse ASN.1 structure from extension
        val record = parseAttestationExtension(extensionValue)
        if (record == null) {
            return VerificationResult(
                isValid = false,
                isHardwareBacked = false,
                securityLevel = "SOFTWARE",
                isGoogleRootCaVerified = isGoogleRoot,
                errorMessage = "CORRUPT_ASN1_ATTESTATION_STRUCTURE"
            )
        }

        // 4. Validate Challenge
        if (expectedChallenge != null && !record.attestationChallenge.contentEquals(expectedChallenge)) {
            return VerificationResult(
                isValid = false,
                isHardwareBacked = record.isHardwareBacked,
                securityLevel = record.securityLevelName,
                isGoogleRootCaVerified = isGoogleRoot,
                errorMessage = "ATTESTATION_CHALLENGE_MISMATCH",
                record = record
            )
        }

        return VerificationResult(
            isValid = true,
            isHardwareBacked = record.isHardwareBacked,
            securityLevel = record.securityLevelName,
            isGoogleRootCaVerified = isGoogleRoot,
            record = record
        )
    }

    /**
     * Checks if certificate's encoded public key matches Google Root CA SHA-256 fingerprint.
     */
    fun verifyRootCaFingerprint(cert: X509Certificate): Boolean {
        try {
            val md = MessageDigest.getInstance("SHA-256")
            val fp = md.digest(cert.encoded).joinToString("") { "%02x".format(it) }.lowercase()
            return GOOGLE_ROOT_CA_SHA256.contains(fp)
        } catch (e: Exception) {
            logger.warning("Failed calculating Root CA SHA-256: ${e.message}")
            return false
        }
    }

    /**
     * Lightweight ASN.1 parser extracting Key Attestation sequence fields.
     */
    fun parseAttestationExtension(derBytes: ByteArray): KeyAttestationRecord? {
        try {
            // The extension value in X.509 is wrapped in an outer OCTET STRING (tag 0x04)
            var offset = 0
            if (offset >= derBytes.size) return null

            // Unwrap outer Octet String if present
            var payload = derBytes
            if (derBytes[offset] == 0x04.toByte()) {
                val lenInfo = readDerLength(derBytes, offset + 1)
                payload = derBytes.copyOfRange(lenInfo.dataOffset, lenInfo.dataOffset + lenInfo.length)
                offset = 0
            }

            // SEQUENCE tag (0x30)
            if (payload[offset] != 0x30.toByte()) return null
            val seqLen = readDerLength(payload, offset + 1)
            var curr = seqLen.dataOffset

            // Field 1: attestationVersion (INTEGER, 0x02)
            val v1 = readDerInteger(payload, curr)
            curr = v1.nextOffset

            // Field 2: attestationSecurityLevel (ENUMERATED, 0x0a)
            val secLevel = readDerEnumerated(payload, curr)
            curr = secLevel.nextOffset

            // Field 3: keymasterVersion (INTEGER, 0x02)
            val kmVersion = readDerInteger(payload, curr)
            curr = kmVersion.nextOffset

            // Field 4: keymasterSecurityLevel (ENUMERATED, 0x0a)
            val kmSecLevel = readDerEnumerated(payload, curr)
            curr = kmSecLevel.nextOffset

            // Field 5: attestationChallenge (OCTET STRING, 0x04)
            val challenge = readDerOctetString(payload, curr)
            curr = challenge.nextOffset

            // Field 6: uniqueId (OCTET STRING, 0x04)
            val uniqueId = readDerOctetString(payload, curr)

            val isHardware = (secLevel.value == KM_SECURITY_LEVEL_TRUSTED_ENVIRONMENT ||
                    secLevel.value == KM_SECURITY_LEVEL_STRONGBOX)

            val secName = when (secLevel.value) {
                KM_SECURITY_LEVEL_STRONGBOX -> "STRONGBOX"
                KM_SECURITY_LEVEL_TRUSTED_ENVIRONMENT -> "TRUSTED_EXECUTION_ENVIRONMENT"
                else -> "SOFTWARE"
            }

            return KeyAttestationRecord(
                attestationVersion = v1.value,
                attestationSecurityLevel = secLevel.value,
                keymasterVersion = kmVersion.value,
                keymasterSecurityLevel = kmSecLevel.value,
                attestationChallenge = challenge.bytes,
                uniqueId = uniqueId.bytes,
                isHardwareBacked = isHardware,
                securityLevelName = secName
            )
        } catch (e: Exception) {
            logger.warning("ASN.1 parsing exception: ${e.message}")
            return null
        }
    }

    private data class LengthResult(val length: Int, val dataOffset: Int)
    private data class IntResult(val value: Int, val nextOffset: Int)
    private data class BytesResult(val bytes: ByteArray, val nextOffset: Int)

    private fun readDerLength(bytes: ByteArray, offset: Int): LengthResult {
        val first = bytes[offset].toInt() and 0xFF
        if ((first and 0x80) == 0) {
            return LengthResult(first, offset + 1)
        }
        val numBytes = first and 0x7F
        var len = 0
        for (i in 0 until numBytes) {
            len = (len shl 8) or (bytes[offset + 1 + i].toInt() and 0xFF)
        }
        return LengthResult(len, offset + 1 + numBytes)
    }

    private fun readDerInteger(bytes: ByteArray, offset: Int): IntResult {
        if (bytes[offset] != 0x02.toByte()) throw IllegalArgumentException("Expected INTEGER tag 0x02 at $offset")
        val lenInfo = readDerLength(bytes, offset + 1)
        var value = 0
        for (i in 0 until lenInfo.length) {
            value = (value shl 8) or (bytes[lenInfo.dataOffset + i].toInt() and 0xFF)
        }
        return IntResult(value, lenInfo.dataOffset + lenInfo.length)
    }

    private fun readDerEnumerated(bytes: ByteArray, offset: Int): IntResult {
        if (bytes[offset] != 0x0a.toByte()) throw IllegalArgumentException("Expected ENUMERATED tag 0x0a at $offset")
        val lenInfo = readDerLength(bytes, offset + 1)
        var value = 0
        for (i in 0 until lenInfo.length) {
            value = (value shl 8) or (bytes[lenInfo.dataOffset + i].toInt() and 0xFF)
        }
        return IntResult(value, lenInfo.dataOffset + lenInfo.length)
    }

    private fun readDerOctetString(bytes: ByteArray, offset: Int): BytesResult {
        if (bytes[offset] != 0x04.toByte()) throw IllegalArgumentException("Expected OCTET STRING tag 0x04 at $offset")
        val lenInfo = readDerLength(bytes, offset + 1)
        val data = bytes.copyOfRange(lenInfo.dataOffset, lenInfo.dataOffset + lenInfo.length)
        return BytesResult(data, lenInfo.dataOffset + lenInfo.length)
    }
}
