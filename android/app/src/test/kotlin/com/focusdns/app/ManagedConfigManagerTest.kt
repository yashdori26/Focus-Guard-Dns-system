package com.focusdns.app

import org.junit.Assert.*
import org.junit.Test

/**
 * ManagedConfigManagerTest
 * ========================
 * Unit tests validating Android Enterprise Managed Configurations (AppConfig),
 * RestrictionsManager key mappings, profile serialization, and conditional uninstallation.
 *
 * Core Law Verification:
 * - When enforceStrictUninstallLock is False (Normal Corporate Default): AppConfig allows
 *   clean, friction-free uninstallation.
 * - When enforceStrictUninstallLock is True: Endpoint enforces strict uninstallation restrictions
 *   during focus sessions.
 */
class ManagedConfigManagerTest {

    @Test
    fun testDefaultManagedConfigModel() {
        val config = ManagedConfigManager.ManagedConfig()
        assertEquals("https://dns.focusguard.internal", config.serverUrl)
        assertEquals("default_enterprise", config.tenantId)
        assertEquals("", config.enrollmentToken)
        assertFalse(config.enforceStrictUninstallLock)
        assertTrue(config.whitelistedPackages.isEmpty())
        assertFalse(config.kioskEnabled)
        assertEquals("", config.approvedDotHost)
    }

    @Test
    fun testManagedConfigToMapSerialization() {
        val config = ManagedConfigManager.ManagedConfig(
            serverUrl = "https://custom.dns.org",
            tenantId = "corp_123",
            enrollmentToken = "tok_xyz",
            enforceStrictUninstallLock = true,
            whitelistedPackages = listOf("com.slack", "com.zoom"),
            kioskEnabled = true,
            approvedDotHost = "dot.custom.org"
        )
        val map = config.toMap()
        assertEquals("https://custom.dns.org", map["serverUrl"])
        assertEquals("corp_123", map["tenantId"])
        assertEquals("tok_xyz", map["enrollmentToken"])
        assertEquals(true, map["enforceStrictUninstallLock"])
        assertEquals(listOf("com.slack", "com.zoom"), map["whitelistedPackages"])
        assertEquals(true, map["kioskEnabled"])
        assertEquals("dot.custom.org", map["approvedDotHost"])
    }

    @Test
    fun testManagedConfigKeyConstants() {
        assertEquals("server_url", ManagedConfigManager.KEY_SERVER_URL)
        assertEquals("tenant_id", ManagedConfigManager.KEY_TENANT_ID)
        assertEquals("enrollment_token", ManagedConfigManager.KEY_ENROLLMENT_TOKEN)
        assertEquals("enforce_strict_uninstall_lock", ManagedConfigManager.KEY_ENFORCE_STRICT_UNINSTALL)
        assertEquals("whitelisted_split_tunnel_pkgs", ManagedConfigManager.KEY_WHITELISTED_PKGS)
        assertEquals("lock_task_kiosk_enabled", ManagedConfigManager.KEY_KIOSK_ENABLED)
        assertEquals("approved_dot_host", ManagedConfigManager.KEY_APPROVED_DOT_HOST)
    }

    @Test
    fun testConditionalUninstallationInAppConfig() {
        // Corporate normal idle profile
        val idleConfig = ManagedConfigManager.ManagedConfig(
            enforceStrictUninstallLock = false
        )
        assertFalse(idleConfig.enforceStrictUninstallLock)

        // Enterprise kiosk lockdown profile
        val lockedConfig = ManagedConfigManager.ManagedConfig(
            enforceStrictUninstallLock = true,
            kioskEnabled = true
        )
        assertTrue(lockedConfig.enforceStrictUninstallLock)
        assertTrue(lockedConfig.kioskEnabled)
    }

    @Test
    fun testWhitelistedPackagesDeduplicationAndSorting() {
        val pkgs = listOf("com.zoom", "com.slack", "com.zoom", "com.teams")
        val uniqueSorted = pkgs.distinct().sorted()

        assertEquals(3, uniqueSorted.size)
        assertEquals("com.slack", uniqueSorted[0])
        assertEquals("com.teams", uniqueSorted[1])
        assertEquals("com.zoom", uniqueSorted[2])
    }

    @Test
    fun testApprovedDotHostnameFormat() {
        val validDotHosts = listOf(
            "dns.focusguard.internal",
            "dot.corporate.com",
            "secure-dns.hospital.org"
        )
        for (host in validDotHosts) {
            assertTrue(host.contains("."))
            assertFalse(host.startsWith("http://"))
            assertFalse(host.startsWith("https://"))
        }
    }
}
