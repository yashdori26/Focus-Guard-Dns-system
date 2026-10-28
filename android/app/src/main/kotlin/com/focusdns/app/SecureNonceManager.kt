package com.focusdns.app

import java.security.SecureRandom
import java.util.concurrent.ConcurrentHashMap
import javax.crypto.Mac
import javax.crypto.spec.SecretKeySpec

/**
 * SecureNonceManager
 * ==================
 * Cryptographic Anti-Replay Nonce Engine for FocusDNS.
 *
 * Prevents replay attacks where an attacker captures a valid signed "Session Ended"
 * or "Uninstall Allowed" payload from a prior idle session and replays it while
 * a strict focus timer is currently running.
 *
 * Features:
 * - CSPRNG 256-bit entropy generation via SecureRandom.
 * - Single-use nonce consumption semantics.
 * - Automatic expiration window (TTL default: 300 seconds).
 * - HMAC-SHA256 signature verification for client-server attestation sync.
 */
object SecureNonceManager {

    private const val NONCE_BYTES = 32
    private const val DEFAULT_TTL_MS = 300_000L // 5 minutes

    data class NonceRecord(
        val nonce: String,
        val createdAtMs: Long,
        val ttlMs: Long,
        var isConsumed: Boolean = false
    )

    private val secureRandom = SecureRandom()
    private val activeNonces = ConcurrentHashMap<String, NonceRecord>()

    /**
     * Generates a fresh cryptographic 256-bit nonce with expiration TTL.
     */
    fun generateNonce(ttlMs: Long = DEFAULT_TTL_MS): String {
        pruneExpired()
        val bytes = ByteArray(NONCE_BYTES)
        secureRandom.nextBytes(bytes)
        val nonceHex = bytes.joinToString("") { "%02x".format(it) }

        val record = NonceRecord(
            nonce = nonceHex,
            createdAtMs = System.currentTimeMillis(),
            ttlMs = ttlMs,
            isConsumed = false
        )
        activeNonces[nonceHex] = record
        return nonceHex
    }

    /**
     * Validates and immediately consumes a nonce.
     * Returns true ONLY if the nonce exists, has not expired, and has NOT been consumed before.
     */
    fun validateAndConsume(nonce: String): Pair<Boolean, String> {
        val record = activeNonces[nonce] ?: return Pair(false, "NONCE_NOT_FOUND")

        val now = System.currentTimeMillis()
        if (now - record.createdAtMs > record.ttlMs) {
            activeNonces.remove(nonce)
            return Pair(false, "NONCE_EXPIRED")
        }

        synchronized(record) {
            if (record.isConsumed) {
                return Pair(false, "NONCE_ALREADY_REPLAYED")
            }
            record.isConsumed = true
        }

        // Keep consumed record for anti-replay window, will be pruned upon expiration
        return Pair(true, "VALID")
    }

    /**
     * Computes an HMAC-SHA256 signature of a payload bound to a specific nonce.
     */
    fun signWithNonce(payload: String, nonce: String, secretKey: ByteArray): String {
        val mac = Mac.getInstance("HmacSHA256")
        mac.init(SecretKeySpec(secretKey, "HmacSHA256"))
        val data = "$nonce:$payload".toByteArray(Charsets.UTF_8)
        val hash = mac.doFinal(data)
        return hash.joinToString("") { "%02x".format(it) }
    }

    /**
     * Verifies that a signed payload matches the expected signature bound to the nonce.
     */
    fun verifyWithNonce(
        payload: String,
        nonce: String,
        signature: String,
        secretKey: ByteArray
    ): Boolean {
        val expected = signWithNonce(payload, nonce, secretKey)
        // Constant-time string comparison to prevent timing attacks
        return MessageDigestUtils.constantTimeEquals(expected, signature)
    }

    /**
     * Prunes expired nonces from memory.
     */
    fun pruneExpired() {
        val now = System.currentTimeMillis()
        val it = activeNonces.entries.iterator()
        while (it.hasNext()) {
            val entry = it.next()
            if (now - entry.value.createdAtMs > entry.value.ttlMs) {
                it.remove()
            }
        }
    }

    /**
     * Clears all nonces (for testing and session resets).
     */
    fun clearAll() {
        activeNonces.clear()
    }

    /**
     * Returns count of currently tracked nonces.
     */
    fun activeCount(): Int = activeNonces.size
}

/**
 * Utility for constant-time cryptographic equality checks.
 */
object MessageDigestUtils {
    fun constantTimeEquals(a: String, b: String): Boolean {
        if (a.length != b.length) return false
        var result = 0
        for (i in a.indices) {
            result = result or (a[i].code xor b[i].code)
        }
        return result == 0
    }
}
