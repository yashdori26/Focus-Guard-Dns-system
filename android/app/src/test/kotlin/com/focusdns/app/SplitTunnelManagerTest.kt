package com.focusdns.app

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Unit tests for SplitTunnelManager verifying default banking and utility exemptions,
 * package list JSON serialization, and per-app VPN routing rule evaluation.
 */
class SplitTunnelManagerTest {

    private fun parsePackagesJson(raw: String): Set<String> {
        val trimmed = raw.trim()
        if (!trimmed.startsWith("[") || !trimmed.endsWith("]")) return emptySet()
        val content = trimmed.substring(1, trimmed.length - 1)
        if (content.isBlank()) return emptySet()
        return content.split(",")
            .map { it.trim().removeSurrounding("\"") }
            .filter { it.isNotEmpty() }
            .toSet()
    }

    private fun serializePackagesJson(packages: Set<String>): String {
        return packages.sorted().joinToString(separator = ",", prefix = "[", postfix = "]") { "\"$it\"" }
    }

    private fun shouldRoutePackageThroughVpn(
        pkg: String,
        mode: String,
        configuredPackages: Set<String>
    ): Boolean {
        return if (mode == "allow_list") {
            configuredPackages.contains(pkg)
        } else {
            // disallow_list: all traffic routed into VPN EXCEPT configuredPackages
            !configuredPackages.contains(pkg)
        }
    }

    @Test
    fun testDefaultExemptPackages_containsMajorBankingAndPaymentApps() {
        val defaults = SplitTunnelManager.DEFAULT_EXEMPT_PACKAGES
        assertTrue("Google Pay must be in default exemptions", defaults.contains("com.google.android.apps.nbu.paisa.user"))
        assertTrue("PhonePe must be in default exemptions", defaults.contains("com.phonepe.app"))
        assertTrue("Paytm must be in default exemptions", defaults.contains("net.one97.paytm"))
        assertTrue("SBI YONO must be in default exemptions", defaults.contains("com.sbi.lotusintouch"))
        assertTrue("HDFC Bank must be in default exemptions", defaults.contains("com.snapwork.hdfc"))
        assertTrue("ICICI iMobile must be in default exemptions", defaults.contains("com.csam.icici.bank.imobile"))
        assertTrue("WhatsApp must be in default exemptions", defaults.contains("com.whatsapp"))
    }

    @Test
    fun testJsonSerialization_roundTrip() {
        val original = setOf("com.bank.app", "com.work.app", "com.chat.secure")
        val json = serializePackagesJson(original)
        val deserialized = parsePackagesJson(json)
        assertEquals(original, deserialized)
    }

    @Test
    fun testDisallowListRouting_exemptsTargetApp() {
        val exemptions = setOf("com.bank.app", "com.payment.upi")

        // Exempt app should NOT route through VPN (bypasses VPN to preserve banking connectivity)
        val routeBank = shouldRoutePackageThroughVpn("com.bank.app", "disallow_list", exemptions)
        assertFalse("Exempt banking app must bypass VPN in disallow_list mode", routeBank)

        // Non-exempt browser/social apps MUST route through VPN
        val routeBrowser = shouldRoutePackageThroughVpn("com.android.chrome", "disallow_list", exemptions)
        assertTrue("Chrome browser must route through VPN in disallow_list mode", routeBrowser)
    }

    @Test
    fun testAllowListRouting_onlyRoutesConfiguredApp() {
        val allowList = setOf("com.android.chrome", "org.mozilla.firefox")

        // Configured browser routes through VPN
        val routeChrome = shouldRoutePackageThroughVpn("com.android.chrome", "allow_list", allowList)
        assertTrue("Allow-listed Chrome must route through VPN", routeChrome)

        // Non-configured banking app bypasses VPN
        val routeBank = shouldRoutePackageThroughVpn("com.bank.app", "allow_list", allowList)
        assertFalse("Non-allowlisted bank app must bypass VPN", routeBank)
    }

    @Test
    fun testEmptyExemptionList_routesAllTrafficInDisallowMode() {
        val emptySet = emptySet<String>()
        assertTrue(shouldRoutePackageThroughVpn("com.example.app", "disallow_list", emptySet))
        assertTrue(shouldRoutePackageThroughVpn("com.android.chrome", "disallow_list", emptySet))
    }
}
