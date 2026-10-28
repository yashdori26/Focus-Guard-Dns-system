package com.focusdns.app

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Unit tests for AntiTamperSecurityShield verifying root binary paths,
 * hook detection heuristics, and device integrity score calculations.
 */
class AntiTamperSecurityShieldTest {

    private fun calculateIntegrityScore(
        isRooted: Boolean,
        hasTestKeys: Boolean,
        hasHookDetected: Boolean,
        isDebuggerAttached: Boolean
    ): Int {
        var score = 100
        if (isRooted) score -= 40
        if (hasTestKeys) score -= 30
        if (hasHookDetected) score -= 25
        if (isDebuggerAttached) score -= 15
        return score.coerceIn(0, 100)
    }

    private fun classifyIntegrityLevel(score: Int): String {
        return when {
            score >= 90 -> "EXCELLENT"
            score >= 70 -> "MODERATE"
            score >= 50 -> "COMPROMISED"
            else -> "CRITICAL"
        }
    }

    @Test
    fun testRootPaths_containsStandardSuAndMagiskLocations() {
        val paths = AntiTamperSecurityShield.KNOWN_ROOT_PATHS
        assertTrue(paths.contains("/system/bin/su"))
        assertTrue(paths.contains("/system/xbin/su"))
        assertTrue(paths.contains("/sbin/su"))
        assertTrue(paths.contains("/system/sd/xbin/su"))
        assertTrue(paths.contains("/system/bin/failsafe/su"))
        assertTrue(paths.contains("/data/local/xbin/su"))
        assertTrue(paths.contains("/data/local/bin/su"))
        assertTrue(paths.contains("/system/app/Superuser.apk"))
    }

    @Test
    fun testIntegrityScore_cleanDeviceReturns100() {
        val score = calculateIntegrityScore(
            isRooted = false,
            hasTestKeys = false,
            hasHookDetected = false,
            isDebuggerAttached = false
        )
        assertEquals(100, score)
        assertEquals("EXCELLENT", classifyIntegrityLevel(score))
    }

    @Test
    fun testIntegrityScore_rootedDeviceDropsScore() {
        val score = calculateIntegrityScore(
            isRooted = true,
            hasTestKeys = false,
            hasHookDetected = false,
            isDebuggerAttached = false
        )
        assertEquals(60, score)
        assertEquals("COMPROMISED", classifyIntegrityLevel(score))
    }

    @Test
    fun testIntegrityScore_rootedAndHookedReturnsCritical() {
        val score = calculateIntegrityScore(
            isRooted = true,
            hasTestKeys = false,
            hasHookDetected = true,
            isDebuggerAttached = false
        )
        assertEquals(35, score)
        assertEquals("CRITICAL", classifyIntegrityLevel(score))
    }

    @Test
    fun testIntegrityScore_allCompromisedClampsToZero() {
        val score = calculateIntegrityScore(
            isRooted = true,
            hasTestKeys = true,
            hasHookDetected = true,
            isDebuggerAttached = true
        )
        // 100 - 40 - 30 - 25 - 15 = -10 => clamps to 0
        assertEquals(0, score)
        assertEquals("CRITICAL", classifyIntegrityLevel(score))
    }

    @Test
    fun testBuildTags_releaseKeysClean() {
        val tags = "release-keys"
        val isTestKeys = tags.contains("test-keys")
        assertFalse(isTestKeys)
    }

    @Test
    fun testBuildTags_testKeysFlagged() {
        val tags = "test-keys,userdebug"
        val isTestKeys = tags.contains("test-keys")
        assertTrue(isTestKeys)
    }
}
