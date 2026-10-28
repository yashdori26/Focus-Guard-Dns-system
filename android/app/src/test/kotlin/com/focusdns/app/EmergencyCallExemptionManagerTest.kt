package com.focusdns.app

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Unit tests for EmergencyCallExemptionManager verifying life-safety
 * emergency number recognition and telecom package exemptions.
 */
class EmergencyCallExemptionManagerTest {

    @Test
    fun testEmergencyNumbers_globalStandardsRecognized() {
        // Global standards
        assertTrue(EmergencyCallExemptionManager.isEmergencyNumber("911"))
        assertTrue(EmergencyCallExemptionManager.isEmergencyNumber("112"))
        assertTrue(EmergencyCallExemptionManager.isEmergencyNumber("999"))
        assertTrue(EmergencyCallExemptionManager.isEmergencyNumber("000"))
        assertTrue(EmergencyCallExemptionManager.isEmergencyNumber("111"))

        // India emergency services
        assertTrue(EmergencyCallExemptionManager.isEmergencyNumber("100"))
        assertTrue(EmergencyCallExemptionManager.isEmergencyNumber("101"))
        assertTrue(EmergencyCallExemptionManager.isEmergencyNumber("102"))
        assertTrue(EmergencyCallExemptionManager.isEmergencyNumber("108"))

        // Mental health / crisis helpline
        assertTrue(EmergencyCallExemptionManager.isEmergencyNumber("988"))

        // Formatting variations
        assertTrue(EmergencyCallExemptionManager.isEmergencyNumber(" 911 "))
        assertTrue(EmergencyCallExemptionManager.isEmergencyNumber("+112"))
    }

    @Test
    fun testNonEmergencyNumbers_notExempt() {
        assertFalse(EmergencyCallExemptionManager.isEmergencyNumber("1234567890"))
        assertFalse(EmergencyCallExemptionManager.isEmergencyNumber("+1-555-867-5309"))
        assertFalse(EmergencyCallExemptionManager.isEmergencyNumber("411"))
        assertFalse(EmergencyCallExemptionManager.isEmergencyNumber(""))
        assertFalse(EmergencyCallExemptionManager.isEmergencyNumber(null))
    }

    @Test
    fun testEmergencyPackages_nativeDialersAndTelecom() {
        assertTrue(EmergencyCallExemptionManager.isEmergencyPackage("com.android.phone"))
        assertTrue(EmergencyCallExemptionManager.isEmergencyPackage("com.android.server.telecom"))
        assertTrue(EmergencyCallExemptionManager.isEmergencyPackage("com.google.android.dialer"))
        assertTrue(EmergencyCallExemptionManager.isEmergencyPackage("com.samsung.android.incallui"))
        assertTrue(EmergencyCallExemptionManager.isEmergencyPackage("com.samsung.android.dialer"))
        assertTrue(EmergencyCallExemptionManager.isEmergencyPackage("com.android.emergency"))
        assertTrue(EmergencyCallExemptionManager.isEmergencyPackage("com.google.android.apps.safetyhub"))
    }

    @Test
    fun testNonEmergencyPackages_notExempt() {
        assertFalse(EmergencyCallExemptionManager.isEmergencyPackage("com.android.chrome"))
        assertFalse(EmergencyCallExemptionManager.isEmergencyPackage("com.instagram.android"))
        assertFalse(EmergencyCallExemptionManager.isEmergencyPackage("com.reddit.frontpage"))
        assertFalse(EmergencyCallExemptionManager.isEmergencyPackage("com.google.android.youtube"))
        assertFalse(EmergencyCallExemptionManager.isEmergencyPackage(""))
        assertFalse(EmergencyCallExemptionManager.isEmergencyPackage(null))
    }
}
