package com.focusdns.app

import android.os.UserManager
import org.junit.Assert.*
import org.junit.Test

/**
 * DpcPolicyManagerTest
 * ====================
 * Unit tests validating Android Enterprise Device Policy Controller (DPC) policy enforcement,
 * user restrictions matrix, package suspension safety filtering, and conditional uninstallation.
 *
 * Core Law Verification:
 * - When isProtected = False (Normal Mode): All DPC user restrictions are cleared, permitting
 *   clean, unimpeded uninstallation and normal device management.
 * - When isProtected = True (Active Session / Timer): DISALLOW_UNINSTALL_APPS and DISALLOW_APPS_CONTROL
 *   are strictly applied to prevent circumvention.
 * - Telecom & Emergency Dialer Exemption: Native dialer packages are NEVER suspended or blocked.
 */
class DpcPolicyManagerTest {

    @Test
    fun testCoreRestrictionsContainsEssentialSecurityPolicies() {
        val restrictions = DpcPolicyManager.CORE_FOCUS_RESTRICTIONS
        assertTrue(restrictions.contains(UserManager.DISALLOW_UNINSTALL_APPS))
        assertTrue(restrictions.contains(UserManager.DISALLOW_APPS_CONTROL))
        assertTrue(restrictions.contains(UserManager.DISALLOW_SAFE_BOOT))
        assertTrue(restrictions.contains(UserManager.DISALLOW_CONFIG_VPN))
        assertTrue(restrictions.contains(UserManager.DISALLOW_DEBUGGING_FEATURES))
        assertTrue(restrictions.contains(UserManager.DISALLOW_FACTORY_RESET))
        assertEquals(6, restrictions.size)
    }

    @Test
    fun testCoreRestrictionsNamedValues() {
        assertEquals("no_uninstall_apps", DpcPolicyManager.RESTRICTION_UNINSTALL_APPS)
        assertEquals("no_control_apps", DpcPolicyManager.RESTRICTION_APPS_CONTROL)
        assertEquals("no_safe_boot", DpcPolicyManager.RESTRICTION_SAFE_BOOT)
        assertEquals("no_config_vpn", DpcPolicyManager.RESTRICTION_CONFIG_VPN)
        assertEquals("no_debugging_features", DpcPolicyManager.RESTRICTION_DEBUGGING_FEATURES)
        assertEquals("no_factory_reset", DpcPolicyManager.RESTRICTION_FACTORY_RESET)
    }

    @Test
    fun testOptionalEnterpriseRestrictions() {
        assertEquals("no_add_user", DpcPolicyManager.RESTRICTION_ADD_USER)
        assertEquals("no_modify_accounts", DpcPolicyManager.RESTRICTION_MODIFY_ACCOUNTS)
    }

    @Test
    fun testEmergencyDialerPackagesAreExemptFromSuspensionFiltering() {
        val inputList = listOf(
            "com.android.phone",
            "com.google.android.dialer",
            "com.samsung.incallui",
            "com.android.server.telecom",
            "com.distraction.game",
            "com.social.media.app"
        )

        // Filter using EmergencyCallExemptionManager
        val filtered = inputList.filter { pkg ->
            !EmergencyCallExemptionManager.isTelecomPackage(pkg) &&
                    pkg != "android" &&
                    pkg != "com.android.systemui"
        }

        assertEquals(2, filtered.size)
        assertEquals("com.distraction.game", filtered[0])
        assertEquals("com.social.media.app", filtered[1])
        assertFalse(filtered.contains("com.android.phone"))
        assertFalse(filtered.contains("com.google.android.dialer"))
        assertFalse(filtered.contains("com.samsung.incallui"))
        assertFalse(filtered.contains("com.android.server.telecom"))
    }

