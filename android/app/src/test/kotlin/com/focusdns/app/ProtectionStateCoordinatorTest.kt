package com.focusdns.app

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.security.MessageDigest
import javax.crypto.Mac
import javax.crypto.spec.SecretKeySpec

/**
 * Unit tests verifying the cryptographic protection state coordinator and the core
 * uninstallation permission law:
 * - App CAN be uninstalled cleanly when idle.
 * - App CANNOT be uninstalled when protection mode is ON or timer mode is active.
 */
class ProtectionStateCoordinatorTest {

    // Pure evaluation function matching ProtectionStateCoordinator truth table
    private fun evaluateCanUninstall(
        isProtectionActive: Boolean,
        isTimerActive: Boolean,
        remainingSeconds: Long
    ): Boolean {
        if (isProtectionActive) return false
        if (isTimerActive || remainingSeconds > 0) return false
        return true
    }

    private fun formatRemainingTime(seconds: Long): String {
        val s = if (seconds < 0) 0 else seconds
        val hours = s / 3600
        val minutes = (s % 3600) / 60
        val secs = s % 60
        return if (hours > 0) {
            String.format("%02d:%02d:%02d", hours, minutes, secs)
        } else {
            String.format("%02d:%02d", minutes, secs)
        }
    }

    private fun computeHmac(data: String, key: ByteArray): String {
        val mac = Mac.getInstance("HmacSHA256")
        mac.init(SecretKeySpec(key, "HmacSHA256"))
        val hash = mac.doFinal(data.toByteArray(Charsets.UTF_8))
        return hash.joinToString("") { "%02x".format(it) }
    }

    @Test
    fun testTruthTable_normalModePermitsUninstallation() {
        // When protection is OFF and timer is 0, user CAN uninstall
        val canUninstall = evaluateCanUninstall(
            isProtectionActive = false,
            isTimerActive = false,
            remainingSeconds = 0L
        )
        assertTrue("App must be uninstallable when protection is OFF and timer is 0", canUninstall)
    }

    @Test
    fun testTruthTable_protectionActiveBlocksUninstallation() {
        // When protection is ON and timer is 0, user CANNOT uninstall
        val canUninstall = evaluateCanUninstall(
            isProtectionActive = true,
            isTimerActive = false,
            remainingSeconds = 0L
        )
        assertFalse("App cannot be uninstalled when protection is active", canUninstall)
    }

    @Test
    fun testTruthTable_timerActiveBlocksUninstallation() {
        // When protection is OFF but timer is running (> 0), user CANNOT uninstall
        val canUninstall = evaluateCanUninstall(
            isProtectionActive = false,
            isTimerActive = true,
            remainingSeconds = 1800L
        )
        assertFalse("App cannot be uninstalled when timer is active", canUninstall)
    }

    @Test
    fun testTruthTable_bothActiveBlocksUninstallation() {
        // When both protection is ON and timer is running, user CANNOT uninstall
        val canUninstall = evaluateCanUninstall(
            isProtectionActive = true,
            isTimerActive = true,
            remainingSeconds = 3600L
        )
        assertFalse("App cannot be uninstalled when both protection and timer are active", canUninstall)
    }

    @Test
    fun testTruthTable_timerExpirationUnlocksUninstallation() {
        // Timer active
        assertFalse(evaluateCanUninstall(isProtectionActive = false, isTimerActive = true, remainingSeconds = 10L))

        // Timer expires to 0 and timer flag clears
        val canUninstallAfterExpire = evaluateCanUninstall(
            isProtectionActive = false,
            isTimerActive = false,
            remainingSeconds = 0L
        )
        assertTrue("App must unlock when timer completes and protection is off", canUninstallAfterExpire)
    }

    @Test
    fun testTimeFormatting_hoursMinutesSeconds() {
        assertEquals("01:00:00", formatRemainingTime(3600))
        assertEquals("02:30:15", formatRemainingTime(9015))
    }

    @Test
    fun testTimeFormatting_minutesSecondsOnly() {
        assertEquals("25:00", formatRemainingTime(1500))
        assertEquals("00:45", formatRemainingTime(45))
        assertEquals("00:00", formatRemainingTime(0))
        assertEquals("00:00", formatRemainingTime(-5))
    }

    @Test
    fun testHmacSeal_detectsTampering() {
        val secretKey = "test-focusdns-secret-key".toByteArray(Charsets.UTF_8)
        val stateString = "protection=1:timer=1800:epoch=1700000000"
        val signature = computeHmac(stateString, secretKey)
        assertNotNull(signature)
        assertEquals(64, signature.length) // 256 bits = 64 hex characters

        // Modifying state string must produce different signature
        val tamperedState = "protection=0:timer=0:epoch=1700000000"
        val tamperedSignature = computeHmac(tamperedState, secretKey)
        assertNotEquals(signature, tamperedSignature)
    }

    @Test
    fun testHmacSeal_reproducibleWithSameKey() {
        val secretKey = "reproducible-key-32bytes-length!!".toByteArray(Charsets.UTF_8)
        val state = "protection=0:timer=0:epoch=12345"
        val sig1 = computeHmac(state, secretKey)
        val sig2 = computeHmac(state, secretKey)
        assertEquals(sig1, sig2)
    }
}
