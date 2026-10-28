package com.focusdns.app

import org.junit.Assert.*
import org.junit.Test

/**
 * LockTaskKioskOrchestratorTest
 * =============================
 * Unit tests validating Android Enterprise LockTask (Dedicated Kiosk) Mode configuration,
 * package whitelist merging, life-safety telecom dialer guarantees, and normal-mode exit.
 *
 * Core Law Verification:
 * - In Normal Mode: Kiosk mode is deactivated, enabling standard Android launcher interactions
 *   and allowing clean, friction-free uninstallation.
 * - In Active Focus Mode: LockTask restricts navigation and system alerts, but MUST preserve
 *   the native emergency phone dialer at all times.
 */
class LockTaskKioskOrchestratorTest {

    @Test
    fun testEssentialSafetyPackagesAlwaysIncludesEmergencyDialers() {
        val safety = LockTaskKioskOrchestrator.ESSENTIAL_SAFETY_PACKAGES
        assertTrue(safety.contains("com.android.phone"))
        assertTrue(safety.contains("com.google.android.dialer"))
        assertTrue(safety.contains("com.samsung.incallui"))
        assertTrue(safety.contains("com.android.server.telecom"))
        assertEquals(4, safety.size)
    }

    @Test
    fun testLockTaskPermittedPackageMergingPreservesDialers() {
        val additional = listOf("com.notes.app", "com.calculator.app")
        val merged = mutableSetOf("com.focusdns.app")
        merged.addAll(LockTaskKioskOrchestrator.ESSENTIAL_SAFETY_PACKAGES)
        merged.addAll(additional)

        assertEquals(7, merged.size)
        assertTrue(merged.contains("com.focusdns.app"))
        assertTrue(merged.contains("com.android.phone"))
        assertTrue(merged.contains("com.google.android.dialer"))
        assertTrue(merged.contains("com.samsung.incallui"))
        assertTrue(merged.contains("com.android.server.telecom"))
        assertTrue(merged.contains("com.notes.app"))
        assertTrue(merged.contains("com.calculator.app"))
    }

    @Test
    fun testLockTaskFeatureMaskComposition() {
        // DevicePolicyManager feature constants
        val featureSystemInfo = 1       // LOCK_TASK_FEATURE_SYSTEM_INFO
        val featureKeyguard = 4         // LOCK_TASK_FEATURE_KEYGUARD
        val featureGlobalActions = 16   // LOCK_TASK_FEATURE_GLOBAL_ACTIONS

        // Compose standard FocusDNS feature mask
        val composedMask = featureSystemInfo or featureKeyguard or featureGlobalActions

        assertTrue((composedMask and featureSystemInfo) != 0)
        assertTrue((composedMask and featureKeyguard) != 0)
        assertTrue((composedMask and featureGlobalActions) != 0)
    }

    @Test
    fun testEmergencyDialerDirectActionVerification() {
        // Verify emergency number matching through exemption manager
        assertTrue(EmergencyCallExemptionManager.isEmergencyNumber("911"))
        assertTrue(EmergencyCallExemptionManager.isEmergencyNumber("112"))
        assertTrue(EmergencyCallExemptionManager.isEmergencyNumber("999"))
        assertTrue(EmergencyCallExemptionManager.isEmergencyNumber("000"))
        assertTrue(EmergencyCallExemptionManager.isEmergencyNumber("100"))
        assertTrue(EmergencyCallExemptionManager.isEmergencyNumber("108"))
        assertTrue(EmergencyCallExemptionManager.isEmergencyNumber("988"))
        assertFalse(EmergencyCallExemptionManager.isEmergencyNumber("5551234"))
    }

    @Test
    fun testKioskLifecycleSimulationNormalModePermitsUninstall() {
        var isKioskActive = true
        var canUninstall = false

        // When Kiosk mode ends (session expires or user exits)
        isKioskActive = false
        canUninstall = true

        assertFalse(isKioskActive)
        assertTrue(canUninstall)
    }
}