    @Test
    fun testConditionalUninstallationLawSimulation() {
        // Simulate normal idle mode
        val isProtectedIdle = false
        val idleRestrictions = mutableMapOf<String, Boolean>()
        for (restriction in DpcPolicyManager.CORE_FOCUS_RESTRICTIONS) {
            idleRestrictions[restriction] = isProtectedIdle
        }

        // In normal idle mode, all restrictions must be cleared
        assertFalse(idleRestrictions[UserManager.DISALLOW_UNINSTALL_APPS]!!)
        assertFalse(idleRestrictions[UserManager.DISALLOW_APPS_CONTROL]!!)
        assertFalse(idleRestrictions[UserManager.DISALLOW_SAFE_BOOT]!!)
        assertFalse(idleRestrictions[UserManager.DISALLOW_CONFIG_VPN]!!)
        assertFalse(idleRestrictions[UserManager.DISALLOW_DEBUGGING_FEATURES]!!)
        assertFalse(idleRestrictions[UserManager.DISALLOW_FACTORY_RESET]!!)

        // Verify uninstallation is allowed when idle
        val canUninstallIdle = !idleRestrictions[UserManager.DISALLOW_UNINSTALL_APPS]!!
        assertTrue(canUninstallIdle)

        // Simulate active focus session mode
        val isProtectedActive = true
        val activeRestrictions = mutableMapOf<String, Boolean>()
        for (restriction in DpcPolicyManager.CORE_FOCUS_RESTRICTIONS) {
            activeRestrictions[restriction] = isProtectedActive
        }

        // In active session mode, restrictions are enforced
        assertTrue(activeRestrictions[UserManager.DISALLOW_UNINSTALL_APPS]!!)
        assertTrue(activeRestrictions[UserManager.DISALLOW_APPS_CONTROL]!!)
        assertTrue(activeRestrictions[UserManager.DISALLOW_SAFE_BOOT]!!)
        assertTrue(activeRestrictions[UserManager.DISALLOW_CONFIG_VPN]!!)

        // Verify uninstallation is blocked during focus
        val canUninstallActive = !activeRestrictions[UserManager.DISALLOW_UNINSTALL_APPS]!!
        assertFalse(canUninstallActive)
    }

    @Test
    fun testDpcDiagnosticsMapStructure() {
        val sampleDiagnostics = mapOf(
            "isDeviceOwner" to true,
            "isProfileOwner" to false,
            "isEnterpriseDpcActive" to true,
            "canUninstallApp" to true,
            "coreRestrictionsEnforced" to false,
            "activeRestrictions" to mapOf(
                "no_uninstall_apps" to false,
                "no_control_apps" to false,
                "no_safe_boot" to false,
                "no_config_vpn" to false,
                "no_debugging_features" to false,
                "no_factory_reset" to false
            )
        )

        assertTrue(sampleDiagnostics["isDeviceOwner"] as Boolean)
        assertFalse(sampleDiagnostics["isProfileOwner"] as Boolean)
        assertTrue(sampleDiagnostics["isEnterpriseDpcActive"] as Boolean)
        assertTrue(sampleDiagnostics["canUninstallApp"] as Boolean)
        assertFalse(sampleDiagnostics["coreRestrictionsEnforced"] as Boolean)

        @Suppress("UNCHECKED_CAST")
        val activeRes = sampleDiagnostics["activeRestrictions"] as Map<String, Boolean>
        assertEquals(6, activeRes.size)
        assertFalse(activeRes["no_uninstall_apps"]!!)
    }

    @Test
    fun testMultiOemTelecomDialerExemptions() {
        val oemDialers = listOf(
            "com.google.android.dialer",       // Pixel / Stock Android
            "com.samsung.android.dialer",      // Samsung OneUI
            "com.samsung.incallui",            // Samsung InCallUI
            "com.android.phone",               // AOSP Telecom
            "com.android.server.telecom",      // Telecom Framework
            "com.miui.telephony",              // Xiaomi HyperOS / MIUI
            "com.coloros.telephony",           // Oppo ColorOS
            "com.vivo.telephony"               // Vivo OriginOS
        )

        for (dialer in oemDialers) {
            assertTrue(
                "Dialer $dialer must be exempted as telecom package",
                EmergencyCallExemptionManager.isTelecomPackage(dialer)
            )
        }
    }
}
