package com.focusdns.app

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Unit tests for PrivateDnsProtectionGuard verifying mode parsing,
 * DoT bypass detection, and compliance evaluation.
 */
class PrivateDnsProtectionGuardTest {

    @Test
    fun testParseMode_standardValues() {
        assertEquals(PrivateDnsProtectionGuard.PrivateDnsMode.OFF, PrivateDnsProtectionGuard.parseMode("off"))
        assertEquals(PrivateDnsProtectionGuard.PrivateDnsMode.OFF, PrivateDnsProtectionGuard.parseMode("OFF "))
        assertEquals(PrivateDnsProtectionGuard.PrivateDnsMode.OPPORTUNISTIC, PrivateDnsProtectionGuard.parseMode("opportunistic"))
        assertEquals(PrivateDnsProtectionGuard.PrivateDnsMode.STRICT_HOSTNAME, PrivateDnsProtectionGuard.parseMode("hostname"))
        assertEquals(PrivateDnsProtectionGuard.PrivateDnsMode.UNKNOWN, PrivateDnsProtectionGuard.parseMode("custom_bogus_mode"))
        assertEquals(PrivateDnsProtectionGuard.PrivateDnsMode.UNKNOWN, PrivateDnsProtectionGuard.parseMode(null))
    }

    @Test
    fun testEvaluateCompliance_idleVpnPermitsAnyMode() {
        // When VPN is idle, user can configure whatever Private DNS they wish
        val (compliant1, _) = PrivateDnsProtectionGuard.evaluateCompliance(
            mode = PrivateDnsProtectionGuard.PrivateDnsMode.STRICT_HOSTNAME,
            specifier = "dns.google",
            isVpnActive = false,
            isProtectionActive = false
        )
        assertTrue(compliant1)

        val (compliant2, _) = PrivateDnsProtectionGuard.evaluateCompliance(
            mode = PrivateDnsProtectionGuard.PrivateDnsMode.OFF,
            specifier = "",
            isVpnActive = false,
            isProtectionActive = false
        )
        assertTrue(compliant2)
    }

    @Test
    fun testEvaluateCompliance_activeProtectionWithOpportunisticModeIsCompliant() {
        val (compliant, reason) = PrivateDnsProtectionGuard.evaluateCompliance(
            mode = PrivateDnsProtectionGuard.PrivateDnsMode.OPPORTUNISTIC,
            specifier = "",
            isVpnActive = true,
            isProtectionActive = true
        )
        assertTrue(compliant)
        assertEquals("COMPLIANT", reason)
    }

    @Test
    fun testEvaluateCompliance_activeProtectionWithOffModeIsCompliant() {
        val (compliant, reason) = PrivateDnsProtectionGuard.evaluateCompliance(
            mode = PrivateDnsProtectionGuard.PrivateDnsMode.OFF,
            specifier = "",
            isVpnActive = true,
            isProtectionActive = true
        )
        assertTrue(compliant)
        assertEquals("COMPLIANT", reason)
    }

    @Test
    fun testEvaluateCompliance_activeProtectionWithStrictDoTBypassIsNonCompliant() {
        val (compliant, reason) = PrivateDnsProtectionGuard.evaluateCompliance(
            mode = PrivateDnsProtectionGuard.PrivateDnsMode.STRICT_HOSTNAME,
            specifier = "dns.google",
            isVpnActive = true,
            isProtectionActive = true
        )
        assertFalse(compliant)
        assertTrue(reason.contains("STRICT_DOT_BYPASS_DETECTED"))
        assertTrue(reason.contains("dns.google"))
    }

    @Test
    fun testKnownBypassHostnames_containsMajorPublicResolvers() {
        val set = PrivateDnsProtectionGuard.KNOWN_BYPASS_DOT_HOSTNAMES
        assertTrue(set.contains("dns.google"))
        assertTrue(set.contains("1dot1dot1dot1.cloudflare-dns.com"))
        assertTrue(set.contains("one.one.one.one"))
        assertTrue(set.contains("dns.quad9.net"))
        assertTrue(set.contains("dns.adguard.com"))
    }
}
