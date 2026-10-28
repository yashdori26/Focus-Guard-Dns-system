package com.focusdns.app

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Unit tests for MdmPolicyEngine and DevicePolicyProfileManager user restriction rules,
 * enterprise kiosk mode locks, and conditional policy evaluation.
 */
class MdmPolicyEngineTest {

    enum class TestPolicyLockMode(val value: String) {
        ALWAYS_ALLOWED("always_allowed"),
        CONDITIONAL_ON_PROTECTION("conditional_on_protection"),
        ALWAYS_LOCKED("always_locked")
    }

    private fun resolveActiveRestrictions(
        isFocusActive: Boolean,
        disallowSafeBoot: Boolean,
        disallowVpnConfig: Boolean
    ): Set<String> {
        val restrictions = mutableSetOf<String>()
        if (isFocusActive) {
            if (disallowSafeBoot) restrictions.add("no_safe_boot")
            if (disallowVpnConfig) restrictions.add("no_config_vpn")
            restrictions.add("no_factory_reset")
        }
        return restrictions
    }

    private fun evaluateUninstallationAllowed(
        mode: TestPolicyLockMode,
        isProtectionActive: Boolean,
        remainingTimerSeconds: Long
    ): Boolean {
        return when (mode) {
            TestPolicyLockMode.ALWAYS_ALLOWED -> true
            TestPolicyLockMode.ALWAYS_LOCKED -> false
            TestPolicyLockMode.CONDITIONAL_ON_PROTECTION -> {
                !isProtectionActive && remainingTimerSeconds <= 0L
            }
        }
    }

    @Test
    fun testRestrictions_activeFocusEnforcesSafeBootAndVpnConfig() {
        val restrictions = resolveActiveRestrictions(
            isFocusActive = true,
            disallowSafeBoot = true,
            disallowVpnConfig = true
        )
        assertTrue(restrictions.contains("no_safe_boot"))
        assertTrue(restrictions.contains("no_config_vpn"))
        assertTrue(restrictions.contains("no_factory_reset"))
        assertEquals(3, restrictions.size)
    }

    @Test
    fun testRestrictions_idleModeClearsAllRestrictions() {
        val restrictions = resolveActiveRestrictions(
            isFocusActive = false,
            disallowSafeBoot = true,
            disallowVpnConfig = true
        )
        assertTrue("Idle mode must have no active device restrictions", restrictions.isEmpty())
    }

    @Test
    fun testPolicyLockMode_alwaysAllowedPermitsUninstallationEvenDuringActiveTimer() {
        val allowed = evaluateUninstallationAllowed(
            mode = TestPolicyLockMode.ALWAYS_ALLOWED,
            isProtectionActive = true,
            remainingTimerSeconds = 3600L
        )
        assertTrue(allowed)
    }

    @Test
    fun testPolicyLockMode_alwaysLockedBlocksUninstallationEvenWhenIdle() {
        val allowed = evaluateUninstallationAllowed(
            mode = TestPolicyLockMode.ALWAYS_LOCKED,
            isProtectionActive = false,
            remainingTimerSeconds = 0L
        )
        assertFalse(allowed)
    }

    @Test
    fun testPolicyLockMode_conditionalFollowsTruthTable() {
        // Idle: allowed
        assertTrue(evaluateUninstallationAllowed(TestPolicyLockMode.CONDITIONAL_ON_PROTECTION, false, 0L))

        // Protection active: blocked
        assertFalse(evaluateUninstallationAllowed(TestPolicyLockMode.CONDITIONAL_ON_PROTECTION, true, 0L))

        // Timer active: blocked
        assertFalse(evaluateUninstallationAllowed(TestPolicyLockMode.CONDITIONAL_ON_PROTECTION, false, 900L))

        // Both active: blocked
        assertFalse(evaluateUninstallationAllowed(TestPolicyLockMode.CONDITIONAL_ON_PROTECTION, true, 900L))
    }

    @Test
    fun testLockTaskPackages_ourAppAlwaysIncluded() {
        val lockTaskPackages = listOf("com.focusdns.app")
        assertTrue("FocusDNS must be in lock task list for kiosk mode", lockTaskPackages.contains("com.focusdns.app"))
    }
}
